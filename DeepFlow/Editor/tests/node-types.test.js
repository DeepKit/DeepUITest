/**
 * UniFlow Editor - Node Types Module Tests
 */

describe('NodeTypes - 节点类型定义测试', () => {
  
  // ============================================================================
  // NodeTypes Structure
  // ============================================================================
  
  it('NodeTypes 应包含所有基础节点类型', () => {
    const basicTypes = ['start', 'end'];
    
    basicTypes.forEach(type => {
      assert.hasProperty(NodeTypes, type, `Missing node type: ${type}`);
    });
  });

  it('NodeTypes 应包含所有动作节点类�?, () => {
    const actionTypes = ['llm', 'skill', 'http', 'script', 'assign', 'log'];
    
    actionTypes.forEach(type => {
      assert.hasProperty(NodeTypes, type, `Missing node type: ${type}`);
    });
  });

  it('NodeTypes 应包含所有流程控制节点类�?, () => {
    const flowTypes = ['condition', 'loop', 'parallel', 'wait'];
    
    flowTypes.forEach(type => {
      assert.hasProperty(NodeTypes, type, `Missing node type: ${type}`);
    });
  });

  it('NodeTypes 应包含所有高级节点类�?, () => {
    const advancedTypes = ['subworkflow', 'guard'];
    
    advancedTypes.forEach(type => {
      assert.hasProperty(NodeTypes, type, `Missing node type: ${type}`);
    });
  });

  // ============================================================================
  // Node Type Definition Structure
  // ============================================================================
  
  it('每个节点类型应有必要的属�?, () => {
    const requiredProps = ['type', 'label', 'icon', 'description', 'category', 
                          'color', 'maxInputs', 'maxOutputs', 'properties', 'toWorkflowStep'];
    
    Object.keys(NodeTypes).forEach(key => {
      const nodeType = NodeTypes[key];
      requiredProps.forEach(prop => {
        assert.hasProperty(nodeType, prop, `${key} missing property: ${prop}`);
      });
    });
  });

  it('节点类型�?type 应与键名匹配', () => {
    Object.keys(NodeTypes).forEach(key => {
      assert.equal(NodeTypes[key].type, key, `Type mismatch for ${key}`);
    });
  });

  it('所有节点类型应有有效的分类', () => {
    const validCategories = ['basic', 'action', 'flow', 'advanced'];
    
    Object.keys(NodeTypes).forEach(key => {
      const category = NodeTypes[key].category;
      assert.include(validCategories, category, `Invalid category for ${key}: ${category}`);
    });
  });

  it('所有节点类型应有有效的颜色', () => {
    Object.keys(NodeTypes).forEach(key => {
      const color = NodeTypes[key].color;
      assert.match(color, /^#[0-9a-fA-F]{6}$/, `Invalid color for ${key}: ${color}`);
    });
  });

  // ============================================================================
  // Port Constraints
  // ============================================================================
  
  it('start 节点应有 0 个输入端�?, () => {
    assert.equal(NodeTypes.start.maxInputs, 0);
  });

  it('start 节点应有 1 个输出端�?, () => {
    assert.equal(NodeTypes.start.maxOutputs, 1);
  });

  it('end 节点应有 1 个输入端�?, () => {
    assert.equal(NodeTypes.end.maxInputs, 1);
  });

  it('end 节点应有 0 个输出端�?, () => {
    assert.equal(NodeTypes.end.maxOutputs, 0);
  });

  it('condition 节点应有多个输出端口', () => {
    assert.isAbove(NodeTypes.condition.maxOutputs, 1);
  });

  it('parallel 节点应有多个输出端口', () => {
    assert.isAbove(NodeTypes.parallel.maxOutputs, 1);
  });

  // ============================================================================
  // Properties Definitions
  // ============================================================================
  
  it('所有节点应�?id �?name 属�?, () => {
    Object.keys(NodeTypes).forEach(key => {
      const props = NodeTypes[key].properties;
      const propNames = props.map(p => p.name);
      
      assert.include(propNames, 'id', `${key} missing id property`);
      assert.include(propNames, 'name', `${key} missing name property`);
    });
  });

  it('id 属性应为只�?, () => {
    Object.keys(NodeTypes).forEach(key => {
      const idProp = NodeTypes[key].properties.find(p => p.name === 'id');
      assert.isTrue(idProp.readonly, `${key} id should be readonly`);
    });
  });

  it('属性应有有效的类型', () => {
    const validTypes = ['text', 'textarea', 'number', 'select', 'checkbox', 
                        'json', 'array', 'string', 'boolean', 'branches'];
    
    Object.keys(NodeTypes).forEach(key => {
      NodeTypes[key].properties.forEach(prop => {
        assert.include(validTypes, prop.type, 
          `Invalid property type in ${key}.${prop.name}: ${prop.type}`);
      });
    });
  });

  // ============================================================================
  // LLM Node Specific
  // ============================================================================
  
  describe('LLM 节点', () => {
    const llm = NodeTypes.llm;

    it('应有 provider 属�?, () => {
      const providerProp = llm.properties.find(p => p.name === 'provider');
      
      assert.isDefined(providerProp);
      assert.equal(providerProp.type, 'select');
      assert.isArray(providerProp.options);
      assert.include(providerProp.options, 'openai');
      assert.include(providerProp.options, 'anthropic');
    });

    it('应有 prompt 属�?, () => {
      const promptProp = llm.properties.find(p => p.name === 'prompt');
      
      assert.isDefined(promptProp);
      assert.equal(promptProp.type, 'textarea');
    });

    it('应有 temperature 属�?, () => {
      const tempProp = llm.properties.find(p => p.name === 'temperature');
      
      assert.isDefined(tempProp);
      assert.equal(tempProp.type, 'number');
      assert.equal(tempProp.min, 0);
      assert.equal(tempProp.max, 2);
    });
  });

  // ============================================================================
  // HTTP Node Specific
  // ============================================================================
  
  describe('HTTP 节点', () => {
    const http = NodeTypes.http;

    it('应有 method 属�?, () => {
      const methodProp = http.properties.find(p => p.name === 'method');
      
      assert.isDefined(methodProp);
      assert.equal(methodProp.type, 'select');
      assert.include(methodProp.options, 'GET');
      assert.include(methodProp.options, 'POST');
      assert.include(methodProp.options, 'PUT');
      assert.include(methodProp.options, 'DELETE');
    });

    it('应有 url 属�?, () => {
      const urlProp = http.properties.find(p => p.name === 'url');
      
      assert.isDefined(urlProp);
      assert.equal(urlProp.type, 'text');
    });

    it('应有 headers �?body 属�?, () => {
      const headersProp = http.properties.find(p => p.name === 'headers');
      const bodyProp = http.properties.find(p => p.name === 'body');
      
      assert.isDefined(headersProp);
      assert.isDefined(bodyProp);
      assert.equal(headersProp.type, 'textarea');
      assert.equal(bodyProp.type, 'textarea');
    });
  });

  // ============================================================================
  // Loop Node Specific
  // ============================================================================
  
  describe('Loop 节点', () => {
    const loop = NodeTypes.loop;

    it('应有 mode 属�?, () => {
      const modeProp = loop.properties.find(p => p.name === 'mode');
      
      assert.isDefined(modeProp);
      assert.equal(modeProp.type, 'select');
      assert.include(modeProp.options, 'forEach');
      assert.include(modeProp.options, 'while');
      assert.include(modeProp.options, 'repeat');
    });

    it('应有循环相关属�?, () => {
      const props = loop.properties.map(p => p.name);
      
      assert.include(props, 'collection');
      assert.include(props, 'condition');
      assert.include(props, 'count');
      assert.include(props, 'itemVar');
    });
  });

  // ============================================================================
  // toWorkflowStep() Conversion
  // ============================================================================
  
  describe('toWorkflowStep() 转换', () => {
    
    it('start 节点应转换为 action 步骤', () => {
      const node = {
        id: 'node_123',
        type: 'start',
        properties: { name: '开始节�? }
      };
      
      const step = NodeTypes.start.toWorkflowStep(node);
      
      assert.equal(step.id, 'node_123');
      assert.equal(step.type, 'action');
      assert.equal(step.name, '开始节�?);
    });

    it('end 节点应转换为 end 步骤', () => {
      const node = {
        id: 'node_456',
        type: 'end',
        properties: { name: '结束节点' }
      };
      
      const step = NodeTypes.end.toWorkflowStep(node);
      
      assert.equal(step.id, 'node_456');
      assert.equal(step.type, 'end');
    });

    it('llm 节点应转换为包含 llm action 的步�?, () => {
      const node = {
        id: 'node_llm',
        type: 'llm',
        properties: {
          name: 'AI 调用',
          provider: 'anthropic',
          model: 'claude-3',
          prompt: 'Hello',
          temperature: 0.5,
          maxTokens: 500,
          outputVar: 'result'
        }
      };
      
      const step = NodeTypes.llm.toWorkflowStep(node);
      
      assert.equal(step.type, 'action');
      assert.equal(step.action.type, 'llm');
      assert.equal(step.action.provider, 'anthropic');
      assert.equal(step.action.model, 'claude-3');
      assert.equal(step.action.prompt, 'Hello');
      assert.equal(step.action.temperature, 0.5);
      assert.equal(step.action.max_tokens, 500);
      assert.equal(step.output.target, 'result');
    });

    it('condition 节点应转换为 condition 步骤', () => {
      const node = {
        id: 'node_cond',
        type: 'condition',
        properties: {
          name: '条件判断',
          expression: '{{ vars.count }} > 10'
        }
      };
      
      const step = NodeTypes.condition.toWorkflowStep(node);
      
      assert.equal(step.type, 'condition');
      assert.equal(step.condition.expression, '{{ vars.count }} > 10');
    });

    it('loop 节点应转换为 loop 步骤', () => {
      const node = {
        id: 'node_loop',
        type: 'loop',
        properties: {
          name: '循环',
          mode: 'forEach',
          collection: '{{ vars.items }}',
          itemVar: 'item'
        }
      };
      
      const step = NodeTypes.loop.toWorkflowStep(node);
      
      assert.equal(step.type, 'loop');
      assert.equal(step.loop.mode, 'forEach');
      assert.equal(step.loop.collection, '{{ vars.items }}');
      assert.equal(step.loop.item_var, 'item');
    });

    it('skill 节点应正确解�?JSON 输入', () => {
      const node = {
        id: 'node_skill',
        type: 'skill',
        properties: {
          name: 'Skill 调用',
          skillName: 'search',
          input: '{"query": "test"}',
          outputVar: 'search_result'
        }
      };
      
      const step = NodeTypes.skill.toWorkflowStep(node);
      
      assert.equal(step.action.type, 'skill');
      assert.deepEqual(step.action.input, { query: 'test' });
    });

    it('http 节点应正确处理空 body', () => {
      const node = {
        id: 'node_http',
        type: 'http',
        properties: {
          name: 'GET 请求',
          method: 'GET',
          url: 'https://api.example.com',
          headers: '{"Accept": "application/json"}',
          body: '',
          outputVar: 'response'
        }
      };
      
      const step = NodeTypes.http.toWorkflowStep(node);
      
      assert.equal(step.action.method, 'GET');
      assert.isUndefined(step.action.body);
      assert.deepEqual(step.action.headers, { Accept: 'application/json' });
    });
  });

  // ============================================================================
  // getDefaultProperties()
  // ============================================================================
  
  describe('getDefaultProperties()', () => {
    
    it('应返回节点类型的默认属�?, () => {
      const props = getDefaultProperties('llm');
      
      assert.isDefined(props.id);
      assert.equal(props.name, 'LLM 调用');
      assert.equal(props.provider, 'openai');
      assert.equal(props.model, 'gpt-4');
      assert.equal(props.temperature, 0.7);
    });

    it('应为未知类型返回空对�?, () => {
      const props = getDefaultProperties('unknown_type');
      
      assert.deepEqual(props, {});
    });

    it('生成�?ID 应该是唯一�?, () => {
      const props1 = getDefaultProperties('start');
      const props2 = getDefaultProperties('start');
      
      assert.notEqual(props1.id, props2.id);
    });
  });
});
