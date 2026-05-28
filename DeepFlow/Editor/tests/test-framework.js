/**
 * UniFlow Editor - Simple Test Framework
 * A lightweight, browser-based unit testing framework
 */

// ============================================================================
// Test Framework Core
// ============================================================================

const TestRunner = {
  suites: [],
  results: {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    duration: 0
  },
  currentSuite: null,
  isRunning: false,

  // Register a test suite
  describe(name, fn) {
    const suite = {
      name,
      tests: [],
      beforeEach: null,
      afterEach: null,
      beforeAll: null,
      afterAll: null
    };
    this.suites.push(suite);
    this.currentSuite = suite;
    fn();
    this.currentSuite = null;
    return suite;
  },

  // Register a test case
  it(name, fn, options = {}) {
    if (!this.currentSuite) {
      throw new Error('it() must be called inside describe()');
    }
    this.currentSuite.tests.push({
      name,
      fn,
      skip: options.skip || false,
      only: options.only || false,
      timeout: options.timeout || 5000,
      status: 'pending',
      error: null,
      duration: 0
    });
  },

  // Skip a test
  skip(name, fn) {
    this.it(name, fn, { skip: true });
  },

  // Run only this test
  only(name, fn) {
    this.it(name, fn, { only: true });
  },

  // Setup hooks
  beforeEach(fn) {
    if (this.currentSuite) this.currentSuite.beforeEach = fn;
  },

  afterEach(fn) {
    if (this.currentSuite) this.currentSuite.afterEach = fn;
  },

  beforeAll(fn) {
    if (this.currentSuite) this.currentSuite.beforeAll = fn;
  },

  afterAll(fn) {
    if (this.currentSuite) this.currentSuite.afterAll = fn;
  },

  // Run all tests
  async runAll() {
    if (this.isRunning) return;
    this.isRunning = true;
    
    this.results = { total: 0, passed: 0, failed: 0, skipped: 0, duration: 0 };
    const startTime = performance.now();
    
    this.updateGlobalStatus('running');
    
    // Check if any test has "only" flag
    const hasOnly = this.suites.some(s => s.tests.some(t => t.only));
    
    for (const suite of this.suites) {
      await this.runSuite(suite, hasOnly);
    }
    
    this.results.duration = Math.round(performance.now() - startTime);
    this.updateSummary();
    this.updateGlobalStatus(this.results.failed > 0 ? 'failed' : 'passed');
    
    this.isRunning = false;
  },

  // Run a single suite
  async runSuite(suite, hasOnly = false) {
    // Before all
    if (suite.beforeAll) {
      try {
        await suite.beforeAll();
      } catch (e) {
        console.error(`beforeAll failed in "${suite.name}":`, e);
      }
    }
    
    for (const test of suite.tests) {
      // Skip logic
      if (test.skip || (hasOnly && !test.only)) {
        test.status = 'skipped';
        this.results.skipped++;
        this.results.total++;
        this.updateTestUI(suite, test);
        continue;
      }
      
      await this.runTest(suite, test);
    }
    
    // After all
    if (suite.afterAll) {
      try {
        await suite.afterAll();
      } catch (e) {
        console.error(`afterAll failed in "${suite.name}":`, e);
      }
    }
    
    this.updateSuiteUI(suite);
  },

  // Run a single test
  async runTest(suite, test) {
    const startTime = performance.now();
    this.results.total++;
    
    try {
      // Before each
      if (suite.beforeEach) {
        await suite.beforeEach();
      }
      
      // Run test with timeout
      await Promise.race([
        test.fn(),
        new Promise((_, reject) => 
          setTimeout(() => reject(new Error(`Test timeout after ${test.timeout}ms`)), test.timeout)
        )
      ]);
      
      test.status = 'passed';
      this.results.passed++;
      
    } catch (error) {
      test.status = 'failed';
      test.error = error;
      this.results.failed++;
      console.error(`FAILED: ${suite.name} > ${test.name}`, error);
      
    } finally {
      test.duration = Math.round(performance.now() - startTime);
      
      // After each
      if (suite.afterEach) {
        try {
          await suite.afterEach();
        } catch (e) {
          console.error('afterEach failed:', e);
        }
      }
    }
    
    this.updateTestUI(suite, test);
  },

  // Reset all tests
  reset() {
    for (const suite of this.suites) {
      for (const test of suite.tests) {
        test.status = 'pending';
        test.error = null;
        test.duration = 0;
      }
    }
    this.results = { total: 0, passed: 0, failed: 0, skipped: 0, duration: 0 };
    this.renderSuites();
    this.updateSummary();
    this.updateGlobalStatus('ready');
  },

  // ============================================================================
  // UI Updates
  // ============================================================================

  renderSuites() {
    const container = document.getElementById('testSuites');
    if (!container) return;
    
    container.innerHTML = this.suites.map((suite, idx) => `
      <div class="test-suite" data-suite="${idx}">
        <div class="suite-header" onclick="TestRunner.toggleSuite(${idx})">
          <span class="suite-icon">ðŸ“¦</span>
          <span class="suite-name">${escapeHtml(suite.name)}</span>
          <span class="suite-stats">${suite.tests.length} ä¸ªæµ‹è¯?/span>
        </div>
        <div class="suite-tests">
          ${suite.tests.map((test, testIdx) => `
            <div class="test-case" data-test="${testIdx}">
              <div class="test-icon ${test.status}">
                ${this.getStatusIcon(test.status)}
              </div>
              <span class="test-name">${escapeHtml(test.name)}</span>
              <span class="test-time">${test.duration > 0 ? test.duration + 'ms' : ''}</span>
            </div>
            ${test.error ? `<div class="test-error">${escapeHtml(this.formatError(test.error))}</div>` : ''}
          `).join('')}
        </div>
      </div>
    `).join('');
  },

  updateSuiteUI(suite) {
    const idx = this.suites.indexOf(suite);
    const el = document.querySelector(`[data-suite="${idx}"]`);
    if (!el) return;
    
    const passed = suite.tests.filter(t => t.status === 'passed').length;
    const failed = suite.tests.filter(t => t.status === 'failed').length;
    const total = suite.tests.length;
    
    el.querySelector('.suite-stats').textContent = `${passed}/${total} é€šè¿‡`;
    el.querySelector('.suite-icon').textContent = failed > 0 ? 'â? : 'âœ?;
  },

  updateTestUI(suite, test) {
    const suiteIdx = this.suites.indexOf(suite);
    const testIdx = suite.tests.indexOf(test);
    const suiteEl = document.querySelector(`[data-suite="${suiteIdx}"]`);
    if (!suiteEl) return;
    
    const testEl = suiteEl.querySelector(`[data-test="${testIdx}"]`);
    if (!testEl) return;
    
    const iconEl = testEl.querySelector('.test-icon');
    iconEl.className = `test-icon ${test.status}`;
    iconEl.textContent = this.getStatusIcon(test.status);
    
    testEl.querySelector('.test-time').textContent = test.duration > 0 ? test.duration + 'ms' : '';
    
    // Add or update error display
    let errorEl = testEl.nextElementSibling;
    if (errorEl?.classList.contains('test-error')) {
      errorEl.remove();
    }
    if (test.error) {
      const newErrorEl = document.createElement('div');
      newErrorEl.className = 'test-error';
      newErrorEl.textContent = this.formatError(test.error);
      testEl.after(newErrorEl);
    }
    
    this.updateSummary();
  },

  updateSummary() {
    const el = (id) => document.getElementById(id);
    if (el('totalCount')) el('totalCount').textContent = this.results.total;
    if (el('passedCount')) el('passedCount').textContent = this.results.passed;
    if (el('failedCount')) el('failedCount').textContent = this.results.failed;
    if (el('skippedCount')) el('skippedCount').textContent = this.results.skipped;
    if (el('duration')) el('duration').textContent = this.results.duration + 'ms';
  },

  updateGlobalStatus(status) {
    const el = document.getElementById('globalStatus');
    if (!el) return;
    
    el.className = 'status ' + status;
    const labels = {
      ready: 'å°±ç»ª',
      running: 'è¿è¡Œä¸?..',
      passed: 'å…¨éƒ¨é€šè¿‡ âœ?,
      failed: 'æœ‰å¤±è´?âœ?
    };
    el.textContent = labels[status] || status;
  },

  toggleSuite(idx) {
    const el = document.querySelector(`[data-suite="${idx}"]`);
    if (el) el.classList.toggle('collapsed');
  },

  getStatusIcon(status) {
    const icons = {
      pending: 'â—?,
      passed: 'âœ?,
      failed: 'âœ?,
      skipped: 'âŠ?
    };
    return icons[status] || '?';
  },

  formatError(error) {
    if (!error) return '';
    if (typeof error === 'string') return error;
    
    let msg = error.message || String(error);
    if (error.expected !== undefined && error.actual !== undefined) {
      msg += `\n\nExpected: ${JSON.stringify(error.expected)}`;
      msg += `\nActual:   ${JSON.stringify(error.actual)}`;
    }
    return msg;
  }
};

// ============================================================================
// Assertion Library
// ============================================================================

const assert = {
  // Basic assertions
  ok(value, message) {
    if (!value) {
      throw new AssertionError(message || `Expected truthy, got ${value}`);
    }
  },

  notOk(value, message) {
    if (value) {
      throw new AssertionError(message || `Expected falsy, got ${value}`);
    }
  },

  equal(actual, expected, message) {
    if (actual !== expected) {
      const err = new AssertionError(message || `Expected ${expected}, got ${actual}`);
      err.expected = expected;
      err.actual = actual;
      throw err;
    }
  },

  notEqual(actual, expected, message) {
    if (actual === expected) {
      throw new AssertionError(message || `Expected not equal to ${expected}`);
    }
  },

  strictEqual(actual, expected, message) {
    if (actual !== expected) {
      const err = new AssertionError(message || `Expected strictly ${expected}, got ${actual}`);
      err.expected = expected;
      err.actual = actual;
      throw err;
    }
  },

  deepEqual(actual, expected, message) {
    if (!deepEquals(actual, expected)) {
      const err = new AssertionError(message || 'Deep equality check failed');
      err.expected = expected;
      err.actual = actual;
      throw err;
    }
  },

  // Type assertions
  isTrue(value, message) {
    if (value !== true) {
      throw new AssertionError(message || `Expected true, got ${value}`);
    }
  },

  isFalse(value, message) {
    if (value !== false) {
      throw new AssertionError(message || `Expected false, got ${value}`);
    }
  },

  isNull(value, message) {
    if (value !== null) {
      throw new AssertionError(message || `Expected null, got ${value}`);
    }
  },

  isNotNull(value, message) {
    if (value === null) {
      throw new AssertionError(message || 'Expected not null');
    }
  },

  isUndefined(value, message) {
    if (value !== undefined) {
      throw new AssertionError(message || `Expected undefined, got ${value}`);
    }
  },

  isDefined(value, message) {
    if (value === undefined) {
      throw new AssertionError(message || 'Expected defined value');
    }
  },

  isFunction(value, message) {
    if (typeof value !== 'function') {
      throw new AssertionError(message || `Expected function, got ${typeof value}`);
    }
  },

  isObject(value, message) {
    if (typeof value !== 'object' || value === null) {
      throw new AssertionError(message || `Expected object, got ${typeof value}`);
    }
  },

  isArray(value, message) {
    if (!Array.isArray(value)) {
      throw new AssertionError(message || `Expected array, got ${typeof value}`);
    }
  },

  isString(value, message) {
    if (typeof value !== 'string') {
      throw new AssertionError(message || `Expected string, got ${typeof value}`);
    }
  },

  isNumber(value, message) {
    if (typeof value !== 'number' || isNaN(value)) {
      throw new AssertionError(message || `Expected number, got ${typeof value}`);
    }
  },

  // Comparison assertions
  isAbove(value, threshold, message) {
    if (!(value > threshold)) {
      throw new AssertionError(message || `Expected ${value} > ${threshold}`);
    }
  },

  isBelow(value, threshold, message) {
    if (!(value < threshold)) {
      throw new AssertionError(message || `Expected ${value} < ${threshold}`);
    }
  },

  isAtLeast(value, threshold, message) {
    if (!(value >= threshold)) {
      throw new AssertionError(message || `Expected ${value} >= ${threshold}`);
    }
  },

  isAtMost(value, threshold, message) {
    if (!(value <= threshold)) {
      throw new AssertionError(message || `Expected ${value} <= ${threshold}`);
    }
  },

  // String assertions
  include(haystack, needle, message) {
    if (typeof haystack === 'string') {
      if (!haystack.includes(needle)) {
        throw new AssertionError(message || `Expected "${haystack}" to include "${needle}"`);
      }
    } else if (Array.isArray(haystack)) {
      if (!haystack.includes(needle)) {
        throw new AssertionError(message || `Expected array to include ${needle}`);
      }
    } else {
      throw new AssertionError('include() requires string or array');
    }
  },

  match(value, regex, message) {
    if (!regex.test(value)) {
      throw new AssertionError(message || `Expected "${value}" to match ${regex}`);
    }
  },

  // Object assertions
  hasProperty(obj, prop, message) {
    if (!(prop in obj)) {
      throw new AssertionError(message || `Expected property "${prop}" to exist`);
    }
  },

  hasOwnProperty(obj, prop, message) {
    if (!Object.prototype.hasOwnProperty.call(obj, prop)) {
      throw new AssertionError(message || `Expected own property "${prop}"`);
    }
  },

  // Array assertions
  lengthOf(value, length, message) {
    if (value.length !== length) {
      throw new AssertionError(message || `Expected length ${length}, got ${value.length}`);
    }
  },

  isEmpty(value, message) {
    const len = value.length ?? Object.keys(value).length ?? 0;
    if (len !== 0) {
      throw new AssertionError(message || `Expected empty, got length ${len}`);
    }
  },

  isNotEmpty(value, message) {
    const len = value.length ?? Object.keys(value).length ?? 0;
    if (len === 0) {
      throw new AssertionError(message || 'Expected not empty');
    }
  },

  // Exception assertions
  throws(fn, expected, message) {
    let threw = false;
    let error = null;
    
    try {
      fn();
    } catch (e) {
      threw = true;
      error = e;
      
      if (expected) {
        if (typeof expected === 'string') {
          if (!e.message.includes(expected)) {
            throw new AssertionError(message || `Expected error message to include "${expected}"`);
          }
        } else if (expected instanceof RegExp) {
          if (!expected.test(e.message)) {
            throw new AssertionError(message || `Expected error message to match ${expected}`);
          }
        } else if (typeof expected === 'function') {
          if (!(e instanceof expected)) {
            throw new AssertionError(message || `Expected error to be instance of ${expected.name}`);
          }
        }
      }
    }
    
    if (!threw) {
      throw new AssertionError(message || 'Expected function to throw');
    }
    
    return error;
  },

  async throwsAsync(fn, expected, message) {
    let threw = false;
    let error = null;
    
    try {
      await fn();
    } catch (e) {
      threw = true;
      error = e;
      
      if (expected && typeof expected === 'string') {
        if (!e.message.includes(expected)) {
          throw new AssertionError(message || `Expected error message to include "${expected}"`);
        }
      }
    }
    
    if (!threw) {
      throw new AssertionError(message || 'Expected async function to throw');
    }
    
    return error;
  },

  doesNotThrow(fn, message) {
    try {
      fn();
    } catch (e) {
      throw new AssertionError(message || `Expected not to throw, but threw: ${e.message}`);
    }
  },

  // Approximate equality
  approximately(actual, expected, delta, message) {
    if (Math.abs(actual - expected) > delta) {
      throw new AssertionError(
        message || `Expected ${actual} to be within ${delta} of ${expected}`
      );
    }
  },

  // Instance check
  instanceOf(value, constructor, message) {
    if (!(value instanceof constructor)) {
      throw new AssertionError(
        message || `Expected instance of ${constructor.name}`
      );
    }
  },

  // Fail explicitly
  fail(message) {
    throw new AssertionError(message || 'Assertion failed');
  }
};

// ============================================================================
// Helper Classes and Functions
// ============================================================================

class AssertionError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AssertionError';
  }
}

function deepEquals(a, b) {
  if (a === b) return true;
  if (a === null || b === null) return false;
  if (typeof a !== typeof b) return false;
  
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    return a.every((val, i) => deepEquals(val, b[i]));
  }
  
  if (typeof a === 'object') {
    const keysA = Object.keys(a);
    const keysB = Object.keys(b);
    if (keysA.length !== keysB.length) return false;
    return keysA.every(key => deepEquals(a[key], b[key]));
  }
  
  return false;
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ============================================================================
// Global API
// ============================================================================

// Make test functions globally available
window.describe = TestRunner.describe.bind(TestRunner);
window.it = TestRunner.it.bind(TestRunner);
window.test = TestRunner.it.bind(TestRunner); // Alias
window.beforeEach = TestRunner.beforeEach.bind(TestRunner);
window.afterEach = TestRunner.afterEach.bind(TestRunner);
window.beforeAll = TestRunner.beforeAll.bind(TestRunner);
window.afterAll = TestRunner.afterAll.bind(TestRunner);
window.assert = assert;
window.expect = assert; // Alias

// Skip and only helpers
window.it.skip = TestRunner.skip.bind(TestRunner);
window.it.only = TestRunner.only.bind(TestRunner);

// Runner controls
window.runAllTests = () => TestRunner.runAll();
window.resetTests = () => TestRunner.reset();

// Export
window.TestRunner = TestRunner;
window.AssertionError = AssertionError;
