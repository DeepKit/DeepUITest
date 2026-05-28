/**
 * UniFlow Editor - Properties Panel Tests
 */

describe('PropertiesPanel - 属性面板测�?, () => {
  let panel;
  let container;
  
  beforeEach(() => {
    container = document.getElementById('mockProperties');
    panel = new PropertiesPanel(container);
  });
  
  afterEach(() => {
    panel.showEmpty();
  });

  // ============================================================================
  // Initialization
  // ============================================================================
  
  it('应正确初始化属性面�?, () => {
    assert.isDefined(panel.container);
    assert.isDefined(panel.contentEl);
    assert.isDefined(panel.titleEl);
    assert.isNull(panel.currentNode);
  });

  it('初始状态应显示空状�?, () => {
    assert.isNull(panel.currentNode);
    assert.include(panel.contentEl.innerHTML, '选择节点');
  });

  // ============================================================================
  // showEmpty()
  // ============================================================================
  
  it('showEmpty() 应清除当前节�?, () => {
    panel.currentNode = { id: 'test' };
    panel.showEmpty();
    
    assert.isNull(panel.currentNode);
  });

  it('showEmpty() 应显示空状态提�?, () => {
    panel.showEmpty();
    
    assert.include(panel.contentEl.innerHTML, '选择节点');
    assert.equal(panel.titleEl.textContent, '属�?);
  });

  // ============================================================================
  // showNode()
  // ============================================================================
  
  describe('showNode()', () => {
    
    it('应设置当前节�?, () => {
      const node = {
        id: 'test_node',
        type: 'start',
        properties: { id: 'test_node', name: '开�? }
      };
      
      panel.showNode(node);
      
      assert.equal(panel.currentNode, node);
    });

    it('应更新标�?, () => {
      const node = {
        id: 'test_node',
        type: 'llm',
        properties: { id: 'test_node', name: 'LLM' }
      };
      
      panel.showNode(node);
      
      assert.include(panel.titleEl.textContent, 'LLM 调用');
    });

    it('应渲染所有属性字�?, () => {
      const node = {
        id: 'test_node',
        type: 'llm',
        properties: { id: 'test_node', name: 'LLM' }
      };
      
      panel.showNode(node);
      
      // Should have property groups for each property
      const groups = panel.contentEl.querySelectorAll('.property-group');
      assert.isAbove(groups.length, 0);
    });
  });

  // ============================================================================
  // Property Input Creation
  // ============================================================================
  
  describe('属性输入框创建', () => {
    
    it('应创建文本输入框', () => {
      const node = {
        id: 'test',
        type: 'start',
        properties: { id: 'test', name: '测试' }
      };
      
      panel.showNode(node);
      
      const inputs = panel.contentEl.querySelectorAll('input[type="text"]');
      assert.isAbove(inputs.length, 0);
    });

    it('应创建数字输入框', () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', temperature: 0.7 }
      };
      
      panel.showNode(node);
      
      const inputs = panel.contentEl.querySelectorAll('input[type="number"]');
      assert.isAbove(inputs.length, 0);
    });

    it('应创建文本区�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', prompt: '' }
      };
      
      panel.showNode(node);
      
      const textareas = panel.contentEl.querySelectorAll('textarea');
      assert.isAbove(textareas.length, 0);
    });

    it('应创建选择�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', provider: 'openai' }
      };
      
      panel.showNode(node);
      
      const selects = panel.contentEl.querySelectorAll('select');
      assert.isAbove(selects.length, 0);
    });

    it('应创建复选框', () => {
      const node = {
        id: 'test',
        type: 'parallel',
        properties: { id: 'test', name: '并行', waitAll: true }
      };
      
      panel.showNode(node);
      
      const checkboxes = panel.contentEl.querySelectorAll('input[type="checkbox"]');
      assert.isAbove(checkboxes.length, 0);
    });
  });

  // ============================================================================
  // Property Values
  // ============================================================================
  
  describe('属性值显�?, () => {
    
    it('文本输入应显示当前�?, () => {
      const node = {
        id: 'test',
        type: 'start',
        properties: { id: 'test', name: '我的节点' }
      };
      
      panel.showNode(node);
      
      const nameInput = Array.from(panel.contentEl.querySelectorAll('input[type="text"]'))
        .find(input => input.value === '我的节点');
      
      assert.isDefined(nameInput);
    });

    it('数字输入应显示当前�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', temperature: 0.5, maxTokens: 2000 }
      };
      
      panel.showNode(node);
      
      const tempInput = Array.from(panel.contentEl.querySelectorAll('input[type="number"]'))
        .find(input => input.value === '0.5');
      
      assert.isDefined(tempInput);
    });

    it('选择框应显示当前�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', provider: 'anthropic' }
      };
      
      panel.showNode(node);
      
      const select = panel.contentEl.querySelector('select');
      assert.equal(select.value, 'anthropic');
    });
  });

  // ============================================================================
  // updateProperty()
  // ============================================================================
  
  describe('updateProperty()', () => {
    
    it('应更新节点属�?, () => {
      const node = {
        id: 'test',
        type: 'start',
        properties: { id: 'test', name: '旧名�? }
      };
      
      panel.showNode(node);
      panel.updateProperty('name', '新名�?);
      
      assert.equal(node.properties.name, '新名�?);
    });

    it('无当前节点时不应抛出错误', () => {
      panel.currentNode = null;
      
      assert.doesNotThrow(() => {
        panel.updateProperty('name', 'value');
      });
    });

    it('应触�?onChange 回调', () => {
      let callbackArgs = null;
      
      panel.onChange = (node, propName, value) => {
        callbackArgs = { node, propName, value };
      };
      
      const node = {
        id: 'test',
        type: 'start',
        properties: { id: 'test', name: '测试' }
      };
      
      panel.showNode(node);
      panel.updateProperty('name', '新�?);
      
      assert.isDefined(callbackArgs);
      assert.equal(callbackArgs.node, node);
      assert.equal(callbackArgs.propName, 'name');
      assert.equal(callbackArgs.value, '新�?);
    });
  });

  // ============================================================================
  // refresh()
  // ============================================================================
  
  describe('refresh()', () => {
    
    it('应重新渲染当前节�?, () => {
      const node = {
        id: 'test',
        type: 'start',
        properties: { id: 'test', name: '原名�? }
      };
      
      panel.showNode(node);
      node.properties.name = '新名�?;
      panel.refresh();
      
      const nameInput = Array.from(panel.contentEl.querySelectorAll('input[type="text"]'))
        .find(input => input.value === '新名�?);
      
      assert.isDefined(nameInput);
    });

    it('无当前节点时不应抛出错误', () => {
      panel.currentNode = null;
      
      assert.doesNotThrow(() => {
        panel.refresh();
      });
    });
  });

  // ============================================================================
  // Property Group Creation
  // ============================================================================
  
  describe('createPropertyGroup()', () => {
    
    it('应创建带标签的属性组', () => {
      const propDef = {
        name: 'testProp',
        label: '测试属�?,
        type: 'text',
        default: ''
      };
      
      const group = panel.createPropertyGroup(propDef, 'value');
      
      assert.ok(group.classList.contains('property-group'));
      assert.include(group.innerHTML, '测试属�?);
    });

    it('必填属性应有标�?, () => {
      const propDef = {
        name: 'requiredProp',
        label: '必填',
        type: 'text',
        required: true
      };
      
      const group = panel.createPropertyGroup(propDef, '');
      
      assert.include(group.innerHTML, '*');
    });

    it('有描述的属性应显示提示', () => {
      const propDef = {
        name: 'prop',
        label: '属�?,
        type: 'text',
        description: '这是属性描�?
      };
      
      const group = panel.createPropertyGroup(propDef, '');
      
      assert.include(group.innerHTML, '这是属性描�?);
      assert.ok(group.querySelector('.property-hint'));
    });
  });

  // ============================================================================
  // Number Input Constraints
  // ============================================================================
  
  describe('数字输入约束', () => {
    
    it('应设�?min 属�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', temperature: 0.7 }
      };
      
      panel.showNode(node);
      
      const inputs = panel.contentEl.querySelectorAll('input[type="number"]');
      const hasMinAttr = Array.from(inputs).some(input => input.hasAttribute('min'));
      
      assert.isTrue(hasMinAttr);
    });

    it('应设�?max 属�?, () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', temperature: 0.7 }
      };
      
      panel.showNode(node);
      
      const inputs = panel.contentEl.querySelectorAll('input[type="number"]');
      const hasMaxAttr = Array.from(inputs).some(input => input.hasAttribute('max'));
      
      assert.isTrue(hasMaxAttr);
    });
  });

  // ============================================================================
  // Select Options
  // ============================================================================
  
  describe('选择框选项', () => {
    
    it('应渲染所有选项', () => {
      const node = {
        id: 'test',
        type: 'llm',
        properties: { id: 'test', name: 'LLM', provider: 'openai' }
      };
      
      panel.showNode(node);
      
      const select = panel.contentEl.querySelector('select');
      const options = select.querySelectorAll('option');
      
      // LLM provider has 4 options: openai, anthropic, azure, ollama
      assert.equal(options.length, 4);
    });

    it('选项值应正确', () => {
      const node = {
        id: 'test',
        type: 'http',
        properties: { id: 'test', name: 'HTTP', method: 'GET' }
      };
      
      panel.showNode(node);
      
      const select = panel.contentEl.querySelector('select');
      const optionValues = Array.from(select.options).map(o => o.value);
      
      assert.include(optionValues, 'GET');
      assert.include(optionValues, 'POST');
      assert.include(optionValues, 'PUT');
      assert.include(optionValues, 'DELETE');
    });
  });
});
