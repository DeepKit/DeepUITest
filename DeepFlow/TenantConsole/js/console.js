/**
 * UniFlow 租户控制�?- 主控制器
 */

// ============================================================================
// 应用状�?
// ============================================================================

const AppState = {
  currentView: 'dashboard',
  tenants: {
    page: 1,
    pageSize: 10,
    status: '',
    plan: ''
  },
  workflows: {
    page: 1,
    pageSize: 10,
    tenantId: '',
    status: ''
  },
  usage: {
    tenantId: '',
    range: '30d'
  },
  quotas: {
    currentPlan: 'free'
  }
};

// ============================================================================
// 视图管理
// ============================================================================

const ViewManager = {
  views: {
    dashboard: { title: '仪表�?, load: loadDashboard },
    tenants: { title: '租户管理', load: loadTenants },
    quotas: { title: '配额管理', load: loadQuotas },
    usage: { title: '用量统计', load: loadUsage },
    workflows: { title: '工作�?, load: loadWorkflows },
    settings: { title: '系统设置', load: loadSettings }
  },
  
  switchTo(viewName) {
    if (!this.views[viewName]) return;
    
    // 更新导航
    DOM.$$('.nav-item').forEach(item => {
      item.classList.toggle('active', item.dataset.view === viewName);
    });
    
    // 切换视图
    DOM.$$('.view').forEach(view => {
      view.classList.add('hidden');
    });
    DOM.$(`#${viewName}View`).classList.remove('hidden');
    
    // 更新标题
    DOM.$('#pageTitle').textContent = this.views[viewName].title;
    
    // 加载数据
    AppState.currentView = viewName;
    this.views[viewName].load();
  }
};

// ============================================================================
// 仪表�?
// ============================================================================

async function loadDashboard() {
  try {
    // 加载概览数据
    const overview = await API.getDashboardOverview();
    DOM.$('#activeTenants').textContent = overview.activeTenants;
    DOM.$('#todayFlows').textContent = NumberUtils.compact(overview.todayFlows);
    DOM.$('#apiCalls').textContent = NumberUtils.compact(overview.apiCalls);
    DOM.$('#quotaAlerts').textContent = overview.quotaAlerts;
    
    // 加载租户分布�?
    const distribution = await API.getTenantDistribution();
    ChartUtils.donutChart(DOM.$('#tenantDistChart'), distribution);
    
    // 加载流程趋势�?
    await loadFlowTrendChart();
    
    // 加载最近活�?
    await loadRecentActivity();
  } catch (e) {
    console.error('Load dashboard failed:', e);
    Toast.error('加载仪表板失�?);
  }
}

async function loadFlowTrendChart() {
  const range = DOM.$('#flowTrendRange')?.value || '7d';
  const data = await API.getFlowTrend(range);
  ChartUtils.lineChart(DOM.$('#flowTrendChart'), data.map(d => ({
    label: d.label,
    value: d.flows
  })));
}

async function loadRecentActivity() {
  const activities = await API.getRecentActivity(5);
  const tbody = DOM.$('#recentActivityTable');
  tbody.innerHTML = '';
  
  if (activities.length === 0) {
    Empty.show(tbody, '暂无活动记录');
    return;
  }
  
  activities.forEach(a => {
    tbody.appendChild(Table.renderActivityRow(a));
  });
}

// ============================================================================
// 租户管理
// ============================================================================

async function loadTenants() {
  const tbody = DOM.$('#tenantsTable');
  
  try {
    const result = await API.getTenants({
      page: AppState.tenants.page,
      pageSize: AppState.tenants.pageSize,
      status: AppState.tenants.status,
      plan: AppState.tenants.plan
    });
    
    tbody.innerHTML = '';
    
    if (result.data.length === 0) {
      Empty.show(tbody, '暂无租户');
      return;
    }
    
    result.data.forEach(tenant => {
      tbody.appendChild(Table.renderTenantRow(tenant));
    });
    
    // 分页
    Pagination.render('#tenantsPagination', {
      page: result.page,
      totalPages: result.totalPages,
      onChange: (page) => {
        AppState.tenants.page = page;
        loadTenants();
      }
    });
  } catch (e) {
    console.error('Load tenants failed:', e);
    Toast.error('加载租户列表失败');
  }
}

function openTenantModal(tenant = null) {
  const isEdit = !!tenant;
  DOM.$('#tenantModalTitle').textContent = isEdit ? '编辑租户' : '创建租户';
  
  if (isEdit) {
    DOM.$('#tenantId').value = tenant.id;
    DOM.$('#tenantName').value = tenant.name;
    DOM.$('#tenantName').disabled = true;
    DOM.$('#tenantDisplayName').value = tenant.displayName;
    DOM.$('#tenantPlan').value = tenant.plan;
    DOM.$('#tenantOwnerEmail').value = tenant.ownerEmail || '';
    DOM.$('#tenantNotes').value = '';
  } else {
    Form.reset('tenantForm');
    DOM.$('#tenantId').value = '';
    DOM.$('#tenantName').disabled = false;
  }
  
  Modal.open('tenantModal');
}

async function saveTenant() {
  const id = DOM.$('#tenantId').value;
  const data = {
    name: DOM.$('#tenantName').value,
    displayName: DOM.$('#tenantDisplayName').value,
    plan: DOM.$('#tenantPlan').value,
    ownerEmail: DOM.$('#tenantOwnerEmail').value
  };
  
  // 验证
  if (!data.name || !data.displayName) {
    Toast.warning('请填写必填字�?);
    return;
  }
  
  if (!id && !Validators.tenantName(data.name)) {
    Toast.warning('租户名称只能包含字母、数字和下划�?);
    return;
  }
  
  try {
    if (id) {
      await API.updateTenant(id, data);
      Toast.success('租户更新成功');
    } else {
      await API.createTenant(data);
      Toast.success('租户创建成功');
    }
    
    Modal.close();
    loadTenants();
  } catch (e) {
    Toast.error(e.message || '操作失败');
  }
}

async function deleteTenant(tenant) {
  Modal.confirm({
    title: '删除租户',
    message: `确定要删除租�?"${tenant.displayName}" 吗？此操作不可恢复。`,
    confirmText: '删除',
    onConfirm: async () => {
      try {
        await API.deleteTenant(tenant.id);
        Toast.success('租户已删�?);
        loadTenants();
      } catch (e) {
        Toast.error(e.message || '删除失败');
      }
    }
  });
}

async function suspendTenant(tenant) {
  Modal.confirm({
    title: '暂停租户',
    message: `确定要暂停租�?"${tenant.displayName}" 吗？暂停后该租户将无法执行新流程。`,
    confirmText: '暂停',
    onConfirm: async () => {
      try {
        await API.suspendTenant(tenant.id);
        Toast.success('租户已暂�?);
        loadTenants();
      } catch (e) {
        Toast.error(e.message || '操作失败');
      }
    }
  });
}

async function activateTenant(tenant) {
  try {
    await API.activateTenant(tenant.id);
    Toast.success('租户已激�?);
    loadTenants();
  } catch (e) {
    Toast.error(e.message || '操作失败');
  }
}

// ============================================================================
// 配额管理
// ============================================================================

async function loadQuotas() {
  const plan = AppState.quotas.currentPlan;
  const quota = await API.getPlanQuota(plan);
  
  DOM.$('#quotaMaxActiveFlows').value = quota.maxActiveFlows;
  DOM.$('#quotaMaxFlowsPerDay').value = quota.maxFlowsPerDay;
  DOM.$('#quotaMaxEventsPerFlow').value = quota.maxEventsPerFlow;
  DOM.$('#quotaMaxStorageMB').value = quota.maxStorageMB;
  DOM.$('#quotaMaxSnapshotsPerFlow').value = quota.maxSnapshotsPerFlow;
  DOM.$('#quotaMaxRequestsPerMinute').value = quota.maxRequestsPerMinute;
  DOM.$('#quotaMaxRequestsPerDay').value = quota.maxRequestsPerDay;
  DOM.$('#quotaMaxLLMRequestsPerDay').value = quota.maxLLMRequestsPerDay;
  DOM.$('#quotaMaxTokensPerDay').value = quota.maxTokensPerDay;
  DOM.$('#quotaAllowParallel').checked = quota.allowParallelExecution;
  DOM.$('#quotaAllowSubworkflows').checked = quota.allowSubworkflows;
  DOM.$('#quotaAllowCustomSkills').checked = quota.allowCustomSkills;
}

async function saveQuota() {
  const quota = {
    maxActiveFlows: parseInt(DOM.$('#quotaMaxActiveFlows').value) || 0,
    maxFlowsPerDay: parseInt(DOM.$('#quotaMaxFlowsPerDay').value) || 0,
    maxEventsPerFlow: parseInt(DOM.$('#quotaMaxEventsPerFlow').value) || 0,
    maxStorageMB: parseInt(DOM.$('#quotaMaxStorageMB').value) || 0,
    maxSnapshotsPerFlow: parseInt(DOM.$('#quotaMaxSnapshotsPerFlow').value) || 0,
    maxRequestsPerMinute: parseInt(DOM.$('#quotaMaxRequestsPerMinute').value) || 0,
    maxRequestsPerDay: parseInt(DOM.$('#quotaMaxRequestsPerDay').value) || 0,
    maxLLMRequestsPerDay: parseInt(DOM.$('#quotaMaxLLMRequestsPerDay').value) || 0,
    maxTokensPerDay: parseInt(DOM.$('#quotaMaxTokensPerDay').value) || 0,
    allowParallelExecution: DOM.$('#quotaAllowParallel').checked,
    allowSubworkflows: DOM.$('#quotaAllowSubworkflows').checked,
    allowCustomSkills: DOM.$('#quotaAllowCustomSkills').checked
  };
  
  try {
    await API.updatePlanQuota(AppState.quotas.currentPlan, quota);
    Toast.success('配额配置已保�?);
  } catch (e) {
    Toast.error('保存失败');
  }
}

// ============================================================================
// 用量统计
// ============================================================================

async function loadUsage() {
  try {
    // 加载租户选择�?
    const tenantsResult = await API.getTenants({ pageSize: 100 });
    Dropdown.populateTenantSelect('usageTenantSelect', tenantsResult.data);
    
    // 加载用量概览
    const overview = await API.getUsageOverview({
      tenantId: AppState.usage.tenantId,
      range: AppState.usage.range
    });
    
    DOM.$('#usageTotalFlows').textContent = NumberUtils.compact(overview.totalFlows);
    DOM.$('#usageTotalAPI').textContent = NumberUtils.compact(overview.totalAPI);
    DOM.$('#usageTotalTokens').textContent = NumberUtils.compact(overview.totalTokens);
    DOM.$('#usageTotalStorage').textContent = `${overview.totalStorage} MB`;
    
    // 趋势指示
    updateTrendIndicator('#usageFlowsTrend', overview.trends.flows);
    updateTrendIndicator('#usageAPITrend', overview.trends.api);
    updateTrendIndicator('#usageTokensTrend', overview.trends.tokens);
    updateTrendIndicator('#usageStorageTrend', overview.trends.storage);
    
    // 用量趋势�?
    const trendData = await API.getUsageTrend({
      tenantId: AppState.usage.tenantId,
      range: AppState.usage.range
    });
    ChartUtils.lineChart(DOM.$('#usageTrendChart'), trendData.map(d => ({
      label: d.label,
      value: d.flows
    })), { width: 800, height: 280 });
    
    // 用量排行
    await loadUsageRanking();
  } catch (e) {
    console.error('Load usage failed:', e);
    Toast.error('加载用量统计失败');
  }
}

function updateTrendIndicator(selector, value) {
  const el = DOM.$(selector);
  if (!el) return;
  
  const isUp = value >= 0;
  el.textContent = `${isUp ? '+' : ''}${value}%`;
  el.className = `card-trend ${isUp ? 'up' : 'down'}`;
}

async function loadUsageRanking() {
  const ranking = await API.getUsageRanking({ limit: 10 });
  const tbody = DOM.$('#usageRankingTable');
  tbody.innerHTML = '';
  
  if (ranking.length === 0) {
    Empty.show(tbody, '暂无数据');
    return;
  }
  
  ranking.forEach(item => {
    tbody.appendChild(Table.renderUsageRankingRow(item));
  });
}

// ============================================================================
// 工作�?
// ============================================================================

async function loadWorkflows() {
  // 加载租户选择�?
  const tenantsResult = await API.getTenants({ pageSize: 100 });
  Dropdown.populateTenantSelect('workflowTenantSelect', tenantsResult.data);
  
  const tbody = DOM.$('#workflowsTable');
  
  try {
    const result = await API.getWorkflows({
      page: AppState.workflows.page,
      pageSize: AppState.workflows.pageSize,
      tenantId: AppState.workflows.tenantId,
      status: AppState.workflows.status,
      search: AppState.workflows.search
    });
    
    tbody.innerHTML = '';
    
    if (result.data.length === 0) {
      Empty.show(tbody, '暂无工作�?);
      return;
    }
    
    result.data.forEach(workflow => {
      tbody.appendChild(Table.renderWorkflowRow(workflow));
    });
    
    // 分页
    Pagination.render('#workflowsPagination', {
      page: result.page,
      totalPages: result.totalPages,
      onChange: (page) => {
        AppState.workflows.page = page;
        loadWorkflows();
      }
    });
  } catch (e) {
    console.error('Load workflows failed:', e);
    Toast.error('加载工作流列表失�?);
  }
}

async function cancelWorkflow(workflow) {
  Modal.confirm({
    title: '取消工作�?,
    message: `确定要取消工作流 "${workflow.id}" 吗？`,
    confirmText: '取消执行',
    onConfirm: async () => {
      try {
        await API.cancelWorkflow(workflow.id);
        Toast.success('工作流已取消');
        loadWorkflows();
      } catch (e) {
        Toast.error(e.message || '操作失败');
      }
    }
  });
}

// ============================================================================
// 系统设置
// ============================================================================

async function loadSettings() {
  try {
    const settings = await API.getSettings();
    
    DOM.$('#settingSystemName').value = settings.systemName;
    DOM.$('#settingTimezone').value = settings.timezone;
    DOM.$('#settingQuotaAlertThreshold').value = settings.quotaAlertThreshold;
    DOM.$('#settingEmailAlerts').checked = settings.emailAlerts;
    DOM.$('#settingAlertEmail').value = settings.alertEmail;
    DOM.$('#settingEventRetention').value = settings.eventRetention;
    DOM.$('#settingSnapshotRetention').value = settings.snapshotRetention;
  } catch (e) {
    console.error('Load settings failed:', e);
  }
}

async function saveSettings() {
  const settings = {
    systemName: DOM.$('#settingSystemName').value,
    timezone: DOM.$('#settingTimezone').value,
    quotaAlertThreshold: parseInt(DOM.$('#settingQuotaAlertThreshold').value) || 80,
    emailAlerts: DOM.$('#settingEmailAlerts').checked,
    alertEmail: DOM.$('#settingAlertEmail').value,
    eventRetention: parseInt(DOM.$('#settingEventRetention').value) || 90,
    snapshotRetention: parseInt(DOM.$('#settingSnapshotRetention').value) || 30
  };
  
  try {
    await API.saveSettings(settings);
    Toast.success('设置已保�?);
  } catch (e) {
    Toast.error('保存失败');
  }
}

// ============================================================================
// 事件绑定
// ============================================================================

function bindEvents() {
  // 导航点击
  DOM.$$('.nav-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      ViewManager.switchTo(item.dataset.view);
    });
  });
  
  // 侧边栏折�?
  DOM.$('#sidebarToggle')?.addEventListener('click', () => {
    DOM.$('#sidebar').classList.toggle('collapsed');
  });
  
  // 刷新按钮
  DOM.$('#refreshBtn')?.addEventListener('click', () => {
    ViewManager.views[AppState.currentView]?.load();
  });
  
  // 仪表�?- 流程趋势范围
  DOM.$('#flowTrendRange')?.addEventListener('change', loadFlowTrendChart);
  
  // 租户管理
  DOM.$('#createTenantBtn')?.addEventListener('click', () => openTenantModal());
  DOM.$('#saveTenantBtn')?.addEventListener('click', saveTenant);
  DOM.$('#cancelTenantBtn')?.addEventListener('click', () => Modal.close());
  DOM.$('#closeTenantModal')?.addEventListener('click', () => Modal.close());
  
  DOM.$('#tenantStatusFilter')?.addEventListener('change', (e) => {
    AppState.tenants.status = e.target.value;
    AppState.tenants.page = 1;
    loadTenants();
  });
  
  DOM.$('#tenantPlanFilter')?.addEventListener('change', (e) => {
    AppState.tenants.plan = e.target.value;
    AppState.tenants.page = 1;
    loadTenants();
  });
  
  // 配额管理 - Tab 切换
  DOM.$$('.tabs .tab').forEach(tab => {
    tab.addEventListener('click', () => {
      DOM.$$('.tabs .tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      AppState.quotas.currentPlan = tab.dataset.plan;
      loadQuotas();
    });
  });
  
  DOM.$('#saveQuotaBtn')?.addEventListener('click', saveQuota);
  DOM.$('#resetQuotaBtn')?.addEventListener('click', loadQuotas);
  
  // 用量统计
  DOM.$('#usageTenantSelect')?.addEventListener('change', (e) => {
    AppState.usage.tenantId = e.target.value;
    loadUsage();
  });
  
  DOM.$('#usageTimeRange')?.addEventListener('change', (e) => {
    AppState.usage.range = e.target.value;
    loadUsage();
  });
  
  DOM.$('#exportUsageBtn')?.addEventListener('click', () => {
    Toast.info('导出功能开发中...');
  });
  
  // 工作�?
  DOM.$('#workflowTenantSelect')?.addEventListener('change', (e) => {
    AppState.workflows.tenantId = e.target.value;
    AppState.workflows.page = 1;
    loadWorkflows();
  });
  
  DOM.$('#workflowStatusFilter')?.addEventListener('change', (e) => {
    AppState.workflows.status = e.target.value;
    AppState.workflows.page = 1;
    loadWorkflows();
  });
  
  DOM.$('#workflowSearch')?.addEventListener('input', debounce((e) => {
    AppState.workflows.search = e.target.value;
    AppState.workflows.page = 1;
    loadWorkflows();
  }, 500));
  
  // 设置
  DOM.$('#saveSettingsBtn')?.addEventListener('click', saveSettings);
  
  // 事件总线
  eventBus.on('tenant:edit', openTenantModal);
  eventBus.on('tenant:delete', deleteTenant);
  eventBus.on('tenant:suspend', suspendTenant);
  eventBus.on('tenant:activate', activateTenant);
  eventBus.on('workflow:cancel', cancelWorkflow);
  eventBus.on('workflow:view', (workflow) => {
    Toast.info(`查看工作�?${workflow.id} (功能开发中)`);
  });
  
  // 全局搜索
  DOM.$('#globalSearch')?.addEventListener('input', debounce((e) => {
    const query = e.target.value.trim();
    if (query) {
      Toast.info(`搜索功能开发中: ${query}`);
    }
  }, 500));
  
  // 链接导航
  DOM.$$('[data-view]').forEach(link => {
    if (link.tagName === 'A') {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        ViewManager.switchTo(link.dataset.view);
      });
    }
  });
}

// ============================================================================
// 初始�?
// ============================================================================

async function init() {
  console.log('UniFlow Tenant Console initializing...');
  
  // 初始化组�?
  Toast.init();
  
  // 绑定事件
  bindEvents();
  
  // 加载初始视图
  ViewManager.switchTo('dashboard');
  
  console.log('UniFlow Tenant Console ready.');
}

// 启动
document.addEventListener('DOMContentLoaded', init);
