/**
 * UniFlow 租户控制�?- UI 组件
 */

// ============================================================================
// Toast 通知
// ============================================================================

const Toast = {
  container: null,
  
  init() {
    this.container = DOM.$('#toastContainer');
  },
  
  show(message, type = 'info', duration = 3000) {
    const icons = {
      success: '�?,
      error: '�?,
      warning: '�?,
      info: '�?
    };
    
    const toast = DOM.create('div', { className: `toast ${type}` }, [
      DOM.create('span', { className: 'toast-icon' }, [icons[type] || icons.info]),
      DOM.create('span', { className: 'toast-message' }, [message]),
      DOM.create('button', { 
        className: 'toast-close',
        onClick: () => this.dismiss(toast)
      }, ['×'])
    ]);
    
    this.container.appendChild(toast);
    
    if (duration > 0) {
      setTimeout(() => this.dismiss(toast), duration);
    }
    
    return toast;
  },
  
  dismiss(toast) {
    toast.style.animation = 'slideIn 0.3s ease reverse';
    setTimeout(() => toast.remove(), 300);
  },
  
  success(message, duration) {
    return this.show(message, 'success', duration);
  },
  
  error(message, duration) {
    return this.show(message, 'error', duration);
  },
  
  warning(message, duration) {
    return this.show(message, 'warning', duration);
  },
  
  info(message, duration) {
    return this.show(message, 'info', duration);
  }
};

// ============================================================================
// Modal 模态框
// ============================================================================

const Modal = {
  current: null,
  
  open(modalId) {
    const modal = DOM.$(`#${modalId}`);
    if (modal) {
      modal.classList.add('show');
      this.current = modal;
      
      // 点击背景关闭
      const backdrop = modal.querySelector('.modal-backdrop');
      backdrop?.addEventListener('click', () => this.close());
    }
  },
  
  close() {
    if (this.current) {
      this.current.classList.remove('show');
      this.current = null;
    }
  },
  
  confirm(options = {}) {
    const {
      title = '确认操作',
      message = '确定要执行此操作吗？',
      confirmText = '确认',
      cancelText = '取消',
      onConfirm = () => {},
      onCancel = () => {}
    } = options;
    
    DOM.$('#confirmModalTitle').textContent = title;
    DOM.$('#confirmModalMessage').textContent = message;
    DOM.$('#confirmOkBtn').textContent = confirmText;
    DOM.$('#confirmCancelBtn').textContent = cancelText;
    
    const handleConfirm = () => {
      cleanup();
      this.close();
      onConfirm();
    };
    
    const handleCancel = () => {
      cleanup();
      this.close();
      onCancel();
    };
    
    const cleanup = () => {
      DOM.$('#confirmOkBtn').removeEventListener('click', handleConfirm);
      DOM.$('#confirmCancelBtn').removeEventListener('click', handleCancel);
      DOM.$('#closeConfirmModal').removeEventListener('click', handleCancel);
    };
    
    DOM.$('#confirmOkBtn').addEventListener('click', handleConfirm);
    DOM.$('#confirmCancelBtn').addEventListener('click', handleCancel);
    DOM.$('#closeConfirmModal').addEventListener('click', handleCancel);
    
    this.open('confirmModal');
  }
};

// ============================================================================
// Pagination 分页
// ============================================================================

const Pagination = {
  render(container, options) {
    const {
      page = 1,
      totalPages = 1,
      onChange = () => {}
    } = options;
    
    if (typeof container === 'string') {
      container = DOM.$(container);
    }
    
    container.innerHTML = '';
    
    if (totalPages <= 1) return;
    
    // 上一�?
    const prevBtn = DOM.create('button', {
      disabled: page <= 1,
      onClick: () => onChange(page - 1)
    }, ['�?]);
    container.appendChild(prevBtn);
    
    // 页码
    const range = this.getPageRange(page, totalPages);
    range.forEach(p => {
      if (p === '...') {
        container.appendChild(DOM.create('span', { className: 'pagination-ellipsis' }, ['...']));
      } else {
        const btn = DOM.create('button', {
          className: p === page ? 'active' : '',
          onClick: () => p !== page && onChange(p)
        }, [String(p)]);
        container.appendChild(btn);
      }
    });
    
    // 下一�?
    const nextBtn = DOM.create('button', {
      disabled: page >= totalPages,
      onClick: () => onChange(page + 1)
    }, ['�?]);
    container.appendChild(nextBtn);
  },
  
  getPageRange(current, total) {
    if (total <= 7) {
      return Array.from({ length: total }, (_, i) => i + 1);
    }
    
    const range = [];
    
    if (current <= 4) {
      range.push(1, 2, 3, 4, 5, '...', total);
    } else if (current >= total - 3) {
      range.push(1, '...', total - 4, total - 3, total - 2, total - 1, total);
    } else {
      range.push(1, '...', current - 1, current, current + 1, '...', total);
    }
    
    return range;
  }
};

// ============================================================================
// Table 表格渲染
// ============================================================================

const Table = {
  renderTenantRow(tenant) {
    const statusConfig = getStatusConfig('tenant', tenant.status);
    const planConfig = getStatusConfig('plan', tenant.plan);
    
    const storagePercent = tenant.quota.maxStorageMB > 0
      ? Math.round((tenant.usage.storageUsedMB / tenant.quota.maxStorageMB) * 100)
      : 0;
    
    return DOM.create('tr', { dataset: { id: tenant.id } }, [
      DOM.create('td', {}, [
        DOM.create('input', { type: 'checkbox', className: 'tenant-checkbox' })
      ]),
      DOM.create('td', {}, [
        DOM.create('div', {}, [
          DOM.create('strong', {}, [tenant.displayName]),
          DOM.create('div', { className: 'text-muted', style: { fontSize: '12px' } }, [tenant.name])
        ])
      ]),
      DOM.create('td', {}, [
        DOM.create('span', { className: `badge badge-${planConfig.badge}` }, [planConfig.label])
      ]),
      DOM.create('td', {}, [
        DOM.create('span', { className: `badge badge-${statusConfig.badge}` }, [statusConfig.label])
      ]),
      DOM.create('td', {}, [String(tenant.usage.activeFlows)]),
      DOM.create('td', {}, [
        DOM.create('div', { style: { minWidth: '100px' } }, [
          DOM.create('div', { className: 'progress', style: { marginBottom: '4px' } }, [
            DOM.create('div', { 
              className: `progress-bar ${storagePercent > 80 ? 'danger' : storagePercent > 60 ? 'warning' : 'success'}`,
              style: { width: `${storagePercent}%` }
            })
          ]),
          DOM.create('span', { className: 'text-muted', style: { fontSize: '11px' } }, [
            `${tenant.usage.storageUsedMB} / ${tenant.quota.maxStorageMB || '�?} MB`
          ])
        ])
      ]),
      DOM.create('td', {}, [DateUtils.format(tenant.createdAt, 'YYYY-MM-DD')]),
      DOM.create('td', {}, [
        DOM.create('div', { className: 'actions' }, [
          DOM.create('button', { 
            className: 'action-btn', 
            title: '编辑',
            onClick: () => eventBus.emit('tenant:edit', tenant)
          }, ['✏️']),
          tenant.status === 'active'
            ? DOM.create('button', { 
                className: 'action-btn', 
                title: '暂停',
                onClick: () => eventBus.emit('tenant:suspend', tenant)
              }, ['�?])
            : DOM.create('button', { 
                className: 'action-btn', 
                title: '激�?,
                onClick: () => eventBus.emit('tenant:activate', tenant)
              }, ['�?]),
          DOM.create('button', { 
            className: 'action-btn danger', 
            title: '删除',
            onClick: () => eventBus.emit('tenant:delete', tenant)
          }, ['🗑'])
        ])
      ])
    ]);
  },
  
  renderWorkflowRow(workflow) {
    const statusConfig = getStatusConfig('workflow', workflow.status);
    
    return DOM.create('tr', { dataset: { id: workflow.id } }, [
      DOM.create('td', {}, [
        DOM.create('span', { style: { fontFamily: 'monospace', fontSize: '12px' } }, [workflow.id])
      ]),
      DOM.create('td', {}, [workflow.tenantName]),
      DOM.create('td', {}, [workflow.type]),
      DOM.create('td', {}, [
        DOM.create('span', { className: `badge badge-${statusConfig.badge}` }, [statusConfig.label])
      ]),
      DOM.create('td', {}, [
        workflow.status === 'running'
          ? `${workflow.completedSteps || 0}/${workflow.totalSteps}`
          : `${workflow.totalSteps}`
      ]),
      DOM.create('td', {}, [DateUtils.format(workflow.startedAt, 'MM-DD HH:mm:ss')]),
      DOM.create('td', {}, [
        workflow.duration ? DateUtils.duration(workflow.duration) : '-'
      ]),
      DOM.create('td', {}, [
        DOM.create('div', { className: 'actions' }, [
          DOM.create('button', { 
            className: 'action-btn', 
            title: '查看详情',
            onClick: () => eventBus.emit('workflow:view', workflow)
          }, ['👁']),
          workflow.status === 'running'
            ? DOM.create('button', { 
                className: 'action-btn danger', 
                title: '取消',
                onClick: () => eventBus.emit('workflow:cancel', workflow)
              }, ['�?])
            : null
        ].filter(Boolean))
      ])
    ]);
  },
  
  renderActivityRow(activity) {
    return DOM.create('tr', {}, [
      DOM.create('td', {}, [activity.tenantName]),
      DOM.create('td', {}, [activity.event]),
      DOM.create('td', {}, [DateUtils.relative(activity.timestamp)]),
      DOM.create('td', {}, [
        DOM.create('span', { 
          className: `badge badge-${activity.status === 'error' ? 'danger' : 'success'}` 
        }, [activity.status === 'error' ? '失败' : '成功'])
      ])
    ]);
  },
  
  renderUsageRankingRow(item) {
    return DOM.create('tr', {}, [
      DOM.create('td', {}, [
        DOM.create('span', { 
          className: `badge ${item.rank <= 3 ? 'badge-warning' : 'badge-muted'}` 
        }, [String(item.rank)])
      ]),
      DOM.create('td', {}, [item.tenantName]),
      DOM.create('td', {}, [NumberUtils.compact(item.flows)]),
      DOM.create('td', {}, [NumberUtils.compact(item.apiCalls)]),
      DOM.create('td', {}, [NumberUtils.compact(item.tokens)]),
      DOM.create('td', {}, [`${item.storage} MB`]),
      DOM.create('td', {}, [
        DOM.create('div', { style: { minWidth: '80px' } }, [
          DOM.create('div', { className: 'progress' }, [
            DOM.create('div', { 
              className: `progress-bar ${item.quotaUsage > 80 ? 'danger' : item.quotaUsage > 60 ? 'warning' : 'success'}`,
              style: { width: `${item.quotaUsage}%` }
            })
          ]),
          DOM.create('span', { className: 'text-muted', style: { fontSize: '11px' } }, [`${item.quotaUsage}%`])
        ])
      ])
    ]);
  }
};

// ============================================================================
// Loading 加载状�?
// ============================================================================

const Loading = {
  show(container, message = '加载�?..') {
    if (typeof container === 'string') {
      container = DOM.$(container);
    }
    
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">�?/div>
        <div class="empty-state-text">${message}</div>
      </div>
    `;
  },
  
  hide(container) {
    if (typeof container === 'string') {
      container = DOM.$(container);
    }
    container.innerHTML = '';
  }
};

// ============================================================================
// Empty 空状�?
// ============================================================================

const Empty = {
  show(container, message = '暂无数据', icon = '📭') {
    if (typeof container === 'string') {
      container = DOM.$(container);
    }
    
    container.innerHTML = `
      <tr>
        <td colspan="100">
          <div class="empty-state">
            <div class="empty-state-icon">${icon}</div>
            <div class="empty-state-text">${message}</div>
          </div>
        </td>
      </tr>
    `;
  }
};

// ============================================================================
// Form 表单工具
// ============================================================================

const Form = {
  getData(formId) {
    const form = DOM.$(`#${formId}`);
    const data = {};
    
    form.querySelectorAll('input, select, textarea').forEach(el => {
      if (el.id) {
        const key = el.id.replace(formId.replace('Form', ''), '').toLowerCase();
        if (key) {
          if (el.type === 'checkbox') {
            data[key] = el.checked;
          } else if (el.type === 'number') {
            data[key] = el.value ? Number(el.value) : 0;
          } else {
            data[key] = el.value;
          }
        }
      }
    });
    
    return data;
  },
  
  setData(formId, data) {
    const form = DOM.$(`#${formId}`);
    
    Object.entries(data).forEach(([key, value]) => {
      const el = form.querySelector(`#${formId.replace('Form', '')}${key.charAt(0).toUpperCase() + key.slice(1)}`);
      if (el) {
        if (el.type === 'checkbox') {
          el.checked = value;
        } else {
          el.value = value;
        }
      }
    });
  },
  
  reset(formId) {
    const form = DOM.$(`#${formId}`);
    form?.reset();
  },
  
  validate(formId, rules = {}) {
    const data = this.getData(formId);
    const errors = [];
    
    Object.entries(rules).forEach(([field, fieldRules]) => {
      const value = data[field];
      
      fieldRules.forEach(rule => {
        if (rule.required && !Validators.required(value)) {
          errors.push({ field, message: rule.message || `${field} 不能为空` });
        }
        if (rule.email && value && !Validators.email(value)) {
          errors.push({ field, message: rule.message || `${field} 格式不正确` });
        }
        if (rule.pattern && value && !rule.pattern.test(value)) {
          errors.push({ field, message: rule.message || `${field} 格式不正确` });
        }
        if (rule.min !== undefined && Number(value) < rule.min) {
          errors.push({ field, message: rule.message || `${field} 不能小于 ${rule.min}` });
        }
        if (rule.max !== undefined && Number(value) > rule.max) {
          errors.push({ field, message: rule.message || `${field} 不能大于 ${rule.max}` });
        }
      });
    });
    
    return {
      valid: errors.length === 0,
      errors
    };
  }
};

// ============================================================================
// Dropdown 下拉选择
// ============================================================================

const Dropdown = {
  populateTenantSelect(selectId, tenants, includeAll = true) {
    const select = DOM.$(`#${selectId}`);
    if (!select) return;
    
    select.innerHTML = '';
    
    if (includeAll) {
      select.appendChild(DOM.create('option', { value: '' }, ['全部租户']));
    }
    
    tenants.forEach(t => {
      select.appendChild(DOM.create('option', { value: t.id }, [t.displayName]));
    });
  }
};

// ============================================================================
// 导出
// ============================================================================

window.Toast = Toast;
window.Modal = Modal;
window.Pagination = Pagination;
window.Table = Table;
window.Loading = Loading;
window.Empty = Empty;
window.Form = Form;
window.Dropdown = Dropdown;
