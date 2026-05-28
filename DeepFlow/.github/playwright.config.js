/**
 * Playwright Configuration for UniFlow Editor Tests
 * Runs browser-based unit tests in headless Chrome
 */

import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '../Editor/tests',
  
  // Test file pattern
  testMatch: '**/*.test.html',
  
  // Timeout settings
  timeout: 30000,
  expect: {
    timeout: 5000
  },
  
  // Run tests in parallel
  fullyParallel: true,
  
  // Fail the build on CI if any test fails
  forbidOnly: !!process.env.CI,
  
  // Retry on CI only
  retries: process.env.CI ? 2 : 0,
  
  // Limit workers on CI
  workers: process.env.CI ? 1 : undefined,
  
  // Reporter
  reporter: [
    ['html', { outputFolder: 'test-results/html-report' }],
    ['json', { outputFile: 'test-results/results.json' }],
    ['list']
  ],
  
  // Output directory
  outputDir: 'test-results/traces',
  
  // Configure projects for different browsers
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ],
  
  // Web server to serve the test runner
  webServer: {
    command: 'npx serve docs/uniFlow/Editor -l 8080',
    port: 8080,
    reuseExistingServer: !process.env.CI
  }
});
