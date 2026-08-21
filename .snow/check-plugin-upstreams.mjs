// Batch-check upstream repos for locally deployed plugins: existence + pushedAt.
// Output: TSV lines "dir\towner/repo\tpushedAt|MISSING".
import { execFileSync } from 'node:child_process'

const candidates = [
  ['chat-width', 'dsh-external', 'chat-width'],
  ['dsh-activity-plugin', 'dsh-external', 'dsh-activity-plugin'],
  ['dsh-auto-approval', 'dsh-external', 'dsh-auto-approval'],
  ['dsh-bash-encoding', 'dsh-external', 'dsh-bash-encoding'],
  ['dsh-cc-tui', 'dsh-external', 'dsh-cc-tui'],
  ['dsh-checkpoint', 'dpskh', 'tool-checkpoint'],
  ['dsh-client-ui-plan-execute', 'dsh-external', 'dsh-client-ui-plan-execute'],
  ['dsh-deep-research', 'dsh-external', 'dsh-deep-research'],
  ['dsh-drag-and-drop', 'dsh-external', 'dsh-drag-and-drop'],
  ['dsh-genui', 'dsh-external', 'dsh-genui'],
  ['dsh-git-identity', 'dsh-external', 'git-identity'],
  ['dsh-git-identity', 'dsh-external', 'dsh-git-identity'],
  ['dsh-input-history', 'dsh-external', 'dsh-input-history'],
  ['dsh-inspect', 'dsh-external', 'dsh-inspect'],
  ['dsh-live-stats', 'dsh-external', 'live-stats'],
  ['dsh-live-stats', 'dsh-external', 'dsh-live-stats'],
  ['dsh-memory-evolve', 'dsh-external', 'dsh-memory-evolve'],
  ['dsh-message-edit', 'dsh-external', 'dsh-message-edit'],
  ['dsh-multimedia-webui-input', 'dsh-community', 'multimedia-webui-input'],
  ['dsh-paste-input', 'dsh-community', 'dsh-paste-input'],
  ['dsh-paste-input', 'dsh-external', 'dsh-paste-input'],
  ['dsh-plan-execute', 'dsh-external', 'dsh-plan-execute'],
  ['dsh-rewind', 'dpskh', 'tool-rewind'],
  ['dsh-session-cluster', 'dsh-external', 'dsh-session-cluster'],
  ['dsh-session-health', 'dsh-external', 'dsh-session-health'],
  ['dsh-session-search', 'dsh-external', 'dsh-session-search'],
  ['dsh-sidechain', 'dsh-external', 'dsh-sidechain'],
  ['dsh-skill-stats', 'dsh-external', 'dsh-skill-stats'],
  ['dsh-skills-manager', 'dsh-external', 'dsh-skills-manager'],
  ['dsh-skins', 'dsh-external', 'dsh-skins'],
  ['dsh-stickers', 'dsh-external', 'dsh-stickers'],
  ['dsh-tool-calculator', 'dsh-external', 'dsh-tool-calculator'],
  ['dsh-tool-csv', 'dsh-external', 'dsh-tool-csv'],
  ['dsh-tool-encoding', 'dsh-external', 'dsh-tool-encoding'],
  ['dsh-tool-json', 'dsh-external', 'dsh-tool-json'],
  ['dsh-tool-markdown', 'dsh-external', 'dsh-tool-markdown'],
  ['dsh-tool-regex', 'dsh-external', 'dsh-tool-regex'],
  ['dsh-tool-time', 'dsh-external', 'dsh-tool-time'],
  ['dsh-ui-progress', 'dsh-external', 'dsh-ui-progress'],
  ['dsh-ui-whale', 'dsh-external', 'dsh-ui-whale'],
  ['dsh-visualize', 'dsh-external', 'dsh-visualize'],
  ['dsh-web-archive', 'dsh-external', 'dsh-web-archive'],
  ['dsh-web-terminal', 'dsh-external', 'dsh-web-panel'],
  ['dsh-web-ui-notify', 'dsh-external', 'dsh-web-ui-notify'],
  ['dsh-working-activity', 'dsh-external', 'dsh-working-activity'],
  ['dsh-subagent-tree', 'dsh-external', 'dsh-subagent-tree'],
]

const fields = candidates.map(([, o, n], i) => `r${i}: repository(owner: "${o}", name: "${n}") { pushedAt isArchived }`).join('\n')
const query = `query {\n${fields}\n}`

let out
try {
  out = execFileSync('gh', ['api', 'graphql', '-f', `query=${query}`], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
} catch (e) {
  out = e.stdout?.toString() ?? ''
  if (!out) throw e
}
const parsed = JSON.parse(out)
const data = parsed.data ?? {}
candidates.forEach(([dir, o, n], i) => {
  const r = data[`r${i}`]
  const tag = r ? `${r.pushedAt.slice(0, 16)}${r.isArchived ? ' [archived]' : ''}` : 'MISSING'
  console.log(`${dir}\t${o}/${n}\t${tag}`)
})
