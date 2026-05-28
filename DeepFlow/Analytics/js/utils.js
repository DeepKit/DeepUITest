/**
 * UniFlow Analytics Dashboard - Utility Functions
 */

const Utils = {
  // ===== Date & Time =====

  /**
   * Format a date for display
   */
  formatDate(date, format = 'short') {
    if (!date) return '--';
    const d = new Date(date);
    if (isNaN(d.getTime())) return '--';

    switch (format) {
      case 'full':
        return d.toLocaleString();
      case 'date':
        return d.toLocaleDateString();
      case 'time':
        return d.toLocaleTimeString();
      case 'short':
        return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
      case 'iso':
        return d.toISOString();
      default:
        return d.toLocaleString();
    }
  },

  /**
   * Format duration in milliseconds to human-readable string
   */
  formatDuration(ms) {
    if (ms == null || isNaN(ms)) return '--';
    
    if (ms < 1000) {
      return `${Math.round(ms)}ms`;
    } else if (ms < 60000) {
      return `${(ms / 1000).toFixed(1)}s`;
    } else if (ms < 3600000) {
      const mins = Math.floor(ms / 60000);
      const secs = Math.round((ms % 60000) / 1000);
      return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
    } else {
      const hours = Math.floor(ms / 3600000);
      const mins = Math.round((ms % 3600000) / 60000);
      return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
    }
  },

  /**
   * Get relative time string (e.g., "2 hours ago")
   */
  relativeTime(date) {
    if (!date) return '--';
    const d = new Date(date);
    if (isNaN(d.getTime())) return '--';

    const now = Date.now();
    const diff = now - d.getTime();
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (seconds < 60) return 'just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;
    return this.formatDate(d, 'short');
  },

  /**
   * Get time range boundaries
   */
  getTimeRange(range) {
    const now = new Date();
    const end = new Date(now);
    let start;

    switch (range) {
      case 'today':
        start = new Date(now);
        start.setHours(0, 0, 0, 0);
        break;
      case 'yesterday':
        start = new Date(now);
        start.setDate(start.getDate() - 1);
        start.setHours(0, 0, 0, 0);
        end.setHours(0, 0, 0, 0);
        break;
      case '7days':
        start = new Date(now);
        start.setDate(start.getDate() - 7);
        break;
      case '30days':
        start = new Date(now);
        start.setDate(start.getDate() - 30);
        break;
      case 'month':
        start = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      case 'lastMonth':
        start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        end.setDate(0); // Last day of previous month
        break;
      default:
        start = new Date(now);
        start.setDate(start.getDate() - 7);
    }

    return { start, end };
  },

  // ===== Number Formatting =====

  /**
   * Format a number with thousand separators
   */
  formatNumber(num, decimals = 0) {
    if (num == null || isNaN(num)) return '--';
    return num.toLocaleString(undefined, {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
  },

  /**
   * Format a percentage
   */
  formatPercent(value, decimals = 1) {
    if (value == null || isNaN(value)) return '--%';
    return `${value.toFixed(decimals)}%`;
  },

  /**
   * Format bytes to human-readable size
   */
  formatBytes(bytes) {
    if (bytes == null || isNaN(bytes)) return '--';
    if (bytes === 0) return '0 B';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    const value = bytes / Math.pow(1024, i);

    return `${value.toFixed(1)} ${units[i]}`;
  },

  /**
   * Compact number (e.g., 1.2K, 3.5M)
   */
  compactNumber(num) {
    if (num == null || isNaN(num)) return '--';
    if (num < 1000) return num.toString();
    if (num < 1000000) return `${(num / 1000).toFixed(1)}K`;
    if (num < 1000000000) return `${(num / 1000000).toFixed(1)}M`;
    return `${(num / 1000000000).toFixed(1)}B`;
  },

  // ===== Statistics =====

  /**
   * Calculate basic statistics from an array of numbers
   */
  calcStats(values) {
    if (!values || values.length === 0) {
      return { count: 0, sum: 0, min: 0, max: 0, avg: 0, stdDev: 0 };
    }

    const count = values.length;
    const sum = values.reduce((a, b) => a + b, 0);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const avg = sum / count;

    const variance = values.reduce((acc, val) => acc + Math.pow(val - avg, 2), 0) / count;
    const stdDev = Math.sqrt(variance);

    return { count, sum, min, max, avg, stdDev };
  },

  /**
   * Calculate percentile
   */
  percentile(values, p) {
    if (!values || values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = (p / 100) * (sorted.length - 1);
    const lower = Math.floor(index);
    const upper = Math.ceil(index);
    
    if (lower === upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
  },

  // ===== Color Utilities =====

  /**
   * Get status color class
   */
  getStatusColor(status) {
    const statusMap = {
      'success': 'success',
      'succeeded': 'success',
      'completed': 'success',
      'failed': 'error',
      'error': 'error',
      'running': 'primary',
      'pending': 'warning',
      'waiting': 'warning',
      'cancelled': 'warning'
    };
    return statusMap[status?.toLowerCase()] || 'primary';
  },

  /**
   * Interpolate between two colors
   */
  interpolateColor(color1, color2, factor) {
    // Convert hex to RGB
    const hex2rgb = (hex) => {
      const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
      return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
      } : null;
    };

    const rgb2hex = (r, g, b) => 
      '#' + [r, g, b].map(x => Math.round(x).toString(16).padStart(2, '0')).join('');

    const c1 = hex2rgb(color1);
    const c2 = hex2rgb(color2);

    if (!c1 || !c2) return color1;

    return rgb2hex(
      c1.r + factor * (c2.r - c1.r),
      c1.g + factor * (c2.g - c1.g),
      c1.b + factor * (c2.b - c1.b)
    );
  },

  // ===== DOM Utilities =====

  /**
   * Create an SVG element
   */
  createSVGElement(tag, attrs = {}) {
    const el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.entries(attrs).forEach(([key, value]) => {
      el.setAttribute(key, value);
    });
    return el;
  },

  /**
   * Create a DOM element with attributes and children
   */
  createElement(tag, attrs = {}, children = []) {
    const el = document.createElement(tag);
    Object.entries(attrs).forEach(([key, value]) => {
      if (key === 'className') {
        el.className = value;
      } else if (key === 'style' && typeof value === 'object') {
        Object.assign(el.style, value);
      } else if (key.startsWith('on') && typeof value === 'function') {
        el.addEventListener(key.slice(2).toLowerCase(), value);
      } else {
        el.setAttribute(key, value);
      }
    });
    children.forEach(child => {
      if (typeof child === 'string') {
        el.appendChild(document.createTextNode(child));
      } else if (child instanceof Node) {
        el.appendChild(child);
      }
    });
    return el;
  },

  /**
   * Debounce function
   */
  debounce(fn, delay = 300) {
    let timeoutId;
    return function (...args) {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => fn.apply(this, args), delay);
    };
  },

  /**
   * Throttle function
   */
  throttle(fn, limit = 100) {
    let inThrottle;
    return function (...args) {
      if (!inThrottle) {
        fn.apply(this, args);
        inThrottle = true;
        setTimeout(() => inThrottle = false, limit);
      }
    };
  },

  // ===== Data Processing =====

  /**
   * Group array by key
   */
  groupBy(array, key) {
    return array.reduce((groups, item) => {
      const value = typeof key === 'function' ? key(item) : item[key];
      (groups[value] = groups[value] || []).push(item);
      return groups;
    }, {});
  },

  /**
   * Sort array by key(s)
   */
  sortBy(array, keys, orders = []) {
    const keyArray = Array.isArray(keys) ? keys : [keys];
    const orderArray = Array.isArray(orders) ? orders : [orders];

    return [...array].sort((a, b) => {
      for (let i = 0; i < keyArray.length; i++) {
        const key = keyArray[i];
        const order = orderArray[i] === 'desc' ? -1 : 1;
        const aVal = typeof key === 'function' ? key(a) : a[key];
        const bVal = typeof key === 'function' ? key(b) : b[key];

        if (aVal < bVal) return -1 * order;
        if (aVal > bVal) return 1 * order;
      }
      return 0;
    });
  },

  /**
   * Generate time buckets for a range
   */
  generateTimeBuckets(start, end, granularity) {
    const buckets = [];
    const current = new Date(start);
    const endTime = new Date(end);

    while (current <= endTime) {
      buckets.push(new Date(current));

      switch (granularity) {
        case 'minute':
          current.setMinutes(current.getMinutes() + 1);
          break;
        case 'hour':
          current.setHours(current.getHours() + 1);
          break;
        case 'day':
          current.setDate(current.getDate() + 1);
          break;
        case 'week':
          current.setDate(current.getDate() + 7);
          break;
        case 'month':
          current.setMonth(current.getMonth() + 1);
          break;
        default:
          current.setHours(current.getHours() + 1);
      }
    }

    return buckets;
  },

  // ===== API Helpers =====

  /**
   * Simple HTTP client
   */
  async fetch(url, options = {}) {
    const defaultOptions = {
      headers: {
        'Content-Type': 'application/json'
      }
    };

    try {
      const response = await window.fetch(url, { ...defaultOptions, ...options });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error('Fetch error:', error);
      throw error;
    }
  },

  /**
   * Build query string from object
   */
  buildQueryString(params) {
    return Object.entries(params)
      .filter(([_, v]) => v != null && v !== '')
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');
  },

  // ===== Local Storage =====

  /**
   * Get item from localStorage with JSON parsing
   */
  getStorage(key, defaultValue = null) {
    try {
      const item = localStorage.getItem(key);
      return item ? JSON.parse(item) : defaultValue;
    } catch {
      return defaultValue;
    }
  },

  /**
   * Set item in localStorage with JSON stringify
   * @param {string} key - Storage key
   * @param {any} value - Value to store
   * @returns {boolean} - true if successful, false if failed
   */
  setStorage(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch (e) {
      console.error('localStorage write failed:', e.name, e.message);
      return false;
    }
  },

  // ===== Unique ID =====

  /**
   * Generate a simple unique ID
   */
  uid() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2);
  }
};

// Export for use in other modules
window.Utils = Utils;
