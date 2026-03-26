import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test/layout',
  use: {
    baseURL: 'file://' + process.cwd() + '/test/layout/fixtures/doc/',
  },
  projects: [
    {
      name: 'desktop',
      use: { viewport: { width: 1280, height: 720 } },
    },
    {
      name: 'tablet',
      use: { viewport: { width: 768, height: 1024 } },
    },
    {
      name: 'mobile',
      use: { viewport: { width: 375, height: 667 } },
    },
  ],
})
