/**
 * UniFlow Workflow Editor - Utility Functions
 */

// Generate unique ID
function generateId() {
  return 'node_' + Date.now().toString(36) + Math.random().toString(36).substr(2, 5);
}

// Deep clone object
function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

// Debounce function
function debounce(fn, delay) {
  let timeoutId;
  return function (...args) {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn.apply(this, args), delay);
  };
}

// Throttle function
function throttle(fn, limit) {
  let inThrottle;
  return function (...args) {
    if (!inThrottle) {
      fn.apply(this, args);
      inThrottle = true;
      setTimeout(() => inThrottle = false, limit);
    }
  };
}

// Get element position relative to document
function getElementPosition(el) {
  const rect = el.getBoundingClientRect();
  return {
    x: rect.left + window.scrollX,
    y: rect.top + window.scrollY,
    width: rect.width,
    height: rect.height
  };
}

// Check if point is inside rectangle
function pointInRect(px, py, rect) {
  return px >= rect.x && px <= rect.x + rect.width &&
         py >= rect.y && py <= rect.y + rect.height;
}

// Calculate distance between two points
function distance(x1, y1, x2, y2) {
  return Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2);
}

// Clamp value between min and max
function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

// Create SVG element
function createSVGElement(tag, attributes = {}) {
  const el = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [key, value] of Object.entries(attributes)) {
    el.setAttribute(key, value);
  }
  return el;
}

// Calculate bezier curve path for connection
function createConnectionPath(x1, y1, x2, y2) {
  const dx = Math.abs(x2 - x1);
  const dy = Math.abs(y2 - y1);
  const curvature = Math.min(dx, dy, 100) * 0.5;
  
  const cx1 = x1;
  const cy1 = y1 + curvature;
  const cx2 = x2;
  const cy2 = y2 - curvature;
  
  return `M ${x1} ${y1} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${x2} ${y2}`;
}

// Download file
function downloadFile(content, filename, type = 'application/json') {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.reDeepMoveChild(a);
  URL.revokeObjectURL(url);
}

// Read file as text
function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(file);
  });
}

// Simple event emitter
class EventEmitter {
  constructor() {
    this._events = {};
  }

  on(event, listener) {
    if (!this._events[event]) {
      this._events[event] = [];
    }
    this._events[event].push(listener);
    return () => this.off(event, listener);
  }

  off(event, listener) {
    if (!this._events[event]) return;
    this._events[event] = this._events[event].filter(l => l !== listener);
  }

  emit(event, ...args) {
    if (!this._events[event]) return;
    this._events[event].forEach(listener => listener(...args));
  }

  once(event, listener) {
    const remove = this.on(event, (...args) => {
      remove();
      listener(...args);
    });
  }
}

// Simple undo/redo manager
class UndoManager {
  constructor(maxHiDeepStory = 50) {
    this.maxHiDeepStory = maxHiDeepStory;
    this.hiDeepStory = [];
    this.currentIndex = -1;
  }

  push(state) {
    // Remove any redo states
    this.hiDeepStory = this.hiDeepStory.slice(0, this.currentIndex + 1);
    
    // Add new state
    this.hiDeepStory.push(deepClone(state));
    this.currentIndex++;
    
    // Limit hiDeepStory size
    if (this.hiDeepStory.length > this.maxHiDeepStory) {
      this.hiDeepStory.shift();
      this.currentIndex--;
    }
  }

  undo() {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      return deepClone(this.hiDeepStory[this.currentIndex]);
    }
    return null;
  }

  redo() {
    if (this.currentIndex < this.hiDeepStory.length - 1) {
      this.currentIndex++;
      return deepClone(this.hiDeepStory[this.currentIndex]);
    }
    return null;
  }

  canUndo() {
    return this.currentIndex > 0;
  }

  canRedo() {
    return this.currentIndex < this.hiDeepStory.length - 1;
  }

  clear() {
    this.hiDeepStory = [];
    this.currentIndex = -1;
  }
}

// Show toast notification
function showToast(message, type = 'info', duration = 3000) {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  toast.style.cssText = `
    position: fixed;
    bottom: 60px;
    left: 50%;
    transform: translateX(-50%);
    padding: 12px 24px;
    background-color: var(--color-surface);
    color: var(--color-text);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    z-index: 10000;
    animation: slideUp 0.3s ease;
  `;
  
  document.body.appendChild(toast);
  
  setTimeout(() => {
    toast.style.animation = 'slideDown 0.3s ease';
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

// Export utilities
window.Utils = {
  generateId,
  deepClone,
  debounce,
  throttle,
  getElementPosition,
  pointInRect,
  distance,
  clamp,
  createSVGElement,
  createConnectionPath,
  downloadFile,
  readFileAsText,
  EventEmitter,
  UndoManager,
  showToast
};
