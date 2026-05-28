/**
 * UniFlow Timeline Visualization Component
 * 
 * 事件时间线可视化组件
 * 
 * 功能:
 * - 事件时间线渲�?
 * - 缩放/平移控制
 * - 事件详情弹窗
 * - 流程执行路径可视�?
 */

// ============================================================================
// Timeline Widget
// ============================================================================

class TimelineWidget {
  constructor(container, options = {}) {
    this.container = typeof container === 'string' 
      ? document.querySelector(container) 
      : container;
    
    this.options = {
      height: 400,
      trackHeight: 48,
      eventHeight: 32,
      minZoom: 0.1,
      maxZoom: 10,
      pixelsPerSecond: 100,
      showMinimap: true,
      showLegend: true,
      ...options
    };
    
    this.state = {
      zoom: 1,
      panX: 0,
      panY: 0,
      selectedEvent: null,
      hoveredEvent: null,
      isDragging: false,
      dragStart: { x: 0, y: 0 }
    };
    
    this.events = [];
    this.tracks = [];
    this.timeRange = { start: null, end: null };
    
    this.init();
  }
  
  init() {
    this.render();
    this.bindEvents();
  }
  
  // ============================================================================
  // Data Loading
  // ============================================================================
  
  setData(events) {
    this.events = events;
    this.processData();
    this.updateView();
  }
  
  processData() {
    if (this.events.length === 0) {
      this.tracks = [];
      this.timeRange = { start: Date.now(), end: Date.now() };
      return;
    }
    
    // 计算时间范围
    let minTime = Infinity;
    let maxTime = -Infinity;
    
    this.events.forEach(e => {
      const time = new Date(e.timestamp).getTime();
      minTime = Math.min(minTime, time);
      maxTime = Math.max(maxTime, time);
      if (e.endTime) {
        maxTime = Math.max(maxTime, new Date(e.endTime).getTime());
      }
    });
    
    this.timeRange = {
      start: minTime,
      end: maxTime + 1000 // 添加一秒缓�?
    };
    
    // 按步骤分组为轨道
    const trackMap = new Map();
    this.events.forEach(e => {
      const trackKey = e.step || 'default';
      if (!trackMap.has(trackKey)) {
        trackMap.set(trackKey, {
          name: trackKey,
          events: []
        });
      }
      trackMap.get(trackKey).events.push(e);
    });
    
    this.tracks = Array.from(trackMap.values());
    
    // 按开始时间排序每个轨道的事件
    this.tracks.forEach(track => {
      track.events.sort((a, b) => 
        new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      );
    });
  }
  
  // ============================================================================
  // Rendering
  // ============================================================================
  
  render() {
    this.container.innerHTML = `
      <div class="timeline-widget">
        <div class="timeline-header">
          <span class="timeline-title">Event Timeline</span>
          <div class="timeline-controls">
            <button class="timeline-zoom-btn" data-action="zoom-out" title="Zoom Out">�?/button>
            <span class="timeline-zoom-level">${Math.round(this.state.zoom * 100)}%</span>
            <button class="timeline-zoom-btn" data-action="zoom-in" title="Zoom In">+</button>
            <button class="timeline-zoom-btn" data-action="fit" title="Fit to View">�?/button>
          </div>
        </div>
        <div class="timeline-canvas-wrapper" style="height: ${this.options.height}px;">
          <div class="timeline-canvas">
            <div class="timeline-axis"></div>
            <div class="timeline-tracks"></div>
          </div>
        </div>
        ${this.options.showMinimap ? '<div class="timeline-minimap"><div class="timeline-minimap-content"></div></div>' : ''}
        ${this.options.showLegend ? `
          <div class="timeline-legend">
            <div class="timeline-legend-item"><span class="timeline-legend-dot started"></span> Started</div>
            <div class="timeline-legend-item"><span class="timeline-legend-dot running"></span> Running</div>
            <div class="timeline-legend-item"><span class="timeline-legend-dot succeeded"></span> Succeeded</div>
            <div class="timeline-legend-item"><span class="timeline-legend-dot failed"></span> Failed</div>
          </div>
        ` : ''}
      </div>
      <div class="timeline-tooltip"></div>
      <div class="timeline-detail-panel">
        <div class="timeline-detail-header">
          <span class="timeline-detail-title">Event Details</span>
          <button class="timeline-detail-close">�?/button>
        </div>
        <div class="timeline-detail-content"></div>
      </div>
    `;
    
    this.elements = {
      widget: this.container.querySelector('.timeline-widget'),
      wrapper: this.container.querySelector('.timeline-canvas-wrapper'),
      canvas: this.container.querySelector('.timeline-canvas'),
      axis: this.container.querySelector('.timeline-axis'),
      tracks: this.container.querySelector('.timeline-tracks'),
      tooltip: this.container.querySelector('.timeline-tooltip'),
      detailPanel: this.container.querySelector('.timeline-detail-panel'),
      detailContent: this.container.querySelector('.timeline-detail-content'),
      zoomLevel: this.container.querySelector('.timeline-zoom-level'),
      minimap: this.container.querySelector('.timeline-minimap-content')
    };
    
    this.updateView();
  }
  
  updateView() {
    this.renderAxis();
    this.renderTracks();
    this.updateMinimap();
  }
  
  renderAxis() {
    if (!this.elements.axis) return;
    
    const duration = this.timeRange.end - this.timeRange.start;
    const width = this.getTimelineWidth();
    
    // 计算刻度间隔
    const tickIntervals = [1000, 5000, 10000, 30000, 60000, 300000, 600000, 3600000];
    let tickInterval = tickIntervals.find(i => width / (duration / i) >= 60) || 3600000;
    
    let html = '';
    let time = Math.ceil(this.timeRange.start / tickInterval) * tickInterval;
    
    while (time <= this.timeRange.end) {
      const x = this.timeToX(time);
      const label = this.formatTime(time);
      html += `
        <div class="timeline-axis-tick" style="left: ${x}px;">
          <span class="timeline-axis-label" style="left: ${x}px;">${label}</span>
        </div>
      `;
      time += tickInterval;
    }
    
    this.elements.axis.innerHTML = html;
    this.elements.axis.style.width = `${width}px`;
  }
  
  renderTracks() {
    if (!this.elements.tracks) return;
    
    if (this.tracks.length === 0) {
      this.elements.tracks.innerHTML = `
        <div class="timeline-empty">
          <svg class="timeline-empty-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 8v4l3 3"/>
            <circle cx="12" cy="12" r="10"/>
          </svg>
          <div class="timeline-empty-title">No Events</div>
          <div class="timeline-empty-message">Load a flow to see its event timeline</div>
        </div>
      `;
      return;
    }
    
    const width = this.getTimelineWidth();
    
    let html = '';
    this.tracks.forEach((track, trackIndex) => {
      html += `
        <div class="timeline-track" data-track="${trackIndex}">
          <div class="timeline-track-label" title="${this.escapeHtml(track.name)}">${this.escapeHtml(track.name)}</div>
          <div class="timeline-track-content">
            ${track.events.map((event, eventIndex) => this.renderEvent(event, eventIndex, trackIndex)).join('')}
          </div>
        </div>
      `;
    });
    
    this.elements.tracks.innerHTML = html;
    this.elements.tracks.style.width = `${width}px`;
    this.elements.canvas.style.width = `${width}px`;
    
    // 应用平移
    this.applyTransform();
  }
  
  renderEvent(event, eventIndex, trackIndex) {
    const startTime = new Date(event.timestamp).getTime();
    const endTime = event.endTime ? new Date(event.endTime).getTime() : startTime + 500;
    
    const x = this.timeToX(startTime);
    const width = Math.max(24, this.timeToX(endTime) - x);
    const status = this.getEventStatus(event);
    
    return `
      <div class="timeline-event ${status} ${event === this.state.selectedEvent ? 'selected' : ''}"
           data-event-id="${event.id}"
           data-track="${trackIndex}"
           data-index="${eventIndex}"
           style="left: ${x}px; width: ${width}px;"
           title="${this.escapeHtml(event.step)}">
        <span class="timeline-event-label">${this.escapeHtml(event.step)}</span>
      </div>
    `;
  }
  
  updateMinimap() {
    if (!this.elements.minimap || this.events.length === 0) return;
    
    const containerWidth = this.elements.wrapper.clientWidth;
    const totalWidth = this.getTimelineWidth();
    const viewportWidth = containerWidth / totalWidth * containerWidth;
    const viewportLeft = -this.state.panX / totalWidth * containerWidth;
    
    let html = '';
    
    // 渲染小地图事�?
    this.events.forEach(event => {
      const startTime = new Date(event.timestamp).getTime();
      const x = (startTime - this.timeRange.start) / (this.timeRange.end - this.timeRange.start) * containerWidth;
      const status = this.getEventStatus(event);
      html += `<div class="timeline-minimap-event ${status}" style="left: ${x}px; width: 2px;"></div>`;
    });
    
    // 视口指示�?
    html += `<div class="timeline-minimap-viewport" style="left: ${viewportLeft}px; width: ${viewportWidth}px;"></div>`;
    
    this.elements.minimap.innerHTML = html;
  }
  
  // ============================================================================
  // Event Handling
  // ============================================================================
  
  bindEvents() {
    // Zoom buttons
    this.container.querySelectorAll('.timeline-zoom-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const action = e.target.dataset.action;
        if (action === 'zoom-in') this.zoomIn();
        else if (action === 'zoom-out') this.zoomOut();
        else if (action === 'fit') this.fitToView();
      });
    });
    
    // Pan with mouse drag
    this.elements.wrapper?.addEventListener('mousedown', (e) => {
      if (e.target.classList.contains('timeline-event')) return;
      this.state.isDragging = true;
      this.state.dragStart = { x: e.clientX - this.state.panX, y: e.clientY - this.state.panY };
      this.elements.wrapper.style.cursor = 'grabbing';
    });
    
    document.addEventListener('mousemove', (e) => {
      if (!this.state.isDragging) return;
      this.state.panX = e.clientX - this.state.dragStart.x;
      this.state.panY = e.clientY - this.state.dragStart.y;
      this.constrainPan();
      this.applyTransform();
      this.updateMinimap();
    });
    
    document.addEventListener('mouseup', () => {
      this.state.isDragging = false;
      if (this.elements.wrapper) {
        this.elements.wrapper.style.cursor = 'grab';
      }
    });
    
    // Zoom with wheel
    this.elements.wrapper?.addEventListener('wheel', (e) => {
      e.preventDefault();
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      this.zoom(delta, e.clientX);
    });
    
    // Event click
    this.container.addEventListener('click', (e) => {
      const eventEl = e.target.closest('.timeline-event');
      if (eventEl) {
        const trackIndex = parseInt(eventEl.dataset.track);
        const eventIndex = parseInt(eventEl.dataset.index);
        const event = this.tracks[trackIndex]?.events[eventIndex];
        if (event) {
          this.selectEvent(event);
        }
      }
    });
    
    // Event hover
    this.container.addEventListener('mouseover', (e) => {
      const eventEl = e.target.closest('.timeline-event');
      if (eventEl) {
        const trackIndex = parseInt(eventEl.dataset.track);
        const eventIndex = parseInt(eventEl.dataset.index);
        const event = this.tracks[trackIndex]?.events[eventIndex];
        if (event) {
          this.showTooltip(event, e);
        }
      }
    });
    
    this.container.addEventListener('mouseout', (e) => {
      if (e.target.closest('.timeline-event')) {
        this.hideTooltip();
      }
    });
    
    // Close detail panel
    this.container.querySelector('.timeline-detail-close')?.addEventListener('click', () => {
      this.closeDetailPanel();
    });
  }
  
  // ============================================================================
  // Zoom & Pan
  // ============================================================================
  
  zoom(factor, centerX = null) {
    const oldZoom = this.state.zoom;
    this.state.zoom = Math.min(this.options.maxZoom, Math.max(this.options.minZoom, this.state.zoom * factor));
    
    if (centerX !== null && this.elements.wrapper) {
      const rect = this.elements.wrapper.getBoundingClientRect();
      const mouseX = centerX - rect.left;
      const ratio = this.state.zoom / oldZoom;
      this.state.panX = mouseX - (mouseX - this.state.panX) * ratio;
    }
    
    this.constrainPan();
    this.updateView();
    this.updateZoomDisplay();
  }
  
  zoomIn() {
    this.zoom(1.25);
  }
  
  zoomOut() {
    this.zoom(0.8);
  }
  
  fitToView() {
    if (!this.elements.wrapper) return;
    
    const containerWidth = this.elements.wrapper.clientWidth;
    const timelineWidth = this.getTimelineWidth();
    
    this.state.zoom = Math.min(1, containerWidth / (timelineWidth / this.state.zoom));
    this.state.panX = 0;
    this.state.panY = 0;
    
    this.updateView();
    this.updateZoomDisplay();
  }
  
  constrainPan() {
    const containerWidth = this.elements.wrapper?.clientWidth || 800;
    const timelineWidth = this.getTimelineWidth();
    
    // 限制水平平移
    const maxPanX = 0;
    const minPanX = Math.min(0, containerWidth - timelineWidth);
    this.state.panX = Math.max(minPanX, Math.min(maxPanX, this.state.panX));
    
    // 限制垂直平移
    const containerHeight = this.elements.wrapper?.clientHeight || 400;
    const tracksHeight = this.tracks.length * this.options.trackHeight + 40;
    const maxPanY = 0;
    const minPanY = Math.min(0, containerHeight - tracksHeight);
    this.state.panY = Math.max(minPanY, Math.min(maxPanY, this.state.panY));
  }
  
  applyTransform() {
    if (this.elements.canvas) {
      this.elements.canvas.style.transform = `translate(${this.state.panX}px, ${this.state.panY}px)`;
    }
  }
  
  updateZoomDisplay() {
    if (this.elements.zoomLevel) {
      this.elements.zoomLevel.textContent = `${Math.round(this.state.zoom * 100)}%`;
    }
  }
  
  // ============================================================================
  // Event Selection & Details
  // ============================================================================
  
  selectEvent(event) {
    this.state.selectedEvent = event;
    this.renderTracks();
    this.showDetailPanel(event);
  }
  
  showTooltip(event, mouseEvent) {
    if (!this.elements.tooltip) return;
    
    const status = this.getEventStatus(event);
    const duration = event.endTime 
      ? new Date(event.endTime).getTime() - new Date(event.timestamp).getTime()
      : null;
    
    this.elements.tooltip.innerHTML = `
      <div class="timeline-tooltip-header">
        <span class="timeline-tooltip-title">${this.escapeHtml(event.step)}</span>
        <span class="timeline-tooltip-status ${status}">${status}</span>
      </div>
      <div class="timeline-tooltip-row">
        <span class="timeline-tooltip-label">Time</span>
        <span class="timeline-tooltip-value">${this.formatDateTime(event.timestamp)}</span>
      </div>
      ${duration ? `
        <div class="timeline-tooltip-row">
          <span class="timeline-tooltip-label">Duration</span>
          <span class="timeline-tooltip-value">${this.formatDuration(duration)}</span>
        </div>
      ` : ''}
      <div class="timeline-tooltip-row">
        <span class="timeline-tooltip-label">Source</span>
        <span class="timeline-tooltip-value">${this.escapeHtml(event.source || '-')}</span>
      </div>
      ${event.errorCode ? `
        <div class="timeline-tooltip-error">
          <strong>${this.escapeHtml(event.errorCode)}</strong>: ${this.escapeHtml(event.errorMessage || '')}
        </div>
      ` : ''}
    `;
    
    // 定位 tooltip
    const rect = this.container.getBoundingClientRect();
    let x = mouseEvent.clientX - rect.left + 10;
    let y = mouseEvent.clientY - rect.top + 10;
    
    // 确保不超出边�?
    const tooltipRect = this.elements.tooltip.getBoundingClientRect();
    if (x + tooltipRect.width > rect.width) {
      x = mouseEvent.clientX - rect.left - tooltipRect.width - 10;
    }
    if (y + tooltipRect.height > rect.height) {
      y = rect.height - tooltipRect.height - 10;
    }
    
    this.elements.tooltip.style.left = `${x}px`;
    this.elements.tooltip.style.top = `${y}px`;
    this.elements.tooltip.classList.add('visible');
  }
  
  hideTooltip() {
    this.elements.tooltip?.classList.remove('visible');
  }
  
  showDetailPanel(event) {
    if (!this.elements.detailContent || !this.elements.detailPanel) return;
    
    const status = this.getEventStatus(event);
    
    this.elements.detailContent.innerHTML = `
      <div class="timeline-detail-section">
        <div class="timeline-detail-section-title">Basic Info</div>
        <div class="timeline-detail-field">
          <div class="timeline-detail-field-label">Event ID</div>
          <div class="timeline-detail-field-value">${this.escapeHtml(event.id)}</div>
        </div>
        <div class="timeline-detail-field">
          <div class="timeline-detail-field-label">Step</div>
          <div class="timeline-detail-field-value">${this.escapeHtml(event.step)}</div>
        </div>
        <div class="timeline-detail-field">
          <div class="timeline-detail-field-label">Status</div>
          <div class="timeline-detail-field-value">
            <span class="timeline-tooltip-status ${status}">${status}</span>
          </div>
        </div>
        <div class="timeline-detail-field">
          <div class="timeline-detail-field-label">Timestamp</div>
          <div class="timeline-detail-field-value">${this.formatDateTime(event.timestamp)}</div>
        </div>
        <div class="timeline-detail-field">
          <div class="timeline-detail-field-label">Source</div>
          <div class="timeline-detail-field-value">${this.escapeHtml(event.source || '-')}</div>
        </div>
      </div>
      
      ${event.errorCode ? `
        <div class="timeline-detail-section">
          <div class="timeline-detail-section-title">Error</div>
          <div class="timeline-detail-field">
            <div class="timeline-detail-field-label">Error Code</div>
            <div class="timeline-detail-field-value">${this.escapeHtml(event.errorCode)}</div>
          </div>
          <div class="timeline-detail-field">
            <div class="timeline-detail-field-label">Message</div>
            <div class="timeline-detail-field-value">${this.escapeHtml(event.errorMessage || '-')}</div>
          </div>
        </div>
      ` : ''}
      
      ${event.payload ? `
        <div class="timeline-detail-section">
          <div class="timeline-detail-section-title">Payload</div>
          <pre class="timeline-detail-payload">${this.formatJson(event.payload)}</pre>
        </div>
      ` : ''}
      
      ${event.metadata ? `
        <div class="timeline-detail-section">
          <div class="timeline-detail-section-title">Metadata</div>
          <pre class="timeline-detail-payload">${this.formatJson(event.metadata)}</pre>
        </div>
      ` : ''}
    `;
    
    this.elements.detailPanel.classList.add('open');
  }
  
  closeDetailPanel() {
    this.elements.detailPanel?.classList.remove('open');
    this.state.selectedEvent = null;
    this.renderTracks();
  }
  
  // ============================================================================
  // Utilities
  // ============================================================================
  
  getTimelineWidth() {
    const duration = this.timeRange.end - this.timeRange.start;
    return Math.max(800, duration / 1000 * this.options.pixelsPerSecond * this.state.zoom);
  }
  
  timeToX(time) {
    const duration = this.timeRange.end - this.timeRange.start;
    const width = this.getTimelineWidth();
    return (time - this.timeRange.start) / duration * width;
  }
  
  xToTime(x) {
    const duration = this.timeRange.end - this.timeRange.start;
    const width = this.getTimelineWidth();
    return this.timeRange.start + x / width * duration;
  }
  
  getEventStatus(event) {
    if (event.status === 'Failed' || event.status === 'failed') return 'failed';
    if (event.status === 'Succeeded' || event.status === 'succeeded') return 'succeeded';
    if (event.status === 'Started' || event.status === 'started') return 'started';
    if (!event.endTime) return 'running';
    return 'started';
  }
  
  formatTime(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }
  
  formatDateTime(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }
  
  formatDuration(ms) {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  }
  
  formatJson(obj) {
    try {
      return JSON.stringify(obj, null, 2);
    } catch (e) {
      console.warn('Failed to stringify JSON:', e.message);
      return String(obj);
    }
  }
  
  escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
  
  // ============================================================================
  // Public API
  // ============================================================================
  
  destroy() {
    this.container.innerHTML = '';
  }
  
  refresh() {
    this.updateView();
  }
  
  scrollToEvent(eventId) {
    const event = this.events.find(e => e.id === eventId);
    if (event) {
      const time = new Date(event.timestamp).getTime();
      const x = this.timeToX(time);
      const containerWidth = this.elements.wrapper?.clientWidth || 800;
      this.state.panX = -x + containerWidth / 2;
      this.constrainPan();
      this.applyTransform();
      this.updateMinimap();
      this.selectEvent(event);
    }
  }
}

// ============================================================================
// Export
// ============================================================================

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { TimelineWidget };
}
