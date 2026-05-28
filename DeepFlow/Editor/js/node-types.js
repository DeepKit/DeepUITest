/**
 * UniFlow Workflow Editor - Node Type Definitions
 */

// Safe JSON parse helper to prevent crashes on invalid input
function safeJsonParse(str, fallback = {}) {
  if (!str || str.trim() === '') return fallback;
  try {
    return JSON.parse(str);
  } catch (e) {
    console.warn('Failed to parse JSON:', e.message, 'Input:', str.substring(0, 100));
    return fallback;
  }
}

const NodeTypes = {
  // ============================================================================
  // Basic Nodes
  // ============================================================================
  
  start: {
    type: 'start',
    label: '开�?,
    icon: '�?,
    description: '工作流入口点',
    category: 'basic',
    color: '#a6e3a1',
    maxInputs: 0,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '开�?
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name || 'start',
      action: { type: 'log', message: 'Workflow started' }
    })
  },

  end: {
    type: 'end',
    label: '结束',
    icon: '�?,
    description: '工作流结束点',
    category: 'basic',
    color: '#f38ba8',
    maxInputs: 1,
    maxOutputs: 0,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '结束'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'end',
      name: node.properties.name || 'end'
    })
  },

  // ============================================================================
  // Action Nodes
  // ============================================================================

  llm: {
    type: 'llm',
    label: 'LLM 调用',
    icon: '🤖',
    description: '调用大语言模型',
    category: 'action',
    color: '#cba6f7',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: 'LLM 调用'
      },
      {
        name: 'provider',
        label: '提供�?,
        type: 'select',
        options: ['openai', 'anthropic', 'azure', 'ollama'],
        default: 'openai'
      },
      {
        name: 'model',
        label: '模型',
        type: 'text',
        default: 'gpt-4'
      },
      {
        name: 'prompt',
        label: 'Prompt',
        type: 'textarea',
        default: ''
      },
      {
        name: 'temperature',
        label: '温度',
        type: 'number',
        default: 0.7,
        min: 0,
        max: 2
      },
      {
        name: 'maxTokens',
        label: '最�?Token',
        type: 'number',
        default: 1000
      },
      {
        name: 'outputVar',
        label: '输出变量',
        type: 'text',
        default: 'llm_response'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'llm',
        provider: node.properties.provider,
        model: node.properties.model,
        prompt: node.properties.prompt,
        temperature: node.properties.temperature,
        max_tokens: node.properties.maxTokens
      },
      output: {
        target: node.properties.outputVar
      }
    })
  },

  skill: {
    type: 'skill',
    label: 'Skill',
    icon: '⚙️',
    description: '调用 Skill 服务',
    category: 'action',
    color: '#fab387',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: 'Skill 调用'
      },
      {
        name: 'skillName',
        label: 'Skill 名称',
        type: 'text',
        default: ''
      },
      {
        name: 'input',
        label: '输入参数 (JSON)',
        type: 'textarea',
        default: '{}'
      },
      {
        name: 'outputVar',
        label: '输出变量',
        type: 'text',
        default: 'skill_result'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'skill',
        skill: node.properties.skillName,
        input: safeJsonParse(node.properties.input, {})
      },
      output: {
        target: node.properties.outputVar
      }
    })
  },

  http: {
    type: 'http',
    label: 'HTTP 请求',
    icon: '🌐',
    description: '发�?HTTP 请求',
    category: 'action',
    color: '#74c7ec',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: 'HTTP 请求'
      },
      {
        name: 'method',
        label: '方法',
        type: 'select',
        options: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
        default: 'GET'
      },
      {
        name: 'url',
        label: 'URL',
        type: 'text',
        default: ''
      },
      {
        name: 'headers',
        label: '请求�?(JSON)',
        type: 'textarea',
        default: '{}'
      },
      {
        name: 'body',
        label: '请求�?(JSON)',
        type: 'textarea',
        default: ''
      },
      {
        name: 'outputVar',
        label: '输出变量',
        type: 'text',
        default: 'http_response'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'http',
        method: node.properties.method,
        url: node.properties.url,
        headers: safeJsonParse(node.properties.headers, {}),
        body: node.properties.body ? safeJsonParse(node.properties.body, null) : undefined
      },
      output: {
        target: node.properties.outputVar
      }
    })
  },

  script: {
    type: 'script',
    label: '脚本',
    icon: '📜',
    description: '执行自定义脚�?,
    category: 'action',
    color: '#89dceb',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '脚本'
      },
      {
        name: 'language',
        label: '语言',
        type: 'select',
        options: ['javascript', 'python'],
        default: 'javascript'
      },
      {
        name: 'code',
        label: '代码',
        type: 'textarea',
        default: '// 输入: ctx.input\n// 输出: return result;'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'script',
        language: node.properties.language,
        code: node.properties.code
      }
    })
  },

  assign: {
    type: 'assign',
    label: '赋�?,
    icon: '📝',
    description: '设置变量�?,
    category: 'action',
    color: '#a6adc8',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '赋�?
      },
      {
        name: 'variable',
        label: '变量�?,
        type: 'text',
        default: ''
      },
      {
        name: 'value',
        label: '�?,
        type: 'textarea',
        default: ''
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'assign',
        assignments: [
          {
            target: node.properties.variable,
            value: node.properties.value
          }
        ]
      }
    })
  },

  log: {
    type: 'log',
    label: '日志',
    icon: '📋',
    description: '输出日志信息',
    category: 'action',
    color: '#bac2de',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '日志'
      },
      {
        name: 'level',
        label: '级别',
        type: 'select',
        options: ['debug', 'info', 'warning', 'error'],
        default: 'info'
      },
      {
        name: 'message',
        label: '消息',
        type: 'textarea',
        default: ''
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'log',
        level: node.properties.level,
        message: node.properties.message
      }
    })
  },

  // ============================================================================
  // Flow Control Nodes
  // ============================================================================

  condition: {
    type: 'condition',
    label: '条件分支',
    icon: '🔀',
    description: '根据条件分支执行',
    category: 'flow',
    color: '#f9e2af',
    maxInputs: 1,
    maxOutputs: 2,
    outputLabels: ['�?, '�?],
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '条件分支'
      },
      {
        name: 'expression',
        label: '条件表达�?,
        type: 'textarea',
        default: '{{ vars.value }} == true'
      }
    ],
    toWorkflowStep: (node, connections) => ({
      id: node.id,
      type: 'condition',
      name: node.properties.name,
      condition: {
        expression: node.properties.expression
      }
    })
  },

  loop: {
    type: 'loop',
    label: '循环',
    icon: '🔄',
    description: '循环执行',
    category: 'flow',
    color: '#94e2d5',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '循环'
      },
      {
        name: 'mode',
        label: '循环模式',
        type: 'select',
        options: ['forEach', 'while', 'repeat'],
        default: 'forEach'
      },
      {
        name: 'collection',
        label: '集合 (forEach)',
        type: 'text',
        default: '{{ vars.items }}'
      },
      {
        name: 'condition',
        label: '条件 (while)',
        type: 'text',
        default: ''
      },
      {
        name: 'count',
        label: '次数 (repeat)',
        type: 'number',
        default: 10
      },
      {
        name: 'itemVar',
        label: '元素变量',
        type: 'text',
        default: 'item'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'loop',
      name: node.properties.name,
      loop: {
        mode: node.properties.mode,
        collection: node.properties.collection,
        condition: node.properties.condition,
        count: node.properties.count,
        item_var: node.properties.itemVar
      }
    })
  },

  parallel: {
    type: 'parallel',
    label: '并行',
    icon: '�?,
    description: '并行执行多个分支',
    category: 'flow',
    color: '#eba0ac',
    maxInputs: 1,
    maxOutputs: 3,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '并行执行'
      },
      {
        name: 'waitAll',
        label: '等待全部完成',
        type: 'checkbox',
        default: true
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'parallel',
      name: node.properties.name,
      parallel: {
        wait_all: node.properties.waitAll
      }
    })
  },

  wait: {
    type: 'wait',
    label: '等待',
    icon: '�?,
    description: '等待指定时间或事�?,
    category: 'flow',
    color: '#f5c2e7',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '等待'
      },
      {
        name: 'strategy',
        label: '等待策略',
        type: 'select',
        options: ['duration', 'event', 'approval'],
        default: 'duration'
      },
      {
        name: 'duration',
        label: '持续时间 (�?',
        type: 'number',
        default: 5
      },
      {
        name: 'event',
        label: '事件名称',
        type: 'text',
        default: ''
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'wait',
      name: node.properties.name,
      wait: {
        strategy: node.properties.strategy,
        duration: node.properties.duration,
        event: node.properties.event
      }
    })
  },

  // ============================================================================
  // Advanced Nodes
  // ============================================================================

  subworkflow: {
    type: 'subworkflow',
    label: '子工作流',
    icon: '📦',
    description: '调用另一个工作流',
    category: 'advanced',
    color: '#b4befe',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '子工作流'
      },
      {
        name: 'workflowId',
        label: '工作�?ID',
        type: 'text',
        default: ''
      },
      {
        name: 'input',
        label: '输入参数 (JSON)',
        type: 'textarea',
        default: '{}'
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'subworkflow',
      name: node.properties.name,
      workflow_id: node.properties.workflowId,
      input: safeJsonParse(node.properties.input, {})
    })
  },

  guard: {
    type: 'guard',
    label: '校验',
    icon: '🛡�?,
    description: '输入校验和安全检�?,
    category: 'advanced',
    color: '#f2cdcd',
    maxInputs: 1,
    maxOutputs: 1,
    properties: [
      {
        name: 'id',
        label: 'ID',
        type: 'text',
        readonly: true
      },
      {
        name: 'name',
        label: '名称',
        type: 'text',
        default: '校验'
      },
      {
        name: 'schema',
        label: 'JSON Schema',
        type: 'textarea',
        default: '{}'
      },
      {
        name: 'sanitize',
        label: '消毒输入',
        type: 'checkbox',
        default: true
      }
    ],
    toWorkflowStep: (node) => ({
      id: node.id,
      type: 'action',
      name: node.properties.name,
      action: {
        type: 'guard',
        schema: safeJsonParse(node.properties.schema, {}),
        sanitize: node.properties.sanitize
      }
    })
  }
};

// Get default properties for a node type
function getDefaultProperties(type) {
  const nodeType = NodeTypes[type];
  if (!nodeType) return {};
  
  const props = { id: Utils.generateId() };
  for (const prop of nodeType.properties) {
    if (prop.default !== undefined) {
      props[prop.name] = prop.default;
    }
  }
  return props;
}

// Export
window.NodeTypes = NodeTypes;
window.getDefaultProperties = getDefaultProperties;
