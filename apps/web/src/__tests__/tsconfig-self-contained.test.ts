import { readFileSync } from 'fs'
import { join } from 'path'

// Vercel preview builds run from the apps/web root directory and do NOT include
// files outside it. A tsconfig `extends` that points above apps/web (e.g.
// "../../tsconfig.base.json") therefore fails on Vercel with
// `TS5083: Cannot read file '/tsconfig.base.json'`, breaking every preview deploy.
// Keep apps/web/tsconfig.json self-contained.
describe('apps/web tsconfig', () => {
  it('does not extend a config outside the package root', () => {
    const tsconfig = JSON.parse(
      readFileSync(join(__dirname, '../../tsconfig.json'), 'utf8'),
    )
    const extendsField: string | string[] | undefined = tsconfig.extends
    const extended = Array.isArray(extendsField)
      ? extendsField
      : extendsField
        ? [extendsField]
        : []
    const escapesRoot = extended.filter(
      (p) => typeof p === 'string' && p.startsWith('..'),
    )
    expect(escapesRoot).toEqual([])
  })
})
