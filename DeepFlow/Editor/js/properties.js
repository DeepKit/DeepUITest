/**
 * UniFlow Workflow Editor - Properties Panel
 */

class PropertiesPanel {
  constructor(container) {
    this.container = container;
    this.contentEl = container.querySelector('.properties-content');
    this.titleEl = container.querySelector('.properties-title');
    this.currentNode = null;
    this.onChange = null;
    
    this.init();
  }

  init() {
    this.showEmpty();
  }

  showEmpty() {
    this.currentNode = null;
    this.titleEl.textContent = '属�?;
    this.contentEl.innerHTML = `
      <div class="properties-empty">
        <span class="properties-empty-icon">📋</span>
        <span>选择节点以查看属�?/span>
      </div>
    `;
  }

  showNode(node) {
    this.currentNode = node;
    const nodeType = NodeTypes[node.type];
    
    this.titleEl.textContent = nodeType.label + ' 属�?;
    this.contentEl.innerHTML = '';
    
    // Render each property
    nodeType.properties.forEach(propDef => {
      const group = this.createPropertyGroup(propDef, node.properties[propDef.name]);
      this.contentEl.appendChild(group);
    });
  }

  createPropertyGroup(propDef, value) {
    const group = document.createElement('div');
    group.className = 'property-group';
    
    const label = document.createElement('label');
    label.className = 'property-label';
    label.textContent = propDef.label;
    if (propDef.required) {
      label.innerHTML += ' <span style="color: var(--color-red)">*</span>';
    }
    group.appendChild(label);
    
    let input;
    
    switch (propDef.type) {
      case 'string':
        input = this.createTextInput(propDef, value);
        break;
      case 'text':
        input = this.createTextarea(propDef, value);
        break;
      case 'number':
        input = this.createNumberInput(propDef, value);
        break;
      case 'boolean':
        input = this.createCheckbox(propDef, value);
        break;
      case 'select':
        input = this.createSelect(propDef, value);
        break;
      case 'json':
        input = this.createJsonEditor(propDef, value);
        break;
      case 'array':
        input = this.createArrayEditor(propDef, value);
        break;
      case 'branches':
        input = this.createBranchesEditor(propDef, value);
        break;
      default:
        input = this.createTextInput(propDef, value);
    }
    
    group.appendChild(input);
    
    if (propDef.description) {
      const hint = document.createElement('div');
      hint.className = 'property-hint';
      hint.textContent = propDef.description;
      group.appendChild(hint);
    }
    
    return group;
  }

  createTextInput(propDef, value) {
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'property-input';
    input.value = value || propDef.default || '';
    input.placeholder = propDef.placeholder || '';
    
    input.addEventListener('input', Utils.debounce(() => {
      this.updateProperty(propDef.name, input.value);
    }, 300));
    
    return input;
  }

  createTextarea(propDef, value) {
    const textarea = document.createElement('textarea');
    textarea.className = 'property-textarea';
    textarea.value = value || propDef.default || '';
    textarea.placeholder = propDef.placeholder || '';
    textarea.rows = 4;
    
    textarea.addEventListener('input', Utils.debounce(() => {
      this.updateProperty(propDef.name, textarea.value);
    }, 300));
    
    return textarea;
  }

  createNumberInput(propDef, value) {
    const input = document.createElement('input');
    input.type = 'number';
    input.className = 'property-input';
    input.value = value ?? propDef.default ?? '';
    
    if (propDef.min !== undefined) input.min = propDef.min;
    if (propDef.max !== undefined) input.max = propDef.max;
    if (propDef.step !== undefined) input.step = propDef.step;
    
    input.addEventListener('input', Utils.debounce(() => {
      const val = input.value === '' ? null : Number(input.value);
      this.updateProperty(propDef.name, val);
    }, 300));
    
    return input;
  }

  createCheckbox(propDef, value) {
    const wrapper = document.createElement('div');
    wrapper.className = 'property-checkbox-wrapper';
    
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.id = `prop-${propDef.name}`;
    input.checked = value ?? propDef.default ?? false;
    
    input.addEventListener('change', () => {
      this.updateProperty(propDef.name, input.checked);
    });
    
    const label = document.createElement('label');
    label.htmlFor = input.id;
    label.textContent = propDef.checkboxLabel || '启用';
    
    wrapper.appendChild(input);
    wrapper.appendChild(label);
    
    return wrapper;
  }

  createSelect(propDef, value) {
    const select = document.createElement('select');
    select.className = 'property-select';
    
    (propDef.options || []).forEach(opt => {
      const option = document.createElement('option');
      if (typeof opt === 'object') {
        option.value = opt.value;
        option.textContent = opt.label;
      } else {
        option.value = opt;
        option.textContent = opt;
      }
      select.appendChild(option);
    });
    
    select.value = value || propDef.default || '';
    
    select.addEventListener('change', () => {
      this.updateProperty(propDef.name, select.value);
    });
    
    return select;
  }

  createJsonEditor(propDef, value) {
    const textarea = document.createElement('textarea');
    textarea.className = 'property-textarea property-json';
    textarea.rows = 6;
    textarea.spellcheck = false;
    
    try {
      textarea.value = JSON.stringify(value || propDef.default || {}, null, 2);
    } catch {
      textarea.value = '{}';
    }
    
    textarea.addEventListener('input', Utils.debounce(() => {
      try {
        const parsed = JSON.parse(textarea.value);
        textarea.classList.remove('error');
        this.updateProperty(propDef.name, parsed);
      } catch {
        textarea.classList.add('error');
      }
    }, 500));
    
    return textarea;
  }

  createArrayEditor(propDef, value) {
    const wrapper = document.createElement('div');
    wrapper.className = 'property-array';
    
    const items = value || [];
    
    const list = document.createElement('div');
    list.className = 'property-array-list';
    
    const renderItems = () => {
      list.innerHTML = '';
      items.forEach((item, index) => {
        const row = document.createElement('div');
        row.className = 'property-array-item';
        
        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'property-input';
        input.value = item;
        
        input.addEventListener('input', Utils.debounce(() => {
          items[index] = input.value;
          this.updateProperty(propDef.name, [...items]);
        }, 300));
        
        const removeBtn = document.createElement('button');
        removeBtn.className = 'property-array-remove';
        removeBtn.innerHTML = '�?;
        removeBtn.onclick = () => {
          items.splice(index, 1);
          this.updateProperty(propDef.name, [...items]);
          renderItems();
        };
        
        row.appendChild(input);
        row.appendChild(removeBtn);
        list.appendChild(row);
      });
    };
    
    renderItems();
    
    const addBtn = document.createElement('button');
    addBtn.className = 'property-array-add';
    addBtn.textContent = '+ 添加';
    addBtn.onclick = () => {
      items.push('');
      this.updateProperty(propDef.name, [...items]);
      renderItems();
    };
    
    wrapper.appendChild(list);
    wrapper.appendChild(addBtn);
    
    return wrapper;
  }

  createBranchesEditor(propDef, value) {
    const wrapper = document.createElement('div');
    wrapper.className = 'property-branches';
    
    const branches = value || [];
    
    const list = document.createElement('div');
    list.className = 'property-branches-list';
    
    const renderBranches = () => {
      list.innerHTML = '';
      branches.forEach((branch, index) => {
        const card = document.createElement('div');
        card.className = 'property-branch-card';
        
        card.innerHTML = `
          <div class="property-branch-header">
            <span>分支 ${index + 1}</span>
            <button class="property-branch-remove">�?/button>
          </div>
          <div class="property-branch-body">
            <label>条件:</label>
            <input type="text" class="property-input branch-condition" value="${branch.condition || ''}" placeholder="表达�?>
            <label>目标:</label>
            <input type="text" class="property-input branch-target" value="${branch.target || ''}" placeholder="目标步骤ID">
          </div>
        `;
        
        card.querySelector('.property-branch-remove').onclick = () => {
          branches.splice(index, 1);
          this.updateProperty(propDef.name, [...branches]);
          renderBranches();
        };
        
        card.querySelector('.branch-condition').addEventListener('input', Utils.debounce((e) => {
          branches[index].condition = e.target.value;
          this.updateProperty(propDef.name, [...branches]);
        }, 300));
        
        card.querySelector('.branch-target').addEventListener('input', Utils.debounce((e) => {
          branches[index].target = e.target.value;
          this.updateProperty(propDef.name, [...branches]);
        }, 300));
        
        list.appendChild(card);
      });
    };
    
    renderBranches();
    
    const addBtn = document.createElement('button');
    addBtn.className = 'property-array-add';
    addBtn.textContent = '+ 添加分支';
    addBtn.onclick = () => {
      branches.push({ condition: '', target: '' });
      this.updateProperty(propDef.name, [...branches]);
      renderBranches();
    };
    
    wrapper.appendChild(list);
    wrapper.appendChild(addBtn);
    
    return wrapper;
  }

  updateProperty(name, value) {
    if (!this.currentNode) return;
    
    this.currentNode.properties[name] = value;
    
    if (this.onChange) {
      this.onChange(this.currentNode, name, value);
    }
  }

  refresh() {
    if (this.currentNode) {
      this.showNode(this.currentNode);
    }
  }
}

// Export
window.PropertiesPanel = PropertiesPanel;
