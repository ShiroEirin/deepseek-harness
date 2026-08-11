/**
 * Pure folds for durable provider-reported token usage and context occupancy.
 */

import { z } from 'zod'
import type { TokenUsage } from '@deepseek-ai/dsh-llm'
import type { SessionEvent } from '@deepseek-ai/dsh-session'
import type { ProjectionDefinition } from '@deepseek-ai/dsh-session-projection'
import type { ContextPressureProjection, TokenUsageProjection } from './projection.ts'
import { foldSurfaceProjection } from './surface-projection.ts'
import type { ShadowPriceClaim } from './surface-projection.ts'

interface UsageSample {
  turn: number
  step: number
  buckets: TokenUsageProjection
}

interface TokenUsageState {
  totals: TokenUsageProjection
  last: UsageSample | null
}

const zeroBuckets = (): TokenUsageProjection => ({
  uncachedInputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
})

const bucketsFrom = (usage: TokenUsage): TokenUsageProjection => ({
  uncachedInputTokens: usage.inputTokens,
  outputTokens: usage.outputTokens,
  cacheReadTokens: usage.cacheReadTokens ?? 0,
  cacheWriteTokens: usage.cacheWriteTokens ?? 0,
})

const bucketsEqual = (left: TokenUsageProjection, right: TokenUsageProjection): boolean =>
  left.uncachedInputTokens === right.uncachedInputTokens
  && left.outputTokens === right.outputTokens
  && left.cacheReadTokens === right.cacheReadTokens
  && left.cacheWriteTokens === right.cacheWriteTokens

const addReplacing = (
  totals: TokenUsageProjection,
  previous: TokenUsageProjection | undefined,
  next: TokenUsageProjection,
): TokenUsageProjection => ({
  uncachedInputTokens: totals.uncachedInputTokens - (previous?.uncachedInputTokens ?? 0) + next.uncachedInputTokens,
  outputTokens: totals.outputTokens - (previous?.outputTokens ?? 0) + next.outputTokens,
  cacheReadTokens: totals.cacheReadTokens - (previous?.cacheReadTokens ?? 0) + next.cacheReadTokens,
  cacheWriteTokens: totals.cacheWriteTokens - (previous?.cacheWriteTokens ?? 0) + next.cacheWriteTokens,
})

const projectionSchema = z.object({
  uncachedInputTokens: z.number().int().nonnegative(),
  outputTokens: z.number().int().nonnegative(),
  cacheReadTokens: z.number().int().nonnegative(),
  cacheWriteTokens: z.number().int().nonnegative(),
}).strict()

// Cast for the optional values: under exactOptionalPropertyTypes zod infers
// `number | undefined` where the interface declares absent-or-number fields.
const pressureSchema = z.object({
  pressureTokens: z.number().int().nonnegative().optional(),
  projectedTokens: z.number().int().nonnegative().optional(),
  contextWindow: z.number().int().positive().optional(),
}).strict() as unknown as z.ZodType<ContextPressureProjection>

/** Prompt-side pressure of one request: input plus cache traffic, no output. */
const pressureFrom = (usage: TokenUsage): number =>
  usage.inputTokens + (usage.cacheReadTokens ?? 0) + (usage.cacheWriteTokens ?? 0)

/** The usage a chunk or finalized message reports for its step, if any. */
const usageOf = (event: SessionEvent): TokenUsage | undefined =>
  event.type === 'assistant/chunk' && event.data.chunk.type === 'usage'
    ? event.data.chunk.usage
    : event.type === 'assistant/message'
      ? event.data.usage
      : undefined

/** Whether a value is a safe non-negative integer count. */
function isNonNegativeInt(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}

/**
 * Input defence for forged/poisoned usage records (upstream #443). A session
 * log is writable storage, so a negative/string/missing token field must not
 * propagate into the projection and explode the view's zod validation. An
 * invalid record is skipped entirely — mirroring `measure()`'s tolerance —
 * so the read path never crashes and no dirty value enters the cached state.
 */
function sanitizeUsage(usage: TokenUsage): TokenUsage | undefined {
  if (
    !isNonNegativeInt(usage.inputTokens) ||
    !isNonNegativeInt(usage.outputTokens)
  )
    return undefined
  if (
    usage.cacheReadTokens !== undefined &&
    !isNonNegativeInt(usage.cacheReadTokens)
  )
    return undefined
  if (
    usage.cacheWriteTokens !== undefined &&
    !isNonNegativeInt(usage.cacheWriteTokens)
  )
    return undefined
  return usage
}

/**
 * Input defence for a forged `request/context` window (upstream #443): the
 * projection schema demands a positive integer, so a negative/zero/string
 * value would blow up the view. `undefined` (absent) is legal; anything else
 * must be a positive safe integer.
 */
function sanitizeContextWindow(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0
    ? value
    : undefined
}

/**
 * Context-occupancy state: the two independent last-wins records plus the
 * O(1) running surface total needed to carry the newest sample forward.
 */
interface ContextPressureState {
  contextWindow?: number
  pressureTokens?: number
  /** Running heuristic total over the current surface ({@link foldSurfaceProjection}). */
  surfaceTokens: number
  /** {@link surfaceTokens} at the newest usage sample; absent until one lands. */
  sampledSurfaceTokens?: number
  /** Shadow price armed by the immediately preceding metering event. */
  claim?: ShadowPriceClaim
}

/**
 * Token-meter's session projection unit.
 *
 * Usage chunks provide an early sample that survives a later request failure;
 * an assistant message provides the final sample for the same turn/step. A
 * repeated sample replaces that step's earlier value instead of double
 * counting it. The single `last` slot relies on the session-log invariant
 * that usage reports for one turn/step are adjacent: once a later step begins,
 * a legal log never reports usage for an earlier step again.
 */
export const tokenUsageProjectionDefinition:
ProjectionDefinition<'tokenUsage', TokenUsageState> = {
  key: 'tokenUsage',
  schema: projectionSchema,
  init: () => { return ({ totals: zeroBuckets(), last: null }) },
  apply: (state, event) => {
    let turn: number
    let step: number
    let usage: TokenUsage
    if (event.type === 'assistant/chunk' && event.data.chunk.type === 'usage') {
      ;({ turn, step } = event.data)
      usage = event.data.chunk.usage
    } else if (event.type === 'assistant/message' && event.data.usage !== undefined) {
      ;({ turn, step, usage } = event.data)
    } else {
      return state
    }

    // Forged/poisoned usage must not reach the projection (upstream #443):
    // skip the event so the view's zod validation never sees a bad number.
    const clean = sanitizeUsage(usage)
    if (clean === undefined) return state

    const buckets = bucketsFrom(clean)
    const previous = state.last !== null
      && state.last.turn === turn
      && state.last.step === step
      ? state.last.buckets
      : undefined
    if (previous !== undefined && bucketsEqual(previous, buckets)) return state

    return {
      totals: addReplacing(state.totals, previous, buckets),
      last: { turn, step, buckets },
    }
  },
  view: state => state.totals,
  stateVersion: 1,
}

/**
 * Token-meter's context-occupancy projection unit.
 *
 * Independent last-wins slots: the newest usage sample supplies the provider
 * numerator, the newest `request/context` record the denominator. Both are
 * whole values, so replay order alone decides the result and no cross-field
 * consistency is claimed — the pair is explicitly not one atomic request
 * observation (see {@link ContextPressureProjection}).
 *
 * `pressureTokens` is prompt-side only, so it holds still while a turn streams
 * and steps forward once the next request reports its usage. Because nothing
 * but a request reports usage, it also cannot see a compaction: the fold
 * therefore carries a running surface total alongside it and publishes
 * `projectedTokens` — the sample plus the surface's signed movement since it
 * was taken — so occupancy answers for the next request rather than the last
 * one. The total rides {@link foldSurfaceProjection}, so the state stays O(1)
 * and a replacement shrinks it by its logged shadow price. A replacement
 * without a claim preserves the previous total. A usage sample is stamped
 * BEFORE the same event joins the surface, so an `assistant/message` anchors
 * against the surface its own request saw.
 */
export const contextPressureProjectionDefinition:
ProjectionDefinition<'contextPressure', ContextPressureState> = {
  key: 'contextPressure',
  schema: pressureSchema,
  init: () => ({ surfaceTokens: 0 }),
  apply: (state, event) => {
    const fold = foldSurfaceProjection(state.claim, event)
    let next = state
    if (event.type === 'request/context') {
      const rawContextWindow = event.data.contextWindow
      if (rawContextWindow === undefined) {
        // A route that advertises no capacity legally clears the window.
        if (state.contextWindow !== undefined) {
          const { contextWindow: _removed, ...withoutContextWindow } = next
          next = withoutContextWindow
        }
      } else {
        // Forged contextWindow (negative/zero/string) must not reach the
        // state: only a positive safe integer is accepted, anything invalid
        // is skipped entirely so the last good window survives (#443).
        const contextWindow = sanitizeContextWindow(rawContextWindow)
        if (
          contextWindow !== undefined &&
          contextWindow !== state.contextWindow
        ) {
          next = { ...next, contextWindow }
        }
      }
    }
    const usage = usageOf(event)
    if (usage !== undefined) {
      // Forged/poisoned usage must not reach the pressure fold (upstream #443).
      const clean = sanitizeUsage(usage)
      if (clean !== undefined) {
        const pressureTokens = pressureFrom(clean)
        if (
          pressureTokens !== next.pressureTokens ||
          next.sampledSurfaceTokens !== next.surfaceTokens
        ) {
          next = {
            ...next,
            pressureTokens,
            sampledSurfaceTokens: next.surfaceTokens,
          }
        }
      }
    }
    if (fold.deltaTokens !== 0) {
      next = { ...next, surfaceTokens: next.surfaceTokens + fold.deltaTokens }
    }
    // A defined fold.claim is always freshly built, so presence decides claim
    // bookkeeping: no claim before or after this event leaves `next` as is.
    if (state.claim === undefined && fold.claim === undefined) return next
    const { claim: _expired, ...withoutClaim } = next
    return fold.claim === undefined ? withoutClaim : { ...withoutClaim, claim: fold.claim }
  },
  view: ({ contextWindow, pressureTokens, surfaceTokens, sampledSurfaceTokens }) => ({
    ...contextWindow === undefined ? {} : { contextWindow },
    ...pressureTokens === undefined ? {} : { pressureTokens },
    ...pressureTokens === undefined || sampledSurfaceTokens === undefined
      ? {}
      : { projectedTokens: Math.max(0, pressureTokens + surfaceTokens - sampledSurfaceTokens) },
  }),
  stateVersion: 4,
}
