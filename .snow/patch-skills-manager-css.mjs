// One-off patch: skills-manager settings-panel maximize button CSS inside the
// prebuilt lib/client.js bundles (deploy + config-package copies).
// The JS logic half was already patched; this adds the CSS half.
import { readFileSync, writeFileSync } from 'node:fs'

const targets = [
  'C:/Users/12971/.dsh/plugins/dsh-skills-manager/lib/client.js',
  'D:/github/DeepSeek/dsh-plugins-config-20260810/plugins/dsh-skills-manager/lib/client.js',
]

// NOTE: inside the bundle the stylesheet is one JS string, so newlines are
// the two literal characters "\n" — String.raw keeps them intact.
const cssOld = String.raw`/* Fullscreen toggle button: pinned to the panel's top-right, left of the\n   framework's close button (36px wide), above the content stack. */\n.sb-panel-maximize {\n  position: absolute;\n  top: 10px;\n  right: 46px;\n  z-index: 20;\n  display: flex;\n`
const cssNew = String.raw`/* Fullscreen toggle button: seated in the panel header's flex row, left of the\n   framework's close button - it shares the close geometry and can never\n   overlap the header actions. The --floating modifier restores the legacy\n   absolute pin when the framework structure is not recognized. */\n.sb-panel-maximize {\n  flex: none;\n  display: flex;\n`

const hoverOld = String.raw`}\n\n.sb-panel-maximize:hover {\n`
const hoverNew = String.raw`}\n\n.sb-panel-maximize--floating {\n  position: absolute;\n  top: 10px;\n  right: 46px;\n  z-index: 20;\n}\n\n.sb-panel-maximize:hover {\n`

for (const file of targets) {
  let text = readFileSync(file, 'utf8')
  const before = text.length
  let hits = 0

  if (text.includes(cssOld)) { text = text.replace(cssOld, cssNew); hits++ }
  if (text.includes(hoverOld)) { text = text.replace(hoverOld, hoverNew); hits++ }

  // Sanity: JS half must already be patched, and the CSS must not be doubled.
  const jsOk = text.includes('toggle.classList.add("sb-panel-maximize--floating")')
  const cssCount = text.split('.sb-panel-maximize--floating').length - 1

  writeFileSync(file, text)
  console.log(JSON.stringify({ file, hits, jsOk, cssFloatingRefs: cssCount, delta: text.length - before }))
}
