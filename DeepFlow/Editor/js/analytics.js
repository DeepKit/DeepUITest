/**
 * UniFlow Analytics Dashboard
 * 
 * 工作流执行统计分析面�?
 * 
 * 功能:
 * - 概览卡片 (总执行数/成功�?平均延迟/活跃工作�?
 * - 时间序列图表 (Chart.js)
 * - 工作流统计表�?(排序/筛�?
 * - 错误分布饼图
 * - 异常检测警�?
 * - 实时数据刷新
 */

// ============================================================================
// Mock Data (用于演示，实际使用时替换�?API 调用)
// ============================================================================

const MOCK_DATA = {
  summary: {
    totalFlows: 1247,
    completedFlows: 1089,
    failedFlows: 98,
    cancelledFlows: 32,
    runningFlows: 28,
    successRate: 87.3,
    avgDurationMs: 2340,
    totalEvents: 15680,
    uniqueWorkflows: 12
  },
  
  workflows: [
    { name: 'simple_qa', total: 456, success: 421, failed: 28, cancelled: 7, successRate: 92.3, avgDuration: 1850 },
    { name: 'code_review', total: 234, success: 198, failed: 31, cancelled: 5, successRate: 84.6, avgDuration: 4520 },
    { name: 'data_transform', total: 189, success: 172, failed: 12, cancelled: 5, successRate: 91.0, avgDuration: 980 },
    { name: 'multi_turn_chat', total: 167, success: 145, failed: 15, cancelled: 7, successRate: 86.8, avgDuration: 3200 },
    { name: 'report_generator', total: 89, success: 78, failed: 8, cancelled: 3, successRate: 87.6, avgDuration: 5670 },
    { name: 'email_processor', total: 67, success: 61, failed: 4, cancelled: 2, successRate: 91.0, avgDuration: 1240 },
    { name: 'ticket_classifier', total: 45, success: 14, failed: 0, cancelled: 3, successRate: 31.1, avgDuration: 890 }
  ],
  
  timeline: [
    { time: '00:00', executions: 45, successes: 41, failures: 4 },
    { time: '02:00', executions: 23, successes: 21, failures: 2 },
    { time: '04:00', executions: 12, successes: 11, failures: 1 },
    { time: '06:00', executions: 34, successes: 30, failures: 4 },
    { time: '08:00', executions: 89, successes: 78, failures: 11 },
    { time: '10:00', executions: 156, successes: 138, failures: 18 },
    { time: '12:00', executions: 178, successes: 159, failures: 19 },
    { time: '14:00', executions: 167, successes: 148, failures: 19 },
    { time: '16:00', executions: 189, successes: 165, failures: 24 },
    { time: '18:00', executions: 145, successes: 128, failures: 17 },
    { time: '20:00', executions: 112, successes: 99, failures: 13 },
    { time: '22:00', executions: 78, successes: 71, failures: 7 }
  ],
  
  errors: [
    { code: 'TIMEOUT', message: 'Request timeout', count: 34, workflows: ['code_review', 'report_generator'] },
    { code: 'LLM_ERROR', message: 'LLM API error', count: 28, workflows: ['simple_qa', 'multi_turn_chat'] },
    { code: 'VALIDATION', message: 'Input validation failed', count: 19, workflows: ['data_transform'] },
    { code: 'SKILL_ERROR', message: 'Skill execution failed', count: 12, workflows: ['code_review'] },
    { code: 'RATE_LIMIT', message: 'Rate limit exceeded', count: 5, workflows: ['simple_qa'] }
  ],
  
  anomalies: [
    { type: 'high_failure_rate', severity: 'warning', message: 'ticket_classifier success rate 31.1% is below 80%', value: 31.1 },
    { type: 'high_latency', severity: 'info', message: 'report_generator avg duration 5.67s exceeds 5s threshold', value: 5670 }
  ]
};

// ============================================================================
// Analytics Dashboard Class
// ============================================================================

class AnalyticsDashboard {
  constructor() {
    this.data = null;
    this.charts = {};
    this.sortColumn = 'total';
    this.sortDirection = 'desc';
    this.searchQuery = '';
    this.timeRange = '7days';
    this.autoRefresh = false;
    this.refreshInterval = null;
    
    this.init();
  }
  
  async init() {
    this.bindEvents();
    await this.loadData();
    this.render();
  }
  
  bindEvents() {
    // Time range selector
    document.getElementById('timeRange')?.addEventListener('change', (e) => {
      this.timeRange = e.target.value;
      this.loadData().then(() => this.render());
    });
    
    // Refresh button
    document.getElementById('refreshBtn')?.addEventListener('click', () => {
      this.loadData().then(() => this.render());
    });
    
    // Auto-refresh toggle
    document.getElementById('autoRefresh')?.addEventListener('change', (e) => {
      this.autoRefresh = e.target.checked;
      if (this.autoRefresh) {
        this.startAutoRefresh();
      } else {
        this.stopAutoRefresh();
      }
    });
    
    // Search input
    document.getElementById('workflowSearch')?.addEventListener('input', (e) => {
      this.searchQuery = e.target.value.toLowerCase();
      this.renderWorkflowTable();
    });
    
    // Table header sorting
    document.querySelectorAll('.data-table th[data-sort]').forEach(th => {
      th.addEventListener('click', () => {
        const column = th.dataset.sort;
        if (this.sortColumn === column) {
          this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
          this.sortColumn = column;
          this.sortDirection = 'desc';
        }
        this.renderWorkflowTable();
      });
    });
    
    // Export button
    document.getElementById('exportBtn')?.addEventListener('click', () => {
      this.exportReport();
    });
  }
  
  async loadData() {
    this.showLoading(true);
    
    try {
      // 实际使用时替换为 API 调用
      // const response = await fetch(`/api/analytics?range=${this.timeRange}`);
      // this.data = await response.json();
      
      // 使用 Mock 数据
      await new Promise(resolve => setTimeout(resolve, 500)); // 模拟网络延迟
      this.data = MOCK_DATA;
    } catch (error) {
      console.error('Failed to load analytics data:', error);
      this.showError('Failed to load data. Please try again.');
    } finally {
      this.showLoading(false);
    }
  }
  
  render() {
    if (!this.data) return;
    
    this.renderOverviewCards();
    this.renderTimeSeriesChart();
    this.renderErrorPieChart();
    this.renderWorkflowTable();
    this.renderAnomalies();
  }
  
  // ============================================================================
  // Overview Cards
  // ============================================================================
  
  renderOverviewCards() {
    const { summary } = this.data;
    
    this.updateCard('totalFlows', this.formatNumber(summary.totalFlows));
    this.updateCard('successRate', `${summary.successRate.toFixed(1)}%`);
    this.updateCard('failedFlows', this.formatNumber(summary.failedFlows));
    this.updateCard('activeFlows', this.formatNumber(summary.runningFlows));
    this.updateCard('avgLatency', this.formatDuration(summary.avgDurationMs));
  }
  
  updateCard(id, value) {
    const el = document.getElementById(id);
    if (el) {
      el.textContent = value;
    }
  }
  
  // ============================================================================
  // Time Series Chart
  // ============================================================================
  
  renderTimeSeriesChart() {
    const ctx = document.getElementById('timeSeriesChart')?.getContext('2d');
    if (!ctx) return;
    
    const { timeline } = this.data;
    
    // 销毁已存在的图�?
    if (this.charts.timeSeries) {
      this.charts.timeSeries.destroy();
    }
    
    this.charts.timeSeries = new Chart(ctx, {
      type: 'line',
      data: {
        labels: timeline.map(t => t.time),
        datasets: [
          {
            label: 'Executions',
            data: timeline.map(t => t.executions),
            borderColor: '#89b4fa',
            backgroundColor: 'rgba(137, 180, 250, 0.1)',
            fill: true,
            tension: 0.4
          },
          {
            label: 'Successes',
            data: timeline.map(t => t.successes),
            borderColor: '#a6e3a1',
            backgroundColor: 'transparent',
            tension: 0.4
          },
          {
            label: 'Failures',
            data: timeline.map(t => t.failures),
            borderColor: '#f38ba8',
            backgroundColor: 'transparent',
            tension: 0.4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            mode: 'index',
            intersect: false,
            backgroundColor: '#313244',
            titleColor: '#cdd6f4',
            bodyColor: '#a6adc8',
            borderColor: '#45475a',
            borderWidth: 1
          }
        },
        scales: {
          x: {
            grid: {
              color: 'rgba(69, 71, 90, 0.5)'
            },
            ticks: {
              color: '#a6adc8'
            }
          },
          y: {
            grid: {
              color: 'rgba(69, 71, 90, 0.5)'
            },
            ticks: {
              color: '#a6adc8'
            },
            beginAtZero: true
          }
        },
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        }
      }
    });
  }
  
  // ============================================================================
  // Error Pie Chart
  // ============================================================================
  
  renderErrorPieChart() {
    const ctx = document.getElementById('errorPieChart')?.getContext('2d');
    if (!ctx) return;
    
    const { errors } = this.data;
    
    // 销毁已存在的图�?
    if (this.charts.errorPie) {
      this.charts.errorPie.destroy();
    }
    
    const colors = ['#f38ba8', '#fab387', '#f9e2af', '#a6e3a1', '#89b4fa'];
    
    this.charts.errorPie = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: errors.map(e => e.code),
        datasets: [{
          data: errors.map(e => e.count),
          backgroundColor: colors,
          borderColor: '#1e1e2e',
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              color: '#a6adc8',
              padding: 16,
              usePointStyle: true
            }
          },
          tooltip: {
            backgroundColor: '#313244',
            titleColor: '#cdd6f4',
            bodyColor: '#a6adc8',
            callbacks: {
              label: (context) => {
                const error = errors[context.dataIndex];
                return `${error.count} occurrences`;
              }
            }
          }
        },
        cutout: '60%'
      }
    });
  }
  
  // ============================================================================
  // Workflow Table
  // ============================================================================
  
  renderWorkflowTable() {
    const tbody = document.getElementById('workflowTableBody');
    if (!tbody) return;
    
    let workflows = [...this.data.workflows];
    
    // 过滤
    if (this.searchQuery) {
      workflows = workflows.filter(w => 
        w.name.toLowerCase().includes(this.searchQuery)
      );
    }
    
    // 排序
    workflows.sort((a, b) => {
      let aVal = a[this.sortColumn];
      let bVal = b[this.sortColumn];
      
      if (typeof aVal === 'string') {
        aVal = aVal.toLowerCase();
        bVal = bVal.toLowerCase();
      }
      
      if (this.sortDirection === 'asc') {
        return aVal > bVal ? 1 : -1;
      } else {
        return aVal < bVal ? 1 : -1;
      }
    });
    
    // 更新排序指示�?
    document.querySelectorAll('.data-table th[data-sort]').forEach(th => {
      th.classList.remove('sorted');
      const icon = th.querySelector('.sort-icon');
      if (icon) {
        icon.textContent = '�?;
      }
    });
    
    const sortedTh = document.querySelector(`.data-table th[data-sort="${this.sortColumn}"]`);
    if (sortedTh) {
      sortedTh.classList.add('sorted');
      const icon = sortedTh.querySelector('.sort-icon');
      if (icon) {
        icon.textContent = this.sortDirection === 'asc' ? '�? : '�?;
      }
    }
    
    // 渲染�?
    tbody.innerHTML = workflows.map(w => `
      <tr>
        <td><span class="workflow-name">${this.escapeHtml(w.name)}</span></td>
        <td>${this.formatNumber(w.total)}</td>
        <td>${this.formatNumber(w.success)}</td>
        <td>${this.formatNumber(w.failed)}</td>
        <td>
          <div class="success-rate">
            <div class="success-rate-bar">
              <div class="success-rate-fill ${this.getSuccessRateClass(w.successRate)}" 
                   style="width: ${w.successRate}%"></div>
            </div>
            <span>${w.successRate.toFixed(1)}%</span>
          </div>
        </td>
        <td>${this.formatDuration(w.avgDuration)}</td>
      </tr>
    `).join('');
  }
  
  getSuccessRateClass(rate) {
    if (rate >= 90) return 'high';
    if (rate >= 70) return 'medium';
    return 'low';
  }
  
  // ============================================================================
  // Anomalies
  // ============================================================================
  
  renderAnomalies() {
    const container = document.getElementById('anomaliesList');
    if (!container) return;
    
    const { anomalies } = this.data;
    
    if (anomalies.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-title">No anomalies detected</div>
          <div class="empty-state-message">All metrics are within normal ranges</div>
        </div>
      `;
      return;
    }
    
    container.innerHTML = anomalies.map(a => `
      <div class="anomaly-item ${a.severity}">
        <svg class="anomaly-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          ${this.getAnomalyIcon(a.severity)}
        </svg>
        <div class="anomaly-content">
          <div class="anomaly-type">${this.formatAnomalyType(a.type)}</div>
          <div class="anomaly-message">${this.escapeHtml(a.message)}</div>
        </div>
        <div class="anomaly-value">${this.formatAnomalyValue(a)}</div>
      </div>
    `).join('');
  }
  
  getAnomalyIcon(severity) {
    switch (severity) {
      case 'error':
        return '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>';
      case 'warning':
        return '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>';
      default:
        return '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>';
    }
  }
  
  formatAnomalyType(type) {
    const types = {
      'high_failure_rate': 'High Failure Rate',
      'high_latency': 'High Latency',
      'too_many_running': 'Many Running Flows'
    };
    return types[type] || type;
  }
  
  formatAnomalyValue(anomaly) {
    switch (anomaly.type) {
      case 'high_failure_rate':
        return `${anomaly.value.toFixed(1)}%`;
      case 'high_latency':
        return this.formatDuration(anomaly.value);
      default:
        return anomaly.value;
    }
  }
  
  // ============================================================================
  // Auto Refresh
  // ============================================================================
  
  startAutoRefresh() {
    this.stopAutoRefresh();
    this.refreshInterval = setInterval(() => {
      this.loadData().then(() => this.render());
    }, 30000); // 30 秒刷新一�?
  }
  
  stopAutoRefresh() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }
  
  // ============================================================================
  // Export
  // ============================================================================
  
  exportReport() {
    const report = {
      generatedAt: new Date().toISOString(),
      timeRange: this.timeRange,
      summary: this.data.summary,
      workflows: this.data.workflows,
      errors: this.data.errors,
      anomalies: this.data.anomalies
    };
    
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `uniflow-analytics-${this.timeRange}-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }
  
  // ============================================================================
  // UI Helpers
  // ============================================================================
  
  showLoading(show) {
    const overlay = document.getElementById('loadingOverlay');
    if (overlay) {
      overlay.style.display = show ? 'flex' : 'none';
    }
  }
  
  showError(message) {
    // 可以替换为更好的通知组件
    alert(message);
  }
  
  // ============================================================================
  // Formatters
  // ============================================================================
  
  formatNumber(num) {
    if (num >= 1000000) {
      return (num / 1000000).toFixed(1) + 'M';
    }
    if (num >= 1000) {
      return (num / 1000).toFixed(1) + 'K';
    }
    return num.toLocaleString();
  }
  
  formatDuration(ms) {
    if (ms < 1000) {
      return `${Math.round(ms)}ms`;
    }
    if (ms < 60000) {
      return `${(ms / 1000).toFixed(1)}s`;
    }
    return `${(ms / 60000).toFixed(1)}m`;
  }
  
  escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
}

// ============================================================================
// Initialize Dashboard
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
  window.dashboard = new AnalyticsDashboard();
});
