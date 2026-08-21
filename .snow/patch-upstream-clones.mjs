// Byte-precise patch application for the two upstream clones (no formatter,
// no line-ending churn): read, replace exact substrings, write back as-is.
import { readFileSync, writeFileSync } from 'node:fs'

const SM = 'D:/github/dsh-external-review/dsh-skills-manager'
const SKINS = 'D:/github/dsh-external-review/dsh-skins'

// ── skills-manager: seat the maximize toggle inside the header flex row ──
const enhancerFile = `${SM}/src/client/settings-enhancer.ts`
{
  let t = readFileSync(enhancerFile, 'utf8')
  const oldJs = `  })\r\n  panel.appendChild(toggle)\r\n`
  const newJs = `  })\r\n  // Seat the toggle inside the panel header's flex row, immediately left of\r\n  // the framework's close button: it shares the close button's geometry and\r\n  // can never overlap the header actions slot (the previous absolute pin at\r\n  // top:10/right:46 floated 10px above the close line and covered the action\r\n  // pill). Structure walk: panel > nav + content > header > actions + close.\r\n  // If the framework reshapes the panel, degrade to the absolute pin.\r\n  const header = panel.querySelector('nav')?.nextElementSibling?.firstElementChild ?? null\r\n  const closeButton = header?.querySelector(':scope > button') ?? null\r\n  if (header !== null && closeButton !== null) {\r\n    header.insertBefore(toggle, closeButton)\r\n  } else {\r\n    toggle.classList.add('sb-panel-maximize--floating')\r\n    panel.appendChild(toggle)\r\n  }\r\n`
  if (!t.includes(oldJs)) throw new Error('enhancer anchor missing')
  t = t.replace(oldJs, newJs)
  writeFileSync(enhancerFile, t)
  console.log('settings-enhancer.ts patched')
}

const cssFile = `${SM}/src/client/styles.css`
{
  let t = readFileSync(cssFile, 'utf8')
  const oldCss = `/* Fullscreen toggle button: pinned to the panel's top-right, left of the\r\n   framework's close button (36px wide), above the content stack. */\r\n.sb-panel-maximize {\r\n  position: absolute;\r\n  top: 10px;\r\n  right: 46px;\r\n  z-index: 20;\r\n  display: flex;\r\n`
  const newCss = `/* Fullscreen toggle button: seated in the panel header's flex row, left of\r\n   the framework's close button — it shares the close geometry and can never\r\n   overlap the header actions. The --floating modifier restores the legacy\r\n   absolute pin when the framework structure is not recognized. */\r\n.sb-panel-maximize {\r\n  flex: none;\r\n  display: flex;\r\n`
  if (!t.includes(oldCss)) throw new Error('css anchor missing')
  t = t.replace(oldCss, newCss)
  const hoverOld = `}\r\n\r\n.sb-panel-maximize:hover {\r\n`
  const hoverNew = `}\r\n\r\n.sb-panel-maximize--floating {\r\n  position: absolute;\r\n  top: 10px;\r\n  right: 46px;\r\n  z-index: 20;\r\n}\r\n\r\n.sb-panel-maximize:hover {\r\n`
  if (!t.includes(hoverOld)) throw new Error('css hover anchor missing')
  t = t.replace(hoverOld, hoverNew)
  writeFileSync(cssFile, t)
  console.log('styles.css patched')
}

// ── dsh-skins: fix the four --dsw-alias-label-primary-inverted values ──
const skinsFile = `${SKINS}/packages/dsh-web-skins/src/client/skins.ts`
{
  let t = readFileSync(skinsFile, 'utf8')
  const pairs = [
    [`'--dsw-alias-label-primary-inverted': '#d8dee9',`, `'--dsw-alias-label-primary-inverted': '#2e3440',`],
    [`'--dsw-alias-label-primary-inverted': '#e8e6ff',`, `'--dsw-alias-label-primary-inverted': '#0d101e',`],
    [`'--dsw-alias-label-primary-inverted': '#4a3a28',`, `'--dsw-alias-label-primary-inverted': '#fbf8f2',`],
    [`'--dsw-alias-label-primary-inverted': '#fdf6e3',`, `'--dsw-alias-label-primary-inverted': '#1b2140',`],
  ]
  for (const [from, to] of pairs) {
    if (!t.includes(from)) throw new Error(`skins anchor missing: ${from}`)
    t = t.replace(from, to)
  }
  writeFileSync(skinsFile, t)
  console.log('skins.ts patched (4 tokens)')
}
