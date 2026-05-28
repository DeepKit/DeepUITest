/**
 * UniFlow 租户控制�?- API 客户�?
 * 
 * 注意：这是一�?Demo 实现，使用模拟数据�?
 * 实际使用时需要连接到后端 API�?
 */

// ============================================================================
// API 配置
// ============================================================================

const API_CONFIG = {
  baseUrl: '/api/v1',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json'
  }
};

// ============================================================================
// Demo 数据生成
// ============================================================================

const DemoData = {
  /**
   * 生成租户列表
   */
  generateTenants(count = 10) {
    const plans = ['free', 'basic', 'professional', 'enterprise'];
    const statuses = ['active', 'active', 'active', 'suspended', 'archived'];
    
    const tenants = [];
    for (let i = 1; i <= count; i++) {
      const plan = plans[Math.floor(Math.random() * plans.length)];
      const status = statuses[Math.floor(Math.random() * statuses.length)];
      
      tenants.push({
        id: `tenant_${String(i).padStart(3, '0')}`,
        name: `tenant_${i}`,
        displayName: `租户 ${i}`,
        status,
        plan,
        quota: this.getQuotaByPlan(plan),
        usage: {
          activeFlows: Math.floor(Math.random() * 50),
          flowsToday: Math.floor(Math.random() * 100),
          totalFlows: Math.floor(Math.random() * 5000),
          storageUsedMB: Math.floor(Math.random() * 500),
          totalEvents: Math.floor(Math.random() * 50000),
          totalSnapshots: Math.floor(Math.random() * 1000),
          requestsThisMinute: Math.floor(Math.random() * 50),
          requestsToday: Math.floor(Math.random() * 5000),
          llmRequestsToday: Math.floor(Math.random() * 200),
          tokensToday: Math.floor(Math.random() * 100000)
        },
        createdAt: new Date(Date.now() - Math.random() * 90 * 24 * 60 * 60 * 1000).toISOString(),
        updatedAt: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000).toISOString(),
        ownerEmail: `admin${i}@example.com`,
        contactEmail: `contact${i}@example.com`
      });
    }
    return tenants;
  },
  
  /**
   * 获取计划配额
   */
  getQuotaByPlan(plan) {
    const quotas = {
      free: {
        maxActiveFlows: 5,
        maxFlowsPerDay: 20,
        maxEventsPerFlow: 100,
        maxStorageMB: 100,
        maxSnapshotsPerFlow: 5,
        maxRequestsPerMinute: 10,
        maxRequestsPerDay: 1000,
        maxLLMRequestsPerDay: 50,
        maxTokensPerDay: 10000,
        allowParallelExecution: false,
        allowSubworkflows: false,
        allowCustomSkills: false
      },
      basic: {
        maxActiveFlows: 20,
        maxFlowsPerDay: 100,
        maxEventsPerFlow: 500,
        maxStorageMB: 500,
        maxSnapshotsPerFlow: 10,
        maxRequestsPerMinute: 30,
        maxRequestsPerDay: 5000,
        maxLLMRequestsPerDay: 200,
        maxTokensPerDay: 50000,
        allowParallelExecution: true,
        allowSubworkflows: false,
        allowCustomSkills: false
      },
      professional: {
        maxActiveFlows: 100,
        maxFlowsPerDay: 500,
        maxEventsPerFlow: 2000,
        maxStorageMB: 2000,
        maxSnapshotsPerFlow: 50,
        maxRequestsPerMinute: 100,
        maxRequestsPerDay: 20000,
        maxLLMRequestsPerDay: 1000,
        maxTokensPerDay: 500000,
        allowParallelExecution: true,
        allowSubworkflows: true,
        allowCustomSkills: false
      },
      enterprise: {
        maxActiveFlows: 0,
        maxFlowsPerDay: 0,
        maxEventsPerFlow: 0,
        maxStorageMB: 0,
        maxSnapshotsPerFlow: 0,
        maxRequestsPerMinute: 0,
        maxRequestsPerDay: 0,
        maxLLMRequestsPerDay: 0,
        maxTokensPerDay: 0,
        allowParallelExecution: true,
        allowSubworkflows: true,
        allowCustomSkills: true
      }
    };
    return quotas[plan] || quotas.free;
  },
  
  /**
   * 生成工作流列�?
   */
  generateWorkflows(count = 20) {
    const types = ['Build', 'Maintain', 'NlConvert', 'SceneChange', 'CodeChange'];
    const statuses = ['running', 'succeeded', 'succeeded', 'succeeded', 'failed', 'cancelled'];
    const tenants = this.generateTenants(5);
    
    const workflows = [];
    for (let i = 1; i <= count; i++) {
      const tenant = tenants[Math.floor(Math.random() * tenants.length)];
      const status = statuses[Math.floor(Math.random() * statuses.length)];
      const startTime = new Date(Date.now() - Math.random() * 24 * 60 * 60 * 1000);
      const duration = status === 'running' ? null : Math.floor(Math.random() * 60000);
      
      workflows.push({
        id: `flow_${String(i).padStart(6, '0')}`,
        tenantId: tenant.id,
        tenantName: tenant.displayName,
        type: types[Math.floor(Math.random() * types.length)],
        status,
        currentStep: status === 'running' ? `Step ${Math.floor(Math.random() * 5) + 1}` : null,
        totalSteps: Math.floor(Math.random() * 10) + 3,
        completedSteps: status === 'running' ? Math.floor(Math.random() * 5) : null,
        startedAt: startTime.toISOString(),
        completedAt: status === 'running' ? null : new Date(startTime.getTime() + duration).toISOString(),
        duration,
        errorMessage: status === 'failed' ? '执行步骤超时' : null
      });
    }
    return workflows;
  },
  
  /**
   * 生成趋势数据
   */
  generateTrendData(days = 7) {
    const data = [];
    const now = new Date();
    
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date(now);
      date.setDate(date.getDate() - i);
      
      data.push({
        date: date.toISOString().split('T')[0],
        label: `${date.getMonth() + 1}/${date.getDate()}`,
        flows: Math.floor(Math.random() * 500) + 100,
        apiCalls: Math.floor(Math.random() * 5000) + 1000,
        tokens: Math.floor(Math.random() * 100000) + 20000
      });
    }
    return data;
  },
  
  /**
   * 生成最近活�?
   */
  generateRecentActivity(count = 10) {
    const events = [
      '创建了新流程',
      '流程执行完成',
      '流程执行失败',
      '更新了配�?,
      '配额超限告警',
      '新用户注�?
    ];
    const tenants = this.generateTenants(5);
    
    const activities = [];
    for (let i = 0; i < count; i++) {
      const tenant = tenants[Math.floor(Math.random() * tenants.length)];
      const event = events[Math.floor(Math.random() * events.length)];
      const isError = event.includes('失败') || event.includes('告警');
      
      activities.push({
        id: uuid(),
        tenantId: tenant.id,
        tenantName: tenant.displayName,
        event,
        timestamp: new Date(Date.now() - Math.random() * 60 * 60 * 1000).toISOString(),
        status: isError ? 'error' : 'success'
      });
    }
    return activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  }
};

// ============================================================================
// 模拟数据存储
// ============================================================================

let mockTenants = DemoData.generateTenants(15);
let mockWorkflows = DemoData.generateWorkflows(30);

// ============================================================================
// API 客户�?
// ============================================================================

const API = {
  /**
   * 模拟 API 延迟
   */
  async delay(ms = 300) {
    return new Promise(resolve => setTimeout(resolve, ms));
  },
  
  // --------------------------------------------------------------------------
  // 仪表�?
  // --------------------------------------------------------------------------
  
  /**
   * 获取仪表板概�?
   */
  async getDashboardOverview() {
    await this.delay(200);
    
    const activeTenants = mockTenants.filter(t => t.status === 'active').length;
    const todayFlows = mockWorkflows.filter(w => {
      const d = new Date(w.startedAt);
      const today = new Date();
      return d.toDateString() === today.toDateString();
    }).length;
    const apiCalls = mockTenants.reduce((sum, t) => sum + t.usage.requestsToday, 0);
    const quotaAlerts = mockTenants.filter(t => {
      if (t.quota.maxStorageMB === 0) return false;
      return (t.usage.storageUsedMB / t.quota.maxStorageMB) > 0.8;
    }).length;
    
    return {
      activeTenants,
      todayFlows,
      apiCalls,
      quotaAlerts
    };
  },
  
  /**
   * 获取租户分布
   */
  async getTenantDistribution() {
    await this.delay(100);
    
    const planCounts = {};
    mockTenants.forEach(t => {
      planCounts[t.plan] = (planCounts[t.plan] || 0) + 1;
    });
    
    return Object.entries(planCounts).map(([plan, count]) => ({
      label: getStatusConfig('plan', plan).label,
      value: count
    }));
  },
  
  /**
   * 获取流程趋势
   */
  async getFlowTrend(range = '7d') {
    await this.delay(100);
    
    const days = range === '7d' ? 7 : range === '30d' ? 30 : 90;
    return DemoData.generateTrendData(days);
  },
  
  /**
   * 获取最近活�?
   */
  async getRecentActivity(limit = 10) {
    await this.delay(100);
    return DemoData.generateRecentActivity(limit);
  },
  
  // --------------------------------------------------------------------------
  // 租户管理
  // --------------------------------------------------------------------------
  
  /**
   * 获取租户列表
   */
  async getTenants(params = {}) {
    await this.delay(300);
    
    let tenants = [...mockTenants];
    
    // 状态过�?
    if (params.status) {
      tenants = tenants.filter(t => t.status === params.status);
    }
    
    // 计划过滤
    if (params.plan) {
      tenants = tenants.filter(t => t.plan === params.plan);
    }
    
    // 搜索
    if (params.search) {
      const search = params.search.toLowerCase();
      tenants = tenants.filter(t => 
        t.name.toLowerCase().includes(search) ||
        t.displayName.toLowerCase().includes(search)
      );
    }
    
    // 分页
    const page = params.page || 1;
    const pageSize = params.pageSize || 10;
    const total = tenants.length;
    const start = (page - 1) * pageSize;
    const data = tenants.slice(start, start + pageSize);
    
    return {
      data,
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize)
    };
  },
  
  /**
   * 获取单个租户
   */
  async getTenant(id) {
    await this.delay(100);
    return mockTenants.find(t => t.id === id);
  },
  
  /**
   * 创建租户
   */
  async createTenant(data) {
    await this.delay(500);
    
    const tenant = {
      id: `tenant_${String(mockTenants.length + 1).padStart(3, '0')}`,
      name: data.name,
      displayName: data.displayName,
      status: 'active',
      plan: data.plan || 'free',
      quota: DemoData.getQuotaByPlan(data.plan || 'free'),
      usage: {
        activeFlows: 0,
        flowsToday: 0,
        totalFlows: 0,
        storageUsedMB: 0,
        totalEvents: 0,
        totalSnapshots: 0,
        requestsThisMinute: 0,
        requestsToday: 0,
        llmRequestsToday: 0,
        tokensToday: 0
      },
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      ownerEmail: data.ownerEmail || '',
      contactEmail: data.contactEmail || ''
    };
    
    mockTenants.unshift(tenant);
    return tenant;
  },
  
  /**
   * 更新租户
   */
  async updateTenant(id, data) {
    await this.delay(300);
    
    const index = mockTenants.findIndex(t => t.id === id);
    if (index === -1) {
      throw new Error('租户不存�?);
    }
    
    mockTenants[index] = {
      ...mockTenants[index],
      ...data,
      updatedAt: new Date().toISOString()
    };
    
    return mockTenants[index];
  },
  
  /**
   * 删除租户
   */
  async deleteTenant(id) {
    await this.delay(300);
    
    const index = mockTenants.findIndex(t => t.id === id);
    if (index === -1) {
      throw new Error('租户不存�?);
    }
    
    mockTenants.splice(index, 1);
    return true;
  },
  
  /**
   * 暂停租户
   */
  async suspendTenant(id) {
    return this.updateTenant(id, { status: 'suspended' });
  },
  
  /**
   * 激活租�?
   */
  async activateTenant(id) {
    return this.updateTenant(id, { status: 'active' });
  },
  
  /**
   * 更改租户计划
   */
  async changeTenantPlan(id, plan) {
    return this.updateTenant(id, { 
      plan, 
      quota: DemoData.getQuotaByPlan(plan) 
    });
  },
  
  // --------------------------------------------------------------------------
  // 配额管理
  // --------------------------------------------------------------------------
  
  /**
   * 获取计划配额
   */
  async getPlanQuota(plan) {
    await this.delay(100);
    return DemoData.getQuotaByPlan(plan);
  },
  
  /**
   * 更新计划配额
   */
  async updatePlanQuota(plan, quota) {
    await this.delay(300);
    // 在实际实现中，这会更新数据库中的配额配置
    console.log('Update quota for plan:', plan, quota);
    return quota;
  },
  
  // --------------------------------------------------------------------------
  // 用量统计
  // --------------------------------------------------------------------------
  
  /**
   * 获取用量概览
   */
  async getUsageOverview(params = {}) {
    await this.delay(200);
    
    let tenants = mockTenants;
    if (params.tenantId) {
      tenants = tenants.filter(t => t.id === params.tenantId);
    }
    
    return {
      totalFlows: tenants.reduce((sum, t) => sum + t.usage.totalFlows, 0),
      totalAPI: tenants.reduce((sum, t) => sum + t.usage.requestsToday, 0),
      totalTokens: tenants.reduce((sum, t) => sum + t.usage.tokensToday, 0),
      totalStorage: tenants.reduce((sum, t) => sum + t.usage.storageUsedMB, 0),
      trends: {
        flows: Math.floor(Math.random() * 30) - 10,
        api: Math.floor(Math.random() * 20) - 5,
        tokens: Math.floor(Math.random() * 15) - 10,
        storage: Math.floor(Math.random() * 10)
      }
    };
  },
  
  /**
   * 获取用量趋势
   */
  async getUsageTrend(params = {}) {
    await this.delay(200);
    
    const days = params.range === 'today' ? 1 : 
                 params.range === '7d' ? 7 : 
                 params.range === '90d' ? 90 : 30;
    return DemoData.generateTrendData(days);
  },
  
  /**
   * 获取用量排行
   */
  async getUsageRanking(params = {}) {
    await this.delay(200);
    
    return mockTenants
      .filter(t => t.status === 'active')
      .sort((a, b) => b.usage.totalFlows - a.usage.totalFlows)
      .slice(0, params.limit || 10)
      .map((t, i) => ({
        rank: i + 1,
        tenantId: t.id,
        tenantName: t.displayName,
        flows: t.usage.totalFlows,
        apiCalls: t.usage.requestsToday,
        tokens: t.usage.tokensToday,
        storage: t.usage.storageUsedMB,
        quotaUsage: t.quota.maxStorageMB > 0 
          ? Math.round((t.usage.storageUsedMB / t.quota.maxStorageMB) * 100)
          : 0
      }));
  },
  
  // --------------------------------------------------------------------------
  // 工作�?
  // --------------------------------------------------------------------------
  
  /**
   * 获取工作流列�?
   */
  async getWorkflows(params = {}) {
    await this.delay(300);
    
    let workflows = [...mockWorkflows];
    
    // 租户过滤
    if (params.tenantId) {
      workflows = workflows.filter(w => w.tenantId === params.tenantId);
    }
    
    // 状态过�?
    if (params.status) {
      workflows = workflows.filter(w => w.status === params.status);
    }
    
    // 搜索
    if (params.search) {
      const search = params.search.toLowerCase();
      workflows = workflows.filter(w => 
        w.id.toLowerCase().includes(search) ||
        w.tenantName.toLowerCase().includes(search)
      );
    }
    
    // 排序
    workflows.sort((a, b) => new Date(b.startedAt) - new Date(a.startedAt));
    
    // 分页
    const page = params.page || 1;
    const pageSize = params.pageSize || 10;
    const total = workflows.length;
    const start = (page - 1) * pageSize;
    const data = workflows.slice(start, start + pageSize);
    
    return {
      data,
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize)
    };
  },
  
  /**
   * 获取单个工作�?
   */
  async getWorkflow(id) {
    await this.delay(100);
    return mockWorkflows.find(w => w.id === id);
  },
  
  /**
   * 取消工作�?
   */
  async cancelWorkflow(id) {
    await this.delay(300);
    
    const workflow = mockWorkflows.find(w => w.id === id);
    if (workflow && workflow.status === 'running') {
      workflow.status = 'cancelled';
      workflow.completedAt = new Date().toISOString();
    }
    return workflow;
  },
  
  // --------------------------------------------------------------------------
  // 系统设置
  // --------------------------------------------------------------------------
  
  /**
   * 获取系统设置
   */
  async getSettings() {
    await this.delay(100);
    
    return Storage.get('settings', {
      systemName: 'UniFlow',
      timezone: 'Asia/Shanghai',
      quotaAlertThreshold: 80,
      emailAlerts: true,
      alertEmail: '',
      eventRetention: 90,
      snapshotRetention: 30
    });
  },
  
  /**
   * 保存系统设置
   */
  async saveSettings(settings) {
    await this.delay(300);
    Storage.set('settings', settings);
    return settings;
  }
};

// ============================================================================
// 导出
// ============================================================================

window.API = API;
window.DemoData = DemoData;
