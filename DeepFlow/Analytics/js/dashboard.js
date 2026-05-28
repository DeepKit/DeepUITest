/**
 * UniFlow Analytics Dashboard - Main Controller
 */

const Dashboard = {
  // Configuration
  config: {
    apiBaseUrl: '/api/analytics',
    refreshInterval: 30000, // 30 seconds
    autoRefresh: true
  },

  // State
  state: {
    timeRange: '7days',
    granularity: 'day',
    customRange: null,
    data: null,
    isLoading: false,
    lastUpdated: null
  },

  // DOM References
  elements: {},

  /**
   * Initialize dashboard
   */
  async init() {
    this.cacheElements();
    this.bindEvents();
    this.initTimeline();
    
    // Load initial data
    await this.loadData();

    // Setup auto-refresh
    if (this.config.autoRefresh) {
      setInterval(() => this.loadData(), this.config.refreshInterval);
    }

    console.log('UniFlow Analytics Dashboard initialized');
  },

  /**
   * Cache DOM element references
   */
  cacheElements() {
    this.elements = {
      // Summary cards
      totalFlows: document.getElementById('totalFlows'),
      completedFlows: document.getElementById('completedFlows'),
      failedFlows: document.getElementById('failedFlows'),
      successRate: document.getElementById('successRate'),
      avgDuration: document.getElementById('avgDuration'),

      // Charts
      executionTrendChart: document.getElementById('executionTrendChart'),
      successRateTrendChart: document.getElementById('successRateTrendChart'),
      latencyChart: document.getElementById('latencyChart'),

      // Tables
      workflowTableBody: document.getElementById('workflowTableBody'),
      errorTableBody: document.getElementById('errorTableBody'),
      workflowSearch: document.getElementById('workflowSearch'),
      errorCount: document.getElementById('errorCount'),

      // Anomalies
      anomaliesList: document.getElementById('anomaliesList'),

      // Timeline
      timelineContainer: document.getElementById('timelineContainer'),
      timelineZoomIn: document.getElementById('timelineZoomIn'),
      timelineZoomOut: document.getElementById('timelineZoomOut'),
      timelineReset: document.getElementById('timelineReset'),

      // Controls
      refreshBtn: document.getElementById('refreshBtn'),
      exportBtn: document.getElementById('exportBtn'),
      lastUpdated: document.getElementById('lastUpdated'),
      trendGranularity: document.getElementById('trendGranularity'),
      connectionStatus: document.getElementById('connectionStatus'),

      // Modal
      dateRangeModal: document.getElementById('dateRangeModal'),
      startDate: document.getElementById('startDate'),
      endDate: document.getElementById('endDate'),
      applyDateRange: document.getElementById('applyDateRange'),
      cancelDateRange: document.getElementById('cancelDateRange'),
      closeDateModal: document.getElementById('closeDateModal')
    };
  },

  /**
   * Bind event handlers
   */
  bindEvents() {
    // Time range buttons
    document.querySelectorAll('.range-btn').forEach(btn => {
      btn.addEventListener('click', (e) => this.handleTimeRangeChange(e));
    });

    // Refresh button
    this.elements.refreshBtn?.addEventListener('click', () => this.loadData());

    // Export button
    this.elements.exportBtn?.addEventListener('click', () => this.exportReport());

    // Granularity selector
    this.elements.trendGranularity?.addEventListener('change', (e) => {
      this.state.granularity = e.target.value;
      this.updateCharts();
    });

    // Workflow search
    this.elements.workflowSearch?.addEventListener('input', 
      Utils.debounce((e) => this.filterWorkflows(e.target.value), 300)
    );

    // Timeline controls
    this.elements.timelineZoomIn?.addEventListener('click', () => Timeline.zoomIn());
    this.elements.timelineZoomOut?.addEventListener('click', () => Timeline.zoomOut());
    this.elements.timelineReset?.addEventListener('click', () => Timeline.reset());

    // Modal handlers
    this.elements.applyDateRange?.addEventListener('click', () => this.applyCustomRange());
    this.elements.cancelDateRange?.addEventListener('click', () => this.closeModal());
    this.elements.closeDateModal?.addEventListener('click', () => this.closeModal());

    // Timeline event selection
    this.elements.timelineContainer?.addEventListener('timeline:select', (e) => {
      console.log('Selected event:', e.detail.event);
    });
  },

  /**
   * Initialize timeline component
   */
  initTimeline() {
    if (this.elements.timelineContainer) {
      Timeline.init(this.elements.timelineContainer, {
        showSwimlanes: true,
        groupBy: 'workflow',
        colorBy: 'status'
      });
    }
  },

  /**
   * Handle time range button click
   */
  handleTimeRangeChange(e) {
    const range = e.target.dataset.range;
    
    // Update active button
    document.querySelectorAll('.range-btn').forEach(btn => {
      btn.classList.remove('active');
    });
    e.target.classList.add('active');

    if (range === 'custom') {
      this.openDateRangeModal();
    } else {
      this.state.timeRange = range;
      this.state.customRange = null;
      this.loadData();
    }
  },

  /**
   * Open date range modal
   */
  openDateRangeModal() {
    const { start, end } = Utils.getTimeRange('7days');
    this.elements.startDate.value = this.formatDateTimeLocal(start);
    this.elements.endDate.value = this.formatDateTimeLocal(end);
    this.elements.dateRangeModal.classList.add('active');
  },

  /**
   * Close modal
   */
  closeModal() {
    this.elements.dateRangeModal.classList.remove('active');
  },

  /**
   * Apply custom date range
   */
  applyCustomRange() {
    const start = new Date(this.elements.startDate.value);
    const end = new Date(this.elements.endDate.value);

    if (start >= end) {
      alert('Start date must be before end date');
      return;
    }

    this.state.customRange = { start, end };
    this.state.timeRange = 'custom';
    this.closeModal();
    this.loadData();
  },

  /**
   * Format date for datetime-local input
   */
  formatDateTimeLocal(date) {
    const d = new Date(date);
    const pad = (n) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  },

  /**
   * Load dashboard data
   */
  async loadData() {
    if (this.state.isLoading) return;

    this.state.isLoading = true;
    this.showLoading(true);

    try {
      // In production, this would be an API call
      // For demo, we generate mock data
      const data = await this.fetchData();
      this.state.data = data;
      this.state.lastUpdated = new Date();

      this.updateSummaryCards();
      this.updateCharts();
      this.updateWorkflowTable();
      this.updateErrorTable();
      this.updateAnomalies();
      this.updateTimeline();
      this.updateLastUpdated();
    } catch (error) {
      console.error('Failed to load data:', error);
      this.showError('Failed to load dashboard data');
    } finally {
      this.state.isLoading = false;
      this.showLoading(false);
    }
  },

  /**
   * Fetch data from API (or generate demo data)
   */
  async fetchData() {
    // For demo purposes, generate mock data
    // In production, replace with actual API call:
    // return await Utils.fetch(`${this.config.apiBaseUrl}/overview?range=${this.state.timeRange}`);
    
    return this.generateDemoData();
  },

  /**
   * Generate demo data
   */
  generateDemoData() {
    const { start, end } = this.state.customRange || Utils.getTimeRange(this.state.timeRange);
    const workflows = ['CodeBuild', 'Deploy', 'Test', 'Analyze', 'Migrate'];
    const steps = ['Init', 'Parse', 'Process', 'Validate', 'Complete'];
    const statuses = ['succeeded', 'failed', 'running'];

    // Generate execution hiDeepStory
    const executions = [];
    const numExecutions = Math.floor(Math.random() * 100) + 50;
    const timeSpan = end.getTime() - start.getTime();

    for (let i = 0; i < numExecutions; i++) {
      const startTime = new Date(start.getTime() + Math.random() * timeSpan);
      const duration = Math.random() * 300000 + 10000; // 10s - 5min
      const status = statuses[Math.floor(Math.random() * (Math.random() > 0.8 ? 2 : 1))];
      
      executions.push({
        id: `exec-${i}`,
        workflow: workflows[Math.floor(Math.random() * workflows.length)],
        step: steps[Math.floor(Math.random() * steps.length)],
        status,
        startTime: startTime.toISOString(),
        endTime: new Date(startTime.getTime() + duration).toISOString(),
        duration
      });
    }

    // Calculate statistics
    const succeeded = executions.filter(e => e.status === 'succeeded').length;
    const failed = executions.filter(e => e.status === 'failed').length;
    const durations = executions.map(e => e.duration);

    // Generate trend data
    const buckets = Utils.generateTimeBuckets(start, end, this.state.granularity);
    const trendData = buckets.map((bucket, i) => {
      const bucketExecs = executions.filter(e => {
        const t = new Date(e.startTime).getTime();
        const nextBucket = buckets[i + 1]?.getTime() || end.getTime();
        return t >= bucket.getTime() && t < nextBucket;
      });
      
      return {
        x: bucket.getTime(),
        y: bucketExecs.length,
        label: Utils.formatDate(bucket, 'short'),
        succeeded: bucketExecs.filter(e => e.status === 'succeeded').length,
        failed: bucketExecs.filter(e => e.status === 'failed').length
      };
    });

    // Success rate trend
    const successRateTrend = trendData.map(d => ({
      x: d.x,
      y: d.y > 0 ? (d.succeeded / d.y) * 100 : 0,
      label: d.label
    }));

    // Workflow stats
    const workflowStats = workflows.map(wf => {
      const wfExecs = executions.filter(e => e.workflow === wf);
      const wfSucceeded = wfExecs.filter(e => e.status === 'succeeded').length;
      const wfFailed = wfExecs.filter(e => e.status === 'failed').length;
      const wfDurations = wfExecs.map(e => e.duration);
      
      return {
        name: wf,
        total: wfExecs.length,
        succeeded: wfSucceeded,
        failed: wfFailed,
        successRate: wfExecs.length > 0 ? (wfSucceeded / wfExecs.length) * 100 : 0,
        avgDuration: wfDurations.length > 0 ? Utils.calcStats(wfDurations).avg : 0
      };
    }).sort((a, b) => b.total - a.total);

    // Errors
    const errors = [];
    const errorCodes = ['E001', 'E002', 'E003', 'E004', 'E005'];
    const errorMessages = [
      'Connection timeout',
      'Invalid input format',
      'Resource not found',
      'Permission denied',
      'Internal error'
    ];
    
    executions.filter(e => e.status === 'failed').forEach(e => {
      const idx = Math.floor(Math.random() * errorCodes.length);
      const existing = errors.find(err => err.code === errorCodes[idx]);
      
      if (existing) {
        existing.count++;
        existing.lastSeen = e.startTime;
        existing.affected.add(e.workflow);
      } else {
        errors.push({
          code: errorCodes[idx],
          message: errorMessages[idx],
          count: 1,
          lastSeen: e.startTime,
          affected: new Set([e.workflow])
        });
      }
    });

    // Anomalies
    const anomalies = [];
    if (failed / executions.length > 0.2) {
      anomalies.push({
        type: 'critical',
        title: 'High Failure Rate',
        desc: `Failure rate is ${((failed / executions.length) * 100).toFixed(1)}%, exceeding 20% threshold`,
        time: new Date()
      });
    }
    
    const avgDur = Utils.calcStats(durations).avg;
    if (avgDur > 180000) {
      anomalies.push({
        type: 'warning',
        title: 'Slow Execution Time',
        desc: `Average execution time is ${Utils.formatDuration(avgDur)}, exceeding 3 minute threshold`,
        time: new Date()
      });
    }

    return {
      summary: {
        total: executions.length,
        succeeded,
        failed,
        running: executions.filter(e => e.status === 'running').length,
        successRate: executions.length > 0 ? (succeeded / executions.length) * 100 : 0,
        avgDuration: avgDur
      },
      trends: {
        executions: trendData,
        successRate: successRateTrend
      },
      workflows: workflowStats,
      errors: errors.map(e => ({
        ...e,
        affected: Array.from(e.affected)
      })),
      anomalies,
      latencies: durations,
      events: executions
    };
  },

  /**
   * Update summary cards
   */
  updateSummaryCards() {
    const { summary } = this.state.data;
    
    this.elements.totalFlows.textContent = Utils.formatNumber(summary.total);
    this.elements.completedFlows.textContent = Utils.formatNumber(summary.succeeded);
    this.elements.failedFlows.textContent = Utils.formatNumber(summary.failed);
    this.elements.successRate.textContent = Utils.formatPercent(summary.successRate);
    this.elements.avgDuration.textContent = Utils.formatDuration(summary.avgDuration);
  },

  /**
   * Update all charts
   */
  updateCharts() {
    const { trends, latencies, summary } = this.state.data;

    // Execution trend chart
    if (this.elements.executionTrendChart) {
      Charts.lineChart(this.elements.executionTrendChart, {
        series: [
          { name: 'Succeeded', data: trends.executions.map(d => ({ x: d.x, y: d.succeeded, label: d.label })), colorClass: 'success' },
          { name: 'Failed', data: trends.executions.map(d => ({ x: d.x, y: d.failed, label: d.label })), colorClass: 'error' }
        ],
        showArea: true,
        yMin: 0
      });
    }

    // Success rate trend chart
    if (this.elements.successRateTrendChart) {
      Charts.gaugeChart(this.elements.successRateTrendChart, {
        value: summary.successRate,
        max: 100,
        thresholds: { warning: 90, error: 80 },
        label: Utils.formatPercent(summary.successRate),
        sublabel: 'Success Rate'
      });
    }

    // Latency distribution chart
    if (this.elements.latencyChart) {
      Charts.histogram(this.elements.latencyChart, {
        data: latencies,
        bins: 10
      });
    }
  },

  /**
   * Update workflow table
   */
  updateWorkflowTable() {
    const { workflows } = this.state.data;
    
    if (!this.elements.workflowTableBody) return;

    const rows = workflows.map(wf => `
      <tr>
        <td><strong>${this.escapeHtml(wf.name)}</strong></td>
        <td>${Utils.formatNumber(wf.total)}</td>
        <td style="color: var(--accent-success)">${Utils.formatNumber(wf.succeeded)}</td>
        <td style="color: var(--accent-error)">${Utils.formatNumber(wf.failed)}</td>
        <td>
          <div style="display: flex; align-items: center; gap: 8px;">
            <div class="progress-bar" style="width: 60px;">
              <div class="progress-fill ${wf.successRate >= 90 ? 'success' : wf.successRate >= 70 ? 'warning' : 'error'}" 
                   style="width: ${wf.successRate}%"></div>
            </div>
            <span>${Utils.formatPercent(wf.successRate)}</span>
          </div>
        </td>
        <td>${Utils.formatDuration(wf.avgDuration)}</td>
      </tr>
    `).join('');

    this.elements.workflowTableBody.innerHTML = rows;
  },

  /**
   * Filter workflows in table
   */
  filterWorkflows(query) {
    const rows = this.elements.workflowTableBody?.querySelectorAll('tr') || [];
    const lowerQuery = query.toLowerCase();

    rows.forEach(row => {
      const name = row.querySelector('td strong')?.textContent?.toLowerCase() || '';
      row.style.display = name.includes(lowerQuery) ? '' : 'none';
    });
  },

  /**
   * Update error table
   */
  updateErrorTable() {
    const { errors } = this.state.data;
    
    if (!this.elements.errorTableBody) return;

    const rows = errors.map(err => `
      <tr>
        <td><code>${this.escapeHtml(err.code)}</code></td>
        <td>${this.escapeHtml(err.message)}</td>
        <td><strong>${err.count}</strong></td>
        <td>${Utils.relativeTime(err.lastSeen)}</td>
        <td>${err.affected.join(', ')}</td>
      </tr>
    `).join('');

    this.elements.errorTableBody.innerHTML = rows || '<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No errors</td></tr>';
    
    if (this.elements.errorCount) {
      const totalErrors = errors.reduce((sum, e) => sum + e.count, 0);
      this.elements.errorCount.textContent = totalErrors;
      this.elements.errorCount.style.display = totalErrors > 0 ? '' : 'none';
    }
  },

  /**
   * Update anomalies panel
   */
  updateAnomalies() {
    const { anomalies } = this.state.data;
    
    if (!this.elements.anomaliesList) return;

    if (anomalies.length === 0) {
      this.elements.anomaliesList.innerHTML = '<div class="empty-state">No anomalies detected</div>';
      return;
    }

    const items = anomalies.map(a => `
      <div class="anomaly-item ${a.type}">
        <span class="anomaly-icon">${a.type === 'critical' ? '🔴' : a.type === 'warning' ? '🟡' : 'ℹ️'}</span>
        <div class="anomaly-content">
          <div class="anomaly-title">${this.escapeHtml(a.title)}</div>
          <div class="anomaly-desc">${this.escapeHtml(a.desc)}</div>
          <div class="anomaly-time">${Utils.relativeTime(a.time)}</div>
        </div>
      </div>
    `).join('');

    this.elements.anomaliesList.innerHTML = items;
  },

  /**
   * Update timeline
   */
  updateTimeline() {
    const { events } = this.state.data;
    Timeline.setData(events);
  },

  /**
   * Update last updated timestamp
   */
  updateLastUpdated() {
    if (this.elements.lastUpdated) {
      this.elements.lastUpdated.textContent = `Updated: ${Utils.formatDate(this.state.lastUpdated, 'time')}`;
    }
  },

  /**
   * Export dashboard report
   */
  async exportReport() {
    const { data } = this.state;
    if (!data) return;

    const report = {
      generatedAt: new Date().toISOString(),
      timeRange: this.state.timeRange,
      summary: data.summary,
      workflows: data.workflows,
      errors: data.errors,
      anomalies: data.anomalies
    };

    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = `uniflow-analytics-${Utils.formatDate(new Date(), 'iso').slice(0, 10)}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.reDeepMoveChild(a);
    URL.revokeObjectURL(url);
  },

  /**
   * Show/hide loading state
   */
  showLoading(show) {
    // Could add loading indicators to charts/tables here
    if (this.elements.refreshBtn) {
      this.elements.refreshBtn.disabled = show;
      this.elements.refreshBtn.textContent = show ? '�? : '🔄';
    }
  },

  /**
   * Show error message
   */
  showError(message) {
    console.error(message);
    // Could show a toast notification here
  },

  /**
   * Escape HTML to prevent XSS attacks
   * @param {any} str - String to escape
   * @returns {string} - Escaped HTML string
   */
  escapeHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;')
      .replace(/`/g, '&#x60;')      // Prevent template literal injection
      .replace(/\//g, '&#x2F;');    // Prevent closing tags
  }
};

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  Dashboard.init();
});

// Export
window.Dashboard = Dashboard;
