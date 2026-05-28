/**
 * UniFlow 租户控制�?- 工具函数
 */

// ============================================================================
// 日期格式�?
// ============================================================================

const DateUtils = {
  /**
   * 格式化日�?
   */
  format(date, pattern = 'YYYY-MM-DD HH:mm:ss') {
    const d = new Date(date);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');
    const seconds = String(d.getSeconds()).padStart(2, '0');
    
    return pattern
      .replace('YYYY', year)
      .replace('MM', month)
      .replace('DD', day)
      .replace('HH', hours)
      .replace('mm', minutes)
      .replace('ss', seconds);
  },
  
  /**
   * 相对时间
   */
  relative(date) {
    const now = new Date();
    const d = new Date(date);
    const diff = now - d;
    
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    
    if (days > 0) return `${days} 天前`;
    if (hours > 0) return `${hours} 小时前`;
    if (minutes > 0) return `${minutes} 分钟前`;
    return '刚刚';
  },
  
  /**
   * 格式化时�?
   */
  duration(ms) {
    if (ms < 1000) return `${ms}ms`;
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
    const hours = Math.floor(minutes / 60);
    return `${hours}h ${minutes % 60}m`;
  },
  
  /**
   * 获取时间范围
   */
  getTimeRange(range) {
    const now = new Date();
    const end = new Date(now);
    let start = new Date(now);
    
    switch (range) {
      case 'today':
        start.setHours(0, 0, 0, 0);
        break;
      case '7d':
        start.setDate(start.getDate() - 7);
        break;
      case '30d':
        start.setDate(start.getDate() - 30);
        break;
      case '90d':
        start.setDate(start.getDate() - 90);
        break;
      default:
        start.setDate(start.getDate() - 30);
    }
    
    return { start, end };
  }
};

// ============================================================================
// 数字格式�?
// ============================================================================

const NumberUtils = {
  /**
   * 格式化数�?
   */
  format(num, decimals = 0) {
    return num.toLocaleString('zh-CN', {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
  },
  
  /**
   * 紧凑格式
   */
  compact(num) {
    if (num >= 1e9) return (num / 1e9).toFixed(1) + 'B';
    if (num >= 1e6) return (num / 1e6).toFixed(1) + 'M';
    if (num >= 1e3) return (num / 1e3).toFixed(1) + 'K';
    return num.toString();
  },
  
  /**
   * 百分�?
   */
  percent(value, total, decimals = 1) {
    if (total === 0) return '0%';
    return ((value / total) * 100).toFixed(decimals) + '%';
  },
  
  /**
   * 字节大小
   */
  bytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }
};

// ============================================================================
// DOM 工具
// ============================================================================

const DOM = {
  /**
   * 获取元素
   */
  $(selector) {
    return document.querySelector(selector);
  },
  
  /**
   * 获取所有元�?
   */
  $$(selector) {
    return document.querySelectorAll(selector);
  },
  
  /**
   * 创建元素
   */
  create(tag, attrs = {}, children = []) {
    const el = document.createElement(tag);
    
    Object.entries(attrs).forEach(([key, value]) => {
      if (key === 'className') {
        el.className = value;
      } else if (key === 'style' && typeof value === 'object') {
        Object.assign(el.style, value);
      } else if (key.startsWith('on') && typeof value === 'function') {
        el.addEventListener(key.slice(2).toLowerCase(), value);
      } else if (key === 'dataset') {
        Object.entries(value).forEach(([k, v]) => {
          el.dataset[k] = v;
        });
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
   * 显示/隐藏
   */
  show(el) {
    if (typeof el === 'string') el = this.$(el);
    el?.classList.remove('hidden');
  },
  
  hide(el) {
    if (typeof el === 'string') el = this.$(el);
    el?.classList.add('hidden');
  },
  
  toggle(el, show) {
    if (typeof el === 'string') el = this.$(el);
    if (show === undefined) {
      el?.classList.toggle('hidden');
    } else {
      show ? this.show(el) : this.hide(el);
    }
  },
  
  /**
   * 添加/移除�?
   */
  addClass(el, ...classes) {
    if (typeof el === 'string') el = this.$(el);
    el?.classList.add(...classes);
  },
  
  reDeepMoveClass(el, ...classes) {
    if (typeof el === 'string') el = this.$(el);
    el?.classList.remove(...classes);
  },
  
  /**
   * 清空内容
   */
  empty(el) {
    if (typeof el === 'string') el = this.$(el);
    if (el) el.innerHTML = '';
  }
};

// ============================================================================
// 存储工具
// ============================================================================

const Storage = {
  prefix: 'uniflow_console_',
  
  get(key, defaultValue = null) {
    try {
      const value = localStorage.getItem(this.prefix + key);
      return value ? JSON.parse(value) : defaultValue;
    } catch {
      return defaultValue;
    }
  },
  
  /**
   * Set a value in localStorage
   * @param {string} key - Storage key
   * @param {any} value - Value to store
   * @returns {boolean} - true if successful, false if failed (e.g., quota exceeded)
   */
  set(key, value) {
    try {
      localStorage.setItem(this.prefix + key, JSON.stringify(value));
      return true;
    } catch (e) {
      console.error('Storage.set failed:', e.name, e.message);
      // Notify caller of failure - could be QuotaExceededError
      return false;
    }
  },
  
  remove(key) {
    localStorage.removeItem(this.prefix + key);
  },
  
  clear() {
    Object.keys(localStorage)
      .filter(k => k.startsWith(this.prefix))
      .forEach(k => localStorage.removeItem(k));
  },
  
  /**
   * Get approximate storage usage
   * @returns {{ used: number, available: number }} - Storage info in bytes
   */
  getUsage() {
    let used = 0;
    for (let key in localStorage) {
      if (localStorage.hasOwnProperty(key) && key.startsWith(this.prefix)) {
        used += localStorage[key].length * 2; // UTF-16 = 2 bytes per char
      }
    }
    // Most browsers have 5MB limit
    const limit = 5 * 1024 * 1024;
    return { used, available: limit - used };
  }
};

// ============================================================================
// 事件总线
// ============================================================================

class EventBus {
  constructor() {
    this.listeners = {};
  }
  
  on(event, callback) {
    if (!this.listeners[event]) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(callback);
    return () => this.off(event, callback);
  }
  
  off(event, callback) {
    if (!this.listeners[event]) return;
    const idx = this.listeners[event].indexOf(callback);
    if (idx > -1) {
      this.listeners[event].splice(idx, 1);
    }
  }
  
  emit(event, ...args) {
    if (!this.listeners[event]) return;
    this.listeners[event].forEach(cb => cb(...args));
  }
}

const eventBus = new EventBus();

// ============================================================================
// 函数工具
// ============================================================================

/**
 * 防抖
 */
function debounce(fn, delay = 300) {
  let timer = null;
  return function(...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), delay);
  };
}

/**
 * 节流
 */
function throttle(fn, limit = 300) {
  let inThrottle = false;
  return function(...args) {
    if (!inThrottle) {
      fn.apply(this, args);
      inThrottle = true;
      setTimeout(() => inThrottle = false, limit);
    }
  };
}

/**
 * 深拷�?
 */
function deepClone(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  if (obj instanceof Date) return new Date(obj);
  if (obj instanceof Array) return obj.map(item => deepClone(item));
  if (obj instanceof Object) {
    const copy = {};
    Object.keys(obj).forEach(key => {
      copy[key] = deepClone(obj[key]);
    });
    return copy;
  }
  return obj;
}

/**
 * 生成 UUID
 */
function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

/**
 * 睡眠
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ============================================================================
// 验证工具
// ============================================================================

const Validators = {
  /**
   * 验证邮箱
   */
  email(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  },
  
  /**
   * 验证租户名称
   */
  tenantName(value) {
    return /^[a-zA-Z][a-zA-Z0-9_]{2,31}$/.test(value);
  },
  
  /**
   * 非空
   */
  required(value) {
    return value !== null && value !== undefined && value !== '';
  },
  
  /**
   * 数字范围
   */
  range(value, min, max) {
    const num = Number(value);
    return !isNaN(num) && num >= min && num <= max;
  }
};

// ============================================================================
// 状态映�?
// ============================================================================

const StatusMap = {
  tenant: {
    active: { label: '活跃', badge: 'success', icon: '�? },
    suspended: { label: '暂停', badge: 'warning', icon: '�? },
    archived: { label: '归档', badge: 'muted', icon: '📦' },
    deleted: { label: '已删�?, badge: 'danger', icon: '�? }
  },
  
  plan: {
    free: { label: '免费�?, badge: 'muted' },
    basic: { label: '基础�?, badge: 'info' },
    professional: { label: '专业�?, badge: 'success' },
    enterprise: { label: '企业�?, badge: 'warning' }
  },
  
  workflow: {
    created: { label: '已创�?, badge: 'muted' },
    running: { label: '运行�?, badge: 'info' },
    waiting_user: { label: '等待用户', badge: 'warning' },
    succeeded: { label: '成功', badge: 'success' },
    failed: { label: '失败', badge: 'danger' },
    cancelled: { label: '已取�?, badge: 'muted' }
  }
};

/**
 * 获取状态配�?
 */
function getStatusConfig(type, status) {
  return StatusMap[type]?.[status] || { label: status, badge: 'muted' };
}

// ============================================================================
// SVG 图表工具
// ============================================================================

const ChartUtils = {
  /**
   * 创建 SVG 元素
   */
  createSVG(width, height, viewBox) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', width);
    svg.setAttribute('height', height);
    if (viewBox) {
      svg.setAttribute('viewBox', viewBox);
    }
    return svg;
  },
  
  /**
   * 创建 SVG 子元�?
   */
  createSVGElement(tag, attrs = {}) {
    const el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.entries(attrs).forEach(([key, value]) => {
      el.setAttribute(key, value);
    });
    return el;
  },
  
  /**
   * 简单折线图
   */
  lineChart(container, data, options = {}) {
    const {
      width = 400,
      height = 200,
      padding = { top: 20, right: 20, bottom: 30, left: 40 },
      lineColor = '#89b4fa',
      fillColor = 'rgba(137, 180, 250, 0.2)'
    } = options;
    
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;
    
    const maxValue = Math.max(...data.map(d => d.value), 1);
    const minValue = Math.min(...data.map(d => d.value), 0);
    const valueRange = maxValue - minValue || 1;
    
    const xScale = (i) => padding.left + (i / (data.length - 1)) * chartWidth;
    const yScale = (v) => padding.top + chartHeight - ((v - minValue) / valueRange) * chartHeight;
    
    // 创建 SVG
    const svg = this.createSVG(width, height);
    
    // 创建路径
    const points = data.map((d, i) => `${xScale(i)},${yScale(d.value)}`).join(' ');
    const areaPoints = `${padding.left},${padding.top + chartHeight} ${points} ${width - padding.right},${padding.top + chartHeight}`;
    
    // 填充区域
    const area = this.createSVGElement('polygon', {
      points: areaPoints,
      fill: fillColor
    });
    svg.appendChild(area);
    
    // 折线
    const line = this.createSVGElement('polyline', {
      points,
      fill: 'none',
      stroke: lineColor,
      'stroke-width': '2'
    });
    svg.appendChild(line);
    
    // 数据�?
    data.forEach((d, i) => {
      const circle = this.createSVGElement('circle', {
        cx: xScale(i),
        cy: yScale(d.value),
        r: '3',
        fill: lineColor
      });
      svg.appendChild(circle);
    });
    
    // 清空并添�?
    container.innerHTML = '';
    container.appendChild(svg);
  },
  
  /**
   * 简单环形图
   */
  donutChart(container, data, options = {}) {
    const {
      size = 180,
      innerRadius = 50,
      outerRadius = 80,
      colors = ['#a6e3a1', '#f9e2af', '#f38ba8', '#89b4fa', '#cba6f7']
    } = options;
    
    const total = data.reduce((sum, d) => sum + d.value, 0);
    if (total === 0) {
      container.innerHTML = '<div class="empty-state"><span class="text-muted">无数�?/span></div>';
      return;
    }
    
    const svg = this.createSVG(size, size, `0 0 ${size} ${size}`);
    const center = size / 2;
    
    let startAngle = -Math.PI / 2;
    
    data.forEach((d, i) => {
      const angle = (d.value / total) * Math.PI * 2;
      const endAngle = startAngle + angle;
      
      const x1 = center + Math.cos(startAngle) * outerRadius;
      const y1 = center + Math.sin(startAngle) * outerRadius;
      const x2 = center + Math.cos(endAngle) * outerRadius;
      const y2 = center + Math.sin(endAngle) * outerRadius;
      const x3 = center + Math.cos(endAngle) * innerRadius;
      const y3 = center + Math.sin(endAngle) * innerRadius;
      const x4 = center + Math.cos(startAngle) * innerRadius;
      const y4 = center + Math.sin(startAngle) * innerRadius;
      
      const largeArc = angle > Math.PI ? 1 : 0;
      
      const path = this.createSVGElement('path', {
        d: `M ${x1} ${y1} A ${outerRadius} ${outerRadius} 0 ${largeArc} 1 ${x2} ${y2} L ${x3} ${y3} A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${x4} ${y4} Z`,
        fill: colors[i % colors.length]
      });
      
      svg.appendChild(path);
      startAngle = endAngle;
    });
    
    // 中心文本
    const text = this.createSVGElement('text', {
      x: center,
      y: center,
      'text-anchor': 'middle',
      'dominant-baseline': 'middle',
      fill: '#cdd6f4',
      'font-size': '24',
      'font-weight': 'bold'
    });
    text.textContent = total;
    svg.appendChild(text);
    
    container.innerHTML = '';
    container.appendChild(svg);
  },
  
  /**
   * 简单柱状图
   */
  barChart(container, data, options = {}) {
    const {
      width = 400,
      height = 200,
      padding = { top: 20, right: 20, bottom: 40, left: 50 },
      barColor = '#89b4fa',
      barGap = 4
    } = options;
    
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;
    
    const maxValue = Math.max(...data.map(d => d.value), 1);
    const barWidth = (chartWidth - barGap * (data.length - 1)) / data.length;
    
    const svg = this.createSVG(width, height);
    
    data.forEach((d, i) => {
      const barHeight = (d.value / maxValue) * chartHeight;
      const x = padding.left + i * (barWidth + barGap);
      const y = padding.top + chartHeight - barHeight;
      
      const rect = this.createSVGElement('rect', {
        x,
        y,
        width: barWidth,
        height: barHeight,
        fill: barColor,
        rx: '2'
      });
      svg.appendChild(rect);
      
      // 标签
      const label = this.createSVGElement('text', {
        x: x + barWidth / 2,
        y: height - 10,
        'text-anchor': 'middle',
        fill: '#a6adc8',
        'font-size': '10'
      });
      label.textContent = d.label;
      svg.appendChild(label);
    });
    
    container.innerHTML = '';
    container.appendChild(svg);
  }
};

// ============================================================================
// 导出
// ============================================================================

window.DateUtils = DateUtils;
window.NumberUtils = NumberUtils;
window.DOM = DOM;
window.Storage = Storage;
window.eventBus = eventBus;
window.debounce = debounce;
window.throttle = throttle;
window.deepClone = deepClone;
window.uuid = uuid;
window.sleep = sleep;
window.Validators = Validators;
window.StatusMap = StatusMap;
window.getStatusConfig = getStatusConfig;
window.ChartUtils = ChartUtils;
