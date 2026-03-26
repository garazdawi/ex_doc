import { test, expect } from '@playwright/test'

// Helper to navigate to a function's detail section
async function goToFunction (page, funcId) {
  await page.goto(`spec_test.html#${funcId}`)
  // Escape / for CSS selector (e.g., "simple_inline/2" -> "simple_inline\\/2")
  const escaped = funcId.replace(/\//g, '\\/')
  return page.locator(`#${escaped}`)
}

// Helper to get the detail section's bounding box
async function detailHeaderBox (section) {
  return section.locator('.detail-header').boundingBox()
}

test.describe('spec rendering layout', () => {
  test.describe('signature and annotations', () => {
    test('annotations stay within the detail-header bounds', async ({ page }) => {
      const section = await goToFunction(page, 'simple_inline/2')
      const headerBox = await detailHeaderBox(section)
      const notes = section.locator('.detail-header .note')

      for (const note of await notes.all()) {
        const noteBox = await note.boundingBox()
        if (noteBox) {
          // Note should not extend beyond the right edge of the header
          expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(
            headerBox.x + headerBox.width + 1 // 1px tolerance
          )
        }
      }
    })

    test('source link stays within the detail-header bounds', async ({ page }) => {
      const section = await goToFunction(page, 'with_types_section/2')
      const sourceLink = section.locator('.detail-header .icon-action').first()

      if (await sourceLink.count() > 0) {
        const headerBox = await detailHeaderBox(section)
        const linkBox = await sourceLink.boundingBox()

        if (linkBox) {
          expect(linkBox.x + linkBox.width).toBeLessThanOrEqual(
            headerBox.x + headerBox.width + 1
          )
        }
      }
    })
  })

  test.describe('inlined specs', () => {
    test('short spec is inlined in the signature with type links', async ({ page }) => {
      const section = await goToFunction(page, 'simple_inline/2')
      const sig = section.locator('h1.signature').first()
      const text = await sig.textContent()

      // Should contain inlined types
      expect(text).toContain('::')
      expect(text).toContain('->')

      // Should have autolinked types
      const links = sig.locator('a')
      expect(await links.count()).toBeGreaterThan(0)
    })

    test('inlined spec has no Types section', async ({ page }) => {
      const section = await goToFunction(page, 'concrete_return/2')
      const sig = section.locator('h1.signature').first()
      const text = await sig.textContent()

      // Types are inlined
      expect(text).toContain('::')

      // No Types heading
      const typesTitle = section.locator('.specs-title')
      await expect(typesTitle).toHaveCount(0)
    })
  })

  test.describe('decomposed specs with Types section', () => {
    test('Types section is present with variable bindings', async ({ page }) => {
      const section = await goToFunction(page, 'with_types_section/2')
      const typesTitle = section.locator('.specs-title')
      await expect(typesTitle).toHaveText('Types')

      const typeEntries = section.locator('.specs pre')
      expect(await typeEntries.count()).toBeGreaterThan(0)

      // Check format: "Var = type()"
      const firstType = await typeEntries.first().textContent()
      expect(firstType).toMatch(/\w+ = /)
    })

    test('Types section has autolinked types', async ({ page }) => {
      const section = await goToFunction(page, 'with_types_section/2')
      const typeLinks = section.locator('.specs pre a')
      expect(await typeLinks.count()).toBeGreaterThan(0)
    })

    test('signature includes return type', async ({ page }) => {
      const section = await goToFunction(page, 'with_types_section/2')
      const sig = section.locator('h1.signature').first()
      const text = await sig.textContent()
      // The -> uses non-breaking spaces from the template
      expect(text).toMatch(/->.*Unsigned/)
    })
  })

  test.describe('same-type variable merging', () => {
    test('variables with same type are merged with =', async ({ page }) => {
      const section = await goToFunction(page, 'same_type_vars/2')
      const typeEntries = section.locator('.specs pre')
      const texts = await typeEntries.allTextContents()

      // Should have a merged entry like "List1 = List2 = [T]"
      const merged = texts.find(t => (t.match(/=/g) || []).length >= 2)
      expect(merged).toBeTruthy()
    })
  })

  test.describe('equiv merged functions', () => {
    test('equiv signature shown above main signature', async ({ page }) => {
      const section = await goToFunction(page, 'equiv_full/2')
      const signatures = section.locator('h1.signature')
      expect(await signatures.count()).toBe(2)

      // First is the equiv entry
      const equivText = await signatures.nth(0).textContent()
      expect(equivText).toContain('->')

      // Second is the main entry
      const mainText = await signatures.nth(1).textContent()
      expect(mainText).toContain('equiv_full')
    })

    test('equiv arrow does not word-break', async ({ page }) => {
      const section = await goToFunction(page, 'equiv_full/2')
      const arrow = section.locator('.signature-arrow').first()
      await expect(arrow).toHaveCSS('white-space', 'nowrap')
    })
  })

  test.describe('long equiv wrapping', () => {
    test('result wraps as inline-block unit', async ({ page }) => {
      const section = await goToFunction(page, 'long_equiv_full/6')
      const result = section.locator('.signature-result').first()
      await expect(result).toHaveCSS('display', 'inline-block')
    })

    test('all signatures stay within detail-header', async ({ page }) => {
      const section = await goToFunction(page, 'long_equiv_full/6')
      const headerBox = await detailHeaderBox(section)
      const signatures = section.locator('h1.signature')

      for (const sig of await signatures.all()) {
        const sigBox = await sig.boundingBox()
        if (sigBox) {
          expect(sigBox.x + sigBox.width).toBeLessThanOrEqual(
            headerBox.x + headerBox.width + 1
          )
        }
      }
    })
  })

  test.describe('multi-clause specs', () => {
    test('falls back to -spec rendering', async ({ page }) => {
      const section = await goToFunction(page, 'multi_clause/1')
      const specAttr = section.locator('.specs .attribute')
      expect(await specAttr.count()).toBeGreaterThan(0)

      const attrText = await specAttr.first().textContent()
      expect(attrText).toBe('-spec')
    })
  })

  test.describe('annotated return type', () => {
    test('uses variable name from annotation', async ({ page }) => {
      const section = await goToFunction(page, 'ann_return/1')
      const sig = section.locator('h1.signature').first()
      const text = await sig.textContent()
      expect(text).toMatch(/->.*Result/)
    })
  })

  test.describe('no spec', () => {
    test('shows plain signature without types', async ({ page }) => {
      const section = await goToFunction(page, 'no_spec/1')
      const sig = section.locator('h1.signature').first()
      const text = await sig.textContent()
      expect(text).toBe('no_spec(X)')

      // No specs section
      const specs = section.locator('.specs')
      await expect(specs).toHaveCount(0)
    })
  })

  test.describe('annotations positioning', () => {
    test('since annotation stays within detail-header', async ({ page }) => {
      const section = await goToFunction(page, 'with_since/1')
      const headerBox = await detailHeaderBox(section)
      const note = section.locator('.detail-header .note').first()
      const noteBox = await note.boundingBox()

      expect(noteBox).toBeTruthy()
      expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(
        headerBox.x + headerBox.width + 1
      )
    })

    test('since annotation on equiv entry stays within detail-header', async ({ page }) => {
      const section = await goToFunction(page, 'with_since_equiv_full/2')
      const headerBox = await detailHeaderBox(section)
      const notes = section.locator('.detail-header .note')

      for (const note of await notes.all()) {
        const noteBox = await note.boundingBox()
        if (noteBox) {
          expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(
            headerBox.x + headerBox.width + 1
          )
        }
      }
    })

    test('since annotation on long signature stays within detail-header', async ({ page }) => {
      const section = await goToFunction(page, 'long_sig_with_since/5')
      const headerBox = await detailHeaderBox(section)
      const note = section.locator('.detail-header .note').first()
      const noteBox = await note.boundingBox()

      expect(noteBox).toBeTruthy()
      expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(
        headerBox.x + headerBox.width + 1
      )
    })

    test('deprecated function with since has both annotations', async ({ page }) => {
      const section = await goToFunction(page, 'deprecated_with_since/1')
      const headerBox = await detailHeaderBox(section)
      const notes = section.locator('.detail-header .note')
      expect(await notes.count()).toBeGreaterThanOrEqual(1)

      for (const note of await notes.all()) {
        const noteBox = await note.boundingBox()
        if (noteBox) {
          expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(
            headerBox.x + headerBox.width + 1
          )
        }
      }
    })

    test('equiv entries each have their own since annotation', async ({ page }) => {
      const section = await goToFunction(page, 'with_since_equiv_full/2')
      const rows = section.locator('.detail-header .signature-row')
      expect(await rows.count()).toBe(2)

      // Each row should have a note
      for (const row of await rows.all()) {
        const note = row.locator('.note')
        expect(await note.count()).toBeGreaterThanOrEqual(1)
      }
    })
  })

  test.describe('visual regression', () => {
    test('full page screenshot', async ({ page }) => {
      await page.goto('spec_test.html')
      await expect(page).toHaveScreenshot('spec-test-full.png', {
        fullPage: true,
      })
    })

    test('inlined spec detail', async ({ page }) => {
      const section = await goToFunction(page, 'simple_inline/2')
      await expect(section).toHaveScreenshot('simple-inline.png')
    })

    test('decomposed spec detail', async ({ page }) => {
      const section = await goToFunction(page, 'with_types_section/2')
      await expect(section).toHaveScreenshot('decomposed-spec.png')
    })

    test('equiv merged detail', async ({ page }) => {
      const section = await goToFunction(page, 'equiv_full/2')
      await expect(section).toHaveScreenshot('equiv-merged.png')
    })

    test('long equiv detail', async ({ page }) => {
      const section = await goToFunction(page, 'long_equiv_full/6')
      await expect(section).toHaveScreenshot('long-equiv.png')
    })

    test('multi-clause spec detail', async ({ page }) => {
      const section = await goToFunction(page, 'multi_clause/1')
      await expect(section).toHaveScreenshot('multi-clause.png')
    })

    test('same-type vars detail', async ({ page }) => {
      const section = await goToFunction(page, 'same_type_vars/2')
      await expect(section).toHaveScreenshot('same-type-vars.png')
    })

    test('since annotation detail', async ({ page }) => {
      const section = await goToFunction(page, 'with_since/1')
      await expect(section).toHaveScreenshot('with-since.png')
    })

    test('equiv with since annotations', async ({ page }) => {
      const section = await goToFunction(page, 'with_since_equiv_full/2')
      await expect(section).toHaveScreenshot('equiv-with-since.png')
    })

    test('long signature with since', async ({ page }) => {
      const section = await goToFunction(page, 'long_sig_with_since/5')
      await expect(section).toHaveScreenshot('long-sig-with-since.png')
    })

    test('deprecated with since', async ({ page }) => {
      const section = await goToFunction(page, 'deprecated_with_since/1')
      await expect(section).toHaveScreenshot('deprecated-with-since.png')
    })
  })
})
