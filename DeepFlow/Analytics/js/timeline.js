/**
 * UniFlow Analytics Dashboard - Event Timeline Component
 */

const Timeline = {
  // Configuration
  config: {
    minZoom: 0.1,
    maxZoom: 10,
    defaultZoom: 1,
    rowHeight: 40,
    swimlaneHeight: 50,
    eventMinWidth: 8,
    eventMaxWidth: 200
  },

  // State
  state: {
    zoom: 1,
    panX: 0,
    events: [],
    selectedEvent: null,
    filter: {
      status: null,
      workflow: null,
      step: null
    }
  },

  /**
   * Initialize timeline in container
   * @param {HTMLElement} container - Timeline container
   * @param {Object} options - Configuration options
   */
  init(container, options = {}) {
    this.container = container;
    this.track = container.querySelector('.timeline-track') || container;
    this.axis = container.querySelector('.timeline-axis');
    
    this.options = {
      showSwimlanes: true,
      groupBy: 'workflow', // 'workflow' | 'status' | 'none'
      colorBy: 'status',   // 'status' | 'workflow' | 'step'
      ...options
    };

    this.setupInteractions();
    return this;
  },

  /**
   * Set timeline data
   * @param {Array} events - Array of event objects
   */
  setData(events) {
    this.state.events = events || [];
    this.render();
    return this;
  },

  /**
   * Set filter
   * @param {Object} filter - Filter criteria
   */
  setFilter(filter) {
    this.state.filter = { ...this.state.filter, ...filter };
    this.render();
    return this;
  },

  /**
   * Zoom in
   */
  zoomIn() {
    this.state.zoom = Math.min(this.state.zoom * 1.5, this.config.maxZoom);
    this.render();
    return this;
  },

  /**
   * Zoom out
   */
  zoomOut() {
    this.state.zoom = Math.max(this.state.zoom / 1.5, this.config.minZoom);
    this.render();
    return this;
  },

  /**
   * Reset zoom and pan
   */
  reset() {
    this.state.zoom = this.config.defaultZoom;
    this.state.panX = 0;
    this.render();
    return this;
  },

  /**
   * Setup mouse/touch interactions
   */
  setupInteractions() {
    if (!this.track) return;

    let isDragging = false;
    let startX = 0;
    let startPanX = 0;

    this.track.addEventListener('mousedown', (e) => {
      if (e.target.closest('.timeline-event')) return;
      isDragging = true;
      startX = e.clientX;
      startPanX = this.state.panX;
      this.track.style.cursor = 'grabbing';
    });

    document.addEventListener('mousemove', (e) => {
      if (!isDragging) return;
      const delta = e.clientX - startX;
      this.state.panX = startPanX + delta;
      this.render();
    });

    document.addEventListener('mouseup', () => {
      isDragging = false;
      if (this.track) this.track.style.cursor = 'grab';
    });

    // Wheel zoom
    this.track.addEventListener('wheel', (e) => {
      e.preventDefault();
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      const newZoom = Math.max(
        this.config.minZoom,
        Math.min(this.config.maxZoom, this.state.zoom * delta)
      );

      // Zoom towards mouse position
      const rect = this.track.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const ratio = newZoom / this.state.zoom;
      this.state.panX = mouseX - (mouseX - this.state.panX) * ratio;
      
      this.state.zoom = newZoom;
      this.render();
    });
  },

  /**
   * Render timeline
   */
  render() {
    if (!this.track) return;

    const events = this.filterEvents(this.state.events);
    
    if (events.length === 0) {
      this.track.innerHTML = `
        <div class="timeline-empty">
          <span>No events to display</span>
        </div>
      `;
      if (this.axis) this.axis.innerHTML = '';
      return;
    }

    // Calculate time bounds
    const timestamps = events.flatMap(e => [
      new Date(e.startTime).getTime(),
      e.endTime ? new Date(e.endTime).getTime() : Date.now()
    ]);
    const minTime = Math.min(...timestamps);
    const maxTime = Math.max(...timestamps);
    const timeRange = maxTime - minTime || 1;

    // Calculate layout
    const trackRect = this.track.getBoundingClientRect();
    const baseWidth = trackRect.width;
    const totalWidth = baseWidth * this.state.zoom;

    // Group events
    const groups = this.groupEvents(events);
    const groupKeys = Object.keys(groups);

    // Build HTML
    let html = '';
    const { rowHeight, swimlaneHeight } = this.config;
    const contentHeight = this.options.showSwimlanes 
      ? groupKeys.length * swimlaneHeight + 20
      : events.length * rowHeight + 20;

    // Swimlane rendering
    if (this.options.showSwimlanes) {
      groupKeys.forEach((groupKey, gi) => {
        const groupEvents = groups[groupKey];
        const laneY = gi * swimlaneHeight;

        // Swimlane label
        html += `
          <div class="timeline-swimlane" style="top: ${laneY}px; height: ${swimlaneHeight}px;">
            <div class="swimlane-label">${this.escapeHtml(groupKey)}</div>
            <div class="swimlane-events">
        `;

        // Events in this lane
        groupEvents.forEach(event => {
          const eventHtml = this.renderEvent(event, minTime, timeRange, totalWidth);
          html += eventHtml;
        });

        html += `
            </div>
          </div>
        `;
      });
    } else {
      // Flat rendering
      events.forEach((event, i) => {
        const eventHtml = this.renderEvent(event, minTime, timeRange, totalWidth, i * rowHeight);
        html += eventHtml;
      });
    }

    // Apply pan
    this.track.innerHTML = `
      <div class="timeline-content" style="width: ${totalWidth}px; height: ${contentHeight}px; transform: translateX(${this.state.panX}px);">
        ${html}
      </div>
    `;

    // Render axis
    this.renderAxis(minTime, maxTime, totalWidth);

    // Setup event handlers
    this.setupEventHandlers();
  },

  /**
   * Render a single event
   */
  renderEvent(event, minTime, timeRange, totalWidth, topOffset = null) {
    const startMs = new Date(event.startTime).getTime();
    const endMs = event.endTime ? new Date(event.endTime).getTime() : Date.now();
    const duration = endMs - startMs;

    const left = ((startMs - minTime) / timeRange) * totalWidth;
    const width = Math.max(
      this.config.eventMinWidth,
      Math.min(this.config.eventMaxWidth, (duration / timeRange) * totalWidth)
    );

    const colorClass = this.getEventColor(event);
    const statusIcon = this.getStatusIcon(event.status);
    const topStyle = topOffset !== null ? `top: ${topOffset + 5}px;` : '';

    return `
      <div class="timeline-event ${colorClass}" 
           style="left: ${left}px; width: ${width}px; ${topStyle}"
           data-event-id="${event.id}"
           title="${this.escapeHtml(event.name || event.step || 'Event')}">
        <span class="event-icon">${statusIcon}</span>
        <span class="event-label">${this.escapeHtml(event.name || event.step || '')}</span>
      </div>
    `;
  },

  /**
   * Render time axis
   */
  renderAxis(minTime, maxTime, totalWidth) {
    if (!this.axis) return;

    const range = maxTime - minTime;
    const tickCount = Math.max(5, Math.floor(totalWidth / 100));
    const tickInterval = range / tickCount;

    let html = `<div class="axis-content" style="width: ${totalWidth}px; transform: translateX(${this.state.panX}px);">`;
    
    for (let i = 0; i <= tickCount; i++) {
      const time = minTime + i * tickInterval;
      const x = (i / tickCount) * totalWidth;
      const label = this.formatAxisLabel(time, range);
      
      html += `
        <div class="axis-tick" style="left: ${x}px;">
          <div class="tick-line"></div>
          <div class="tick-label">${label}</div>
        </div>
      `;
    }

    html += '</div>';
    this.axis.innerHTML = html;
  },

  /**
   * Format axis label based on time range
   */
  formatAxisLabel(timestamp, range) {
    const date = new Date(timestamp);
    
    if (range < 3600000) { // < 1 hour
      return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } else if (range < 86400000) { // < 1 day
      return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
    } else if (range < 604800000) { // < 1 week
      return date.toLocaleDateString(undefined, { weekday: 'short', hour: '2-digit', minute: '2-digit' });
    } else {
      return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    }
  },

  /**
   * Filter events based on current filter state
   */
  filterEvents(events) {
    const { status, workflow, step } = this.state.filter;
    
    return events.filter(e => {
      if (status && e.status !== status) return false;
      if (workflow && e.workflow !== workflow) return false;
      if (step && e.step !== step) return false;
      return true;
    });
  },

  /**
   * Group events for swimlane display
   */
  groupEvents(events) {
    const groupBy = this.options.groupBy;
    if (groupBy === 'none') return { 'All Events': events };
    
    return Utils.groupBy(events, groupBy);
  },

  /**
   * Get color class for event
   */
  getEventColor(event) {
    const colorBy = this.options.colorBy;
    
    if (colorBy === 'status') {
      return Utils.getStatusColor(event.status);
    } else if (colorBy === 'workflow') {
      // Generate consistent color based on workflow name hash
      const colors = ['primary', 'info', 'warning', 'success'];
      const hash = this.simpleHash(event.workflow || '');
      return colors[hash % colors.length];
    }
    
    return 'primary';
  },

  /**
   * Get status icon
   */
  getStatusIcon(status) {
    const icons = {
      'running': 'â–?,
      'succeeded': 'âœ?,
      'success': 'âœ?,
      'failed': 'âœ?,
      'error': 'âœ?,
      'pending': 'â?,
      'waiting': 'â?,
      'cancelled': 'âŠ?
    };
    return icons[status?.toLowerCase()] || 'â—?;
  },

  /**
   * Setup event click handlers
   */
  setupEventHandlers() {
    const eventEls = this.track.querySelectorAll('.timeline-event');
    
    eventEls.forEach(el => {
      el.addEventListener('click', (e) => {
        const eventId = el.dataset.eventId;
        const event = this.state.events.find(ev => ev.id === eventId);
        
        if (event) {
          // Remove previous selection
          this.track.querySelectorAll('.timeline-event.selected').forEach(s => {
            s.classList.remove('selected');
          });
          
          el.classList.add('selected');
          this.state.selectedEvent = event;
          
          // Dispatch custom event
          const customEvent = new CustomEvent('timeline:select', { 
            detail: { event } 
          });
          this.container.dispatchEvent(customEvent);
        }
      });
    });
  },

  /**
   * Simple string hash function
   */
  simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  },

  /**
   * Escape HTML
   */
  escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
};

// Timeline-specific CSS (injected)
const timelineStyles = `
  .timeline-content {
    position: relative;
    min-height: 100%;
    transition: transform 0.1s ease-out;
  }

  .timeline-swimlane {
    position: absolute;
    left: 0;
    right: 0;
    border-bottom: 1px solid var(--ctp-surface1);
    display: flex;
  }

  .swimlane-label {
    width: 120px;
    flex-shrink: 0;
    padding: 8px 12px;
    font-size: 0.85rem;
    color: var(--text-secondary);
    background: var(--bg-card);
    border-right: 1px solid var(--ctp-surface1);
    position: sticky;
    left: 0;
    z-index: 2;
    display: flex;
    align-items: center;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .swimlane-events {
    flex: 1;
    position: relative;
    height: 100%;
  }

  .timeline-event {
    position: absolute;
    height: 28px;
    top: 50%;
    transform: translateY(-50%);
    border-radius: 4px;
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 0 8px;
    font-size: 0.8rem;
    cursor: pointer;
    transition: opacity 0.15s ease, transform 0.15s ease;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .timeline-event:hover {
    opacity: 0.85;
    transform: translateY(-50%) scale(1.02);
    z-index: 10;
  }

  .timeline-event.selected {
    box-shadow: 0 0 0 2px var(--ctp-lavender);
    z-index: 11;
  }

  .timeline-event.primary {
    background: var(--ctp-blue);
    color: var(--ctp-crust);
  }

  .timeline-event.success {
    background: var(--ctp-green);
    color: var(--ctp-crust);
  }

  .timeline-event.error {
    background: var(--ctp-red);
    color: var(--ctp-crust);
  }

  .timeline-event.warning {
    background: var(--ctp-yellow);
    color: var(--ctp-crust);
  }

  .timeline-event.info {
    background: var(--ctp-sapphire);
    color: var(--ctp-crust);
  }

  .event-icon {
    font-size: 0.75rem;
  }

  .event-label {
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .timeline-empty {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-muted);
  }

  /* Axis */
  .axis-content {
    position: relative;
    height: 100%;
  }

  .axis-tick {
    position: absolute;
    top: 0;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .tick-line {
    width: 1px;
    height: 8px;
    background: var(--ctp-surface2);
  }

  .tick-label {
    font-size: 0.75rem;
    color: var(--text-muted);
    white-space: nowrap;
    padding-top: 4px;
  }

  /* Event detail panel */
  .event-detail-panel {
    position: absolute;
    right: 0;
    top: 0;
    bottom: 0;
    width: 300px;
    background: var(--bg-card);
    border-left: 1px solid var(--border-color);
    padding: var(--spacing-md);
    transform: translateX(100%);
    transition: transform 0.3s ease;
    z-index: 100;
  }

  .event-detail-panel.visible {
    transform: translateX(0);
  }

  .event-detail-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: var(--spacing-md);
    padding-bottom: var(--spacing-sm);
    border-bottom: 1px solid var(--border-color);
  }

  .event-detail-title {
    font-weight: 600;
    font-size: 1rem;
  }

  .event-detail-close {
    background: none;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 1.25rem;
  }

  .event-detail-row {
    display: flex;
    justify-content: space-between;
    padding: var(--spacing-xs) 0;
    font-size: 0.9rem;
  }

  .event-detail-label {
    color: var(--text-secondary);
  }

  .event-detail-value {
    color: var(--text-primary);
    font-weight: 500;
  }
`;

// Inject styles
const styleEl = document.createElement('style');
styleEl.textContent = timelineStyles;
document.head.appendChild(styleEl);

// Export
window.Timeline = Timeline;
