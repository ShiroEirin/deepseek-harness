/**
 * Structural secret redaction for settings values. `role('secret')` fields are
 * removed from a value before it crosses a wire boundary; a sidecar records
 * each schema-declared secret position and whether it currently holds a value,
 * so a configuration surface can render a write-only input without ever
 * receiving the secret itself.
 * @module @deepseek-ai/dsh-settings/redact
 */

import type z from 'schemastery'

/**
 * Minimal structural view of a live schemastery node. Only the relations the
 * redactor walks are named; everything else on the instance is ignored.
 */
interface SchemaNode {
  type?: string
  meta?: { role?: unknown }
  /** `object` properties, keyed by property name. */
  dict?: Record<string, SchemaNode>
  /** `dict`/`array` element schema. */
  inner?: SchemaNode
  /** `union` member schemas. */
  list?: SchemaNode[]
}

/** One schema-declared secret position inside a redacted value. */
export interface RedactedSecret {
  /** Path from the section root to the removed field (concrete dict keys and array indexes included). */
  path: string[]
  /** Whether the field held a value before redaction. */
  set: boolean
}

/**
 * One schema position the walker could not structurally reach. A secret
 * declared only behind such a node (union/intersection/transform/...) is
 * returned verbatim and recorded here — a wire MUST NOT ship a value whose
 * `unreachable` is non-empty without a separate audit (upstream #410).
 */
export interface UnreachableSecret {
  /** Path from the section root to the unwalkable schema node. */
  path: string[]
  /** The schemastery node type that was not walked. */
  type: string | undefined
}

/** A value with every `role('secret')` field removed, plus the removal record. */
export interface RedactedValue {
  /** Detached copy of the input with secret fields absent. */
  value: unknown
  /**
   * Every reachable secret position: object properties always (even unset, so
   * a form knows the slot exists), dict entries and array items only where the
   * value has them.
   */
  secrets: RedactedSecret[]
  /**
   * Schema nodes the walker could not structurally walk. Non-empty means some
   * part of the value crossed the boundary without redaction — the caller
   * must treat that as a redaction failure, not a pass.
   */
  unreachable: UnreachableSecret[]
}

/** Whether a value is a plain data object the walker may recurse into. */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * Schemastery leaf node types that carry no structure a secret could hide
 * behind. `role('secret')` is only meaningful on a value slot, and every slot
 * is intercepted before the switch; these leaves pass through safely.
 */
const SAFE_LEAF_TYPES = new Set([
  'string',
  'number',
  'boolean',
  'any',
  'unknown',
  'never',
  'const',
  'literal',
])

/**
 * Whether a secret-role field is reachable anywhere through this schema node.
 * Used to decide whether an unwalkable node (union) can hide a secret: a node
 * whose whole subtree declares no secret is a plain value carrier and passes
 * through; one that does is fail-closed (upstream #410).
 */
function declaresSecret(node: SchemaNode | undefined): boolean {
  if (!node) return false
  if (node.meta?.role === 'secret') return true
  if (node.dict && Object.values(node.dict).some(declaresSecret)) return true
  if (node.inner && declaresSecret(node.inner)) return true
  if (node.list && node.list.some(declaresSecret)) return true
  return false
}

function walk(
  node: SchemaNode | undefined,
  value: unknown,
  path: string[],
  secrets: RedactedSecret[],
  unreachable: UnreachableSecret[],
): unknown {
  if (node === undefined) return value
  if (node.meta?.role === 'secret') {
    secrets.push({ path, set: value !== undefined })
    return undefined
  }
  switch (node.type) {
    case 'object': {
      const properties = node.dict ?? {}
      const source = isRecord(value) ? value : undefined
      const rebuilt: Record<string, unknown> = {}
      if (source !== undefined) {
        for (const [key, entry] of Object.entries(source)) {
          if (key in properties) continue
          rebuilt[key] = entry
        }
      }
      for (const [key, child] of Object.entries(properties)) {
        const stripped = walk(child, source?.[key], [...path, key], secrets, unreachable)
        if (stripped !== undefined) rebuilt[key] = stripped
      }
      return source === undefined && Object.keys(rebuilt).length === 0 ? value : rebuilt
    }
    case 'dict': {
      if (!isRecord(value)) return value
      const rebuilt: Record<string, unknown> = {}
      for (const [key, entry] of Object.entries(value)) {
        const stripped = walk(node.inner, entry, [...path, key], secrets, unreachable)
        if (stripped !== undefined) rebuilt[key] = stripped
      }
      return rebuilt
    }
    case 'array': {
      if (!Array.isArray(value)) return value
      return value.map((entry, index) => walk(node.inner, entry, [...path, String(index)], secrets, unreachable))
    }
    case 'union': {
      // A union whose members declare no secret anywhere is a plain value
      // carrier (preset / effort / retry selectors): pass it through
      // untouched. Only when a secret role is reachable through a member is
      // the node unwalkable in the fail-closed sense (upstream #410).
      if (!declaresSecret(node)) return value
      unreachable.push({ path, type: node.type })
      console.warn(
        `[dsh-settings] redact: cannot structurally walk schema node "${node.type ?? 'unknown'}" at "${path.join('.')}" — ` +
          'a secret declared behind this node is NOT redacted; refuse to ship this value to the wire',
      )
      return value
    }
    default:
      // Leaf scalar types carry no structure a secret could hide behind; pass
      // them through. Any OTHER unwalked node (union/intersection/transform/
      // unknown future types) is a fail-closed posture (upstream #410): a
      // secret reachable only through it is returned verbatim here, so record
      // it loudly instead of silently — the caller can refuse to ship a value
      // whose `unreachable` is non-empty, and no leak passes unnoticed.
      if (SAFE_LEAF_TYPES.has(node.type ?? '')) return value
      unreachable.push({ path, type: node.type })
      console.warn(
        `[dsh-settings] redact: cannot structurally walk schema node "${node.type ?? 'unknown'}" at "${path.join('.')}" — ` +
          'a secret declared behind this node is NOT redacted; refuse to ship this value to the wire',
      )
      return value
  }
}

/**
 * Remove every `role('secret')` field a schema declares from a value. The
 * walker follows `object`, `dict`, and `array` containers; a secret must be
 * declared directly on a field reachable through those containers (a secret
 * buried inside a union branch or transform is not reachable and must not be
 * modeled that way). The input is never mutated.
 * @param schema - live schemastery schema describing the value.
 * @param value - the value to strip; `undefined` yields an empty record with
 *   object-property secret slots still enumerated.
 * @returns the stripped detached value and the ordered secret positions.
 */
export function redactSecrets(schema: z<never>, value: unknown): RedactedValue {
  const secrets: Array<RedactedSecret> = []
  const unreachable: Array<UnreachableSecret> = []
  const stripped = walk(schema, value, [], secrets, unreachable)
  return { value: stripped, secrets, unreachable }
}
