// Repair: the skins bundle patch dropped the trailing comma on the four
// --dsw-alias-label-primary-inverted property lines (JS object literal ->
// SyntaxError). Restore the commas and verify every inverted line ends with
// a comma before the next property line.
import { readFileSync, writeFileSync } from 'node:fs'

const targets = [
  'C:/Users/12971/.dsh/plugins/dsh-skins/packages/dsh-web-skins/lib/client.js',
  'D:/github/DeepSeek/dsh-plugins-config-20260810/plugins/dsh-skins/packages/dsh-web-skins/lib/client.js',
]
const colors = ['#2e3440', '#0d101e', '#fbf8f2', '#1b2140']

for (const file of targets) {
  let text = readFileSync(file, 'utf8')
  let repaired = 0
  for (const color of colors) {
    const broken = `"--dsw-alias-label-primary-inverted": "${color}"\n`
    const fixed = `"--dsw-alias-label-primary-inverted": "${color}",\n`
    if (text.includes(broken)) { text = text.replace(broken, fixed); repaired++ }
  }
  writeFileSync(file, text)

  // Verify: all four inverted lines now end with a comma; no old values left.
  const ok = colors.every(c => text.includes(`"--dsw-alias-label-primary-inverted": "${c}",`))
  const stale = ['#d8dee9",', '#e8e6ff",', '#4a3a28",', '#fdf6e3",']
    .filter(v => text.includes(`"--dsw-alias-label-primary-inverted": "${v.slice(0, -2)}"`))
  console.log(JSON.stringify({ file, repaired, allFourOk: ok, staleHits: stale.length }))
}
