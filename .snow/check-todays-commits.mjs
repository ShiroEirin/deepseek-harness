// Fetch the latest few commit subjects for each plugin repo that pushed today,
// so we can decide which upgrades are worth taking.
import { execFileSync } from 'node:child_process'

const repos = [
  ['dsh-bash-encoding', 'dsh-external', 'dsh-bash-encoding'],
  ['dsh-input-history', 'dsh-external', 'dsh-input-history'],
  ['dsh-ui-whale', 'dsh-external', 'dsh-ui-whale'],
  ['dsh-web-ui-notify', 'dsh-external', 'dsh-web-ui-notify'],
  ['dsh-sidechain', 'dsh-external', 'dsh-sidechain'],
  ['dsh-stickers', 'dsh-external', 'dsh-stickers'],
  ['dsh-paste-input', 'dsh-external', 'dsh-paste-input'],
  ['dsh-memory-evolve', 'dsh-external', 'dsh-memory-evolve'],
]

const fields = repos.map(([, o, n], i) => `r${i}: repository(owner: "${o}", name: "${n}") { defaultBranchRef { target { ... on Commit { history(first: 3) { nodes { messageHeadline committedDate } } } } } }`).join('\n')
const query = `query {\n${fields}\n}`

const out = execFileSync('gh', ['api', 'graphql', '-f', `query=${query}`], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
const data = JSON.parse(out).data ?? {}
repos.forEach(([dir], i) => {
  const nodes = data[`r${i}`]?.defaultBranchRef?.target?.history?.nodes ?? []
  console.log(`\n### ${dir}`)
  for (const n of nodes) console.log(`  ${n.committedDate.slice(5, 16)}  ${n.messageHeadline}`)
})
