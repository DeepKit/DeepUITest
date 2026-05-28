/**
 * Playwright Test Spec for UniFlow Editor
 * Runs the browser-based unit tests and captures results
 */

import { test, expect } from '@playwright/test';

test.describe('UniFlow Editor Unit Tests', () => {
  
  test.beforeEach(async ({ page }) => {
    // Navigate to test runner
    await page.goto('/tests/test-runner.html');
    
    // Wait for test framework to initialize
    await page.waitForSelector('#testSuites');
  });

  test('should load test framework', async ({ page }) => {
    // Verify test suites are rendered
    const suites = await page.locator('.test-suite').count();
    expect(suites).toBeGreaterThan(0);
    
    // Verify global status is ready
    const status = await page.locator('#globalStatus').textContent();
    expect(status).toContain('å°±ç»ª');
  });

  test('should run all tests successfully', async ({ page }) => {
    // Click run all tests button
    await page.click('#btnRunAll');
    
    // Wait for tests to complete (max 60 seconds)
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Get test results
    const total = await page.locator('#totalCount').textContent();
    const passed = await page.locator('#passedCount').textContent();
    const failed = await page.locator('#failedCount').textContent();
    const duration = await page.locator('#duration').textContent();
    
    console.log(`Test Results: ${passed}/${total} passed, ${failed} failed, ${duration}`);
    
    // Check results
    expect(parseInt(total)).toBeGreaterThan(0);
    expect(parseInt(failed)).toBe(0);
    
    // Verify status badge
    const statusClass = await page.locator('#globalStatus').getAttribute('class');
    expect(statusClass).toContain('passed');
  });

  test('should have all test suites', async ({ page }) => {
    const suiteNames = await page.locator('.suite-name').allTextContents();
    
    // Verify expected test suites exist
    expect(suiteNames.some(s => s.includes('Utils'))).toBe(true);
    expect(suiteNames.some(s => s.includes('NodeTypes'))).toBe(true);
    expect(suiteNames.some(s => s.includes('Canvas') || s.includes('WorkflowCanvas'))).toBe(true);
    expect(suiteNames.some(s => s.includes('Properties'))).toBe(true);
    expect(suiteNames.some(s => s.includes('Integration') || s.includes('é›†æˆ'))).toBe(true);
  });

  test('Utils tests should pass', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Find Utils suite and check its status
    const utilsSuite = page.locator('.test-suite').filter({ hasText: 'Utils' });
    const icon = await utilsSuite.locator('.suite-icon').textContent();
    
    expect(icon).toBe('âœ?);
  });

  test('NodeTypes tests should pass', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Find NodeTypes suite and check its status
    const suite = page.locator('.test-suite').filter({ hasText: 'NodeTypes' });
    const icon = await suite.locator('.suite-icon').textContent();
    
    expect(icon).toBe('âœ?);
  });

  test('Canvas tests should pass', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Find Canvas suite and check its status
    const suite = page.locator('.test-suite').filter({ hasText: /Canvas|ç”»å¸ƒ/ });
    const icon = await suite.locator('.suite-icon').textContent();
    
    expect(icon).toBe('âœ?);
  });

  test('Properties tests should pass', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Find Properties suite and check its status
    const suite = page.locator('.test-suite').filter({ hasText: /Properties|å±žæ€? });
    const icon = await suite.locator('.suite-icon').textContent();
    
    expect(icon).toBe('âœ?);
  });

  test('Integration tests should pass', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Find Integration suite and check its status
    const suite = page.locator('.test-suite').filter({ hasText: /Integration|é›†æˆ/ });
    const icon = await suite.locator('.suite-icon').textContent();
    
    expect(icon).toBe('âœ?);
  });

  test('should capture failure details', async ({ page }) => {
    await page.click('#btnRunAll');
    await page.waitForFunction(() => {
      const status = document.getElementById('globalStatus');
      return status && (status.classList.contains('passed') || status.classList.contains('failed'));
    }, { timeout: 60000 });
    
    // Check for any error messages
    const errors = await page.locator('.test-error').count();
    
    if (errors > 0) {
      const errorMessages = await page.locator('.test-error').allTextContents();
      console.log('Test errors:', errorMessages);
    }
    
    expect(errors).toBe(0);
  });
});
