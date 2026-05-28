/**
 * UniFlow Editor - Integration Tests
 * Tests for end-to-end workflows across multiple components
 */

describe('Integration - 集成测试', () => {
  let canvas;
  let properties;
  
  beforeEach(() => {
    const canvasContainer = document.getElementById('mockCanvas');
    const propsContainer = document.getElementById('mockProperties');
    
    canvas = new WorkflowCanvas(canvasContainer);
    properties = new PropertiesPanel(propsContainer);
  });
  
  afterEach(() => {
    canvas.clear();
    properties.showEmpty();
    document.getElementById('nodesLayer').innerHTML = '';
    document.getElementById('connectionsLayer').innerHTML = '';
  });

  // ============================================================================
  // Complete Workflow Creation
  // ============================================================================
  
  describe('完整工作流创�?, () => {
    
    it('应能创建简单的线性工作流', () => {
      // Create: Start -> LLM -> End
      const start = canvas.addNode('start', 100, 50);
      const llm = canvas.addNode('llm', 100, 150);
      const end = canvas.addNode('end', 100, 250);
      
      canvas.addConnection(start.id, llm.id);
      canvas.addConnection(llm.id, end.id);
      
      assert.equal(canvas.nodes.size, 3);
      assert.equal(canvas.connections.length, 2);
      
      const workflow = canvas.toWorkflowDefinition();
      assert.equal(workflow.steps.length, 3);
    });

    it('应能创建带条件分支的工作�?, () => {
      // Create: Start -> Condition -> (Yes: LLM, No: Log) -> End
      const start = canvas.addNode('start', 100, 50);
      const condition = canvas.addNode('condition', 100, 150);
      const llm = canvas.addNode('llm', 50, 250);
      const log = canvas.addNode('log', 200, 250);
      const end = canvas.addNode('end', 100, 350);
      
      canvas.addConnection(start.id, condition.id);
      canvas.addConnection(condition.id, llm.id);
      canvas.addConnection(condition.id, log.id);
      canvas.addConnection(llm.id, end.id);
      canvas.addConnection(log.id, end.id);
      
      assert.equal(canvas.nodes.size, 5);
      assert.equal(canvas.connections.length, 5);
    });

    it('应能创建带循环的工作�?, () => {
      const start = canvas.addNode('start', 100, 50);
      const loop = canvas.addNode('loop', 100, 150);
      const http = canvas.addNode('http', 100, 250);
      const end = canvas.addNode('end', 100, 350);
      
      canvas.addConnection(start.id, loop.id);
      canvas.addConnection(loop.id, http.id);
      canvas.addConnection(http.id, end.id);
      
      assert.equal(canvas.nodes.size, 4);
    });

    it('应能创建带并行节点的工作�?, () => {
      const start = canvas.addNode('start', 100, 50);
      const parallel = canvas.addNode('parallel', 100, 150);
      const http1 = canvas.addNode('http', 50, 250);
      const http2 = canvas.addNode('http', 150, 250);
      const end = canvas.addNode('end', 100, 350);
      
      canvas.addConnection(start.id, parallel.id);
      canvas.addConnection(parallel.id, http1.id);
      canvas.addConnection(parallel.id, http2.id);
      canvas.addConnection(http1.id, end.id);
      canvas.addConnection(http2.id, end.id);
      
      assert.equal(canvas.nodes.size, 5);
    });
  });

  // ============================================================================
  // Canvas and Properties Panel Integration
  // ============================================================================
  
  describe('画布与属性面板联�?, () => {
    
    it('选择节点应显示其属�?, () => {
      const node = canvas.addNode('llm', 100, 100);
      
      canvas.events.on('selectionChanged', (nodes) => {
        if (nodes.length === 1) {
          properties.showNode(nodes[0]);
        }
      });
      
      canvas.selectNode(node);
      
      assert.equal(properties.currentNode, node);
    });

    it('取消选择应清空属性面�?, () => {
      const node = canvas.addNode('start', 100, 100);
      
      canvas.events.on('selectionChanged', (nodes) => {
        if (nodes.length === 0) {
          properties.showEmpty();
        }
      });
      
      canvas.selectNode(node);
      canvas.clearSelection();
      
      assert.isNull(properties.currentNode);
    });

    it('属性修改应反映到节�?, () => {
      const node = canvas.addNode('start', 100, 100);
      
      properties.showNode(node);
      properties.updateProperty('name', '新开始节�?);
      
      assert.equal(node.properties.name, '新开始节�?);
    });
  });

  // ============================================================================
  // Serialization Round-trip
  // ============================================================================
  
  describe('序列化往返测�?, () => {
    
    it('导出再导入应保持一�?, () => {
      // Create workflow
      const start = canvas.addNode('start', 100, 50);
      const llm = canvas.addNode('llm', 100, 150);
      const end = canvas.addNode('end', 100, 250);
      
      llm.properties.prompt = 'Test prompt';
      llm.properties.temperature = 0.5;
      
      canvas.addConnection(start.id, llm.id);
      canvas.addConnection(llm.id, end.id);
      
      // Export
      const json = canvas.toJSON();
      
      // Clear and import
      canvas.clear();
      canvas.fromJSON(json);
      
      // Verify
      assert.equal(canvas.nodes.size, 3);
      assert.equal(canvas.connections.length, 2);
      
      // Check LLM properties preserved
      const importedLLM = Array.from(canvas.nodes.values()).find(n => n.type === 'llm');
      assert.equal(importedLLM.properties.prompt, 'Test prompt');
      assert.equal(importedLLM.properties.temperature, 0.5);
    });

    it('生成的工作流定义应有�?, () => {
      const start = canvas.addNode('start', 100, 50);
      const llm = canvas.addNode('llm', 100, 150);
      const end = canvas.addNode('end', 100, 250);
      
      canvas.addConnection(start.id, llm.id);
      canvas.addConnection(llm.id, end.id);
      
      const workflow = canvas.toWorkflowDefinition();
      
      // Verify structure
      assert.isDefined(workflow.id);
      assert.isDefined(workflow.name);
      assert.isDefined(workflow.version);
      assert.equal(workflow.steps.length, 3);
      
      // Verify steps have correct types
      const types = workflow.steps.map(s => s.type);
      assert.include(types, 'action');
      assert.include(types, 'end');
      
      // Verify connections (next_step)
      const startStep = workflow.steps.find(s => s.id === start.id);
      const llmStep = workflow.steps.find(s => s.id === llm.id);
      
      assert.equal(startStep.next_step, llm.id);
      assert.equal(llmStep.next_step, end.id);
    });
  });

  // ============================================================================
  // Node Type Completeness
  // ============================================================================
  
  describe('节点类型完整�?, () => {
    
    it('所有节点类型都能成功创�?, () => {
      const types = Object.keys(NodeTypes);
      
      types.forEach((type, index) => {
        const node = canvas.addNode(type, index * 100, 0);
        assert.isDefined(node, `Failed to create node of type: ${type}`);
      });
      
      assert.equal(canvas.nodes.size, types.length);
    });

    it('所有节点类型都能生成工作流步骤', () => {
      const types = Object.keys(NodeTypes);
      
      types.forEach((type, index) => {
        canvas.addNode(type, index * 100, 0);
      });
      
      const workflow = canvas.toWorkflowDefinition();
      
      assert.equal(workflow.steps.length, types.length);
    });

    it('所有节点类型都能在属性面板显�?, () => {
      const types = Object.keys(NodeTypes);
      
      types.forEach(type => {
        const node = canvas.addNode(type, 0, 0);
        
        assert.doesNotThrow(() => {
          properties.showNode(node);
        }, `Properties panel failed for type: ${type}`);
        
        canvas.removeNode(node.id);
      });
    });
  });

  // ============================================================================
  // Event Flow
  // ============================================================================
  
  describe('事件�?, () => {
    
    it('添加节点应触发事件链', () => {
      const events = [];
      
      canvas.events.on('nodeAdded', () => events.push('nodeAdded'));
      canvas.events.on('selectionChanged', () => events.push('selectionChanged'));
      
      const node = canvas.addNode('start', 100, 100);
      canvas.selectNode(node);
      
      assert.include(events, 'nodeAdded');
      assert.include(events, 'selectionChanged');
    });

    it('删除节点应触发事件链', () => {
      const events = [];
      
      const node1 = canvas.addNode('start', 100, 100);
      const node2 = canvas.addNode('end', 200, 200);
      canvas.addConnection(node1.id, node2.id);
      
      canvas.events.on('nodeRemoved', () => events.push('nodeRemoved'));
      canvas.events.on('connectionRemoved', () => events.push('connectionRemoved'));
      
      canvas.removeNode(node1.id);
      
      assert.include(events, 'nodeRemoved');
      assert.include(events, 'connectionRemoved');
    });
  });

  // ============================================================================
  // Edge Cases
  // ============================================================================
  
  describe('边界情况', () => {
    
    it('空工作流应正确序列化', () => {
      const json = canvas.toJSON();
      
      assert.deepEqual(json, { nodes: [], connections: [] });
      
      const workflow = canvas.toWorkflowDefinition();
      assert.equal(workflow.steps.length, 0);
    });

    it('单节点工作流应正确处�?, () => {
      const start = canvas.addNode('start', 100, 100);
      
      const json = canvas.toJSON();
      assert.equal(json.nodes.length, 1);
      assert.equal(json.connections.length, 0);
    });

    it('多次选择/取消选择不应出错', () => {
      const node = canvas.addNode('start', 100, 100);
      
      for (let i = 0; i < 10; i++) {
        canvas.selectNode(node);
        canvas.clearSelection();
      }
      
      assert.equal(canvas.selectedNodes.size, 0);
    });

    it('删除不存在的节点不应出错', () => {
      assert.doesNotThrow(() => {
        canvas.removeNode('nonexistent_id');
      });
    });

    it('删除不存在的连接不应出错', () => {
      assert.doesNotThrow(() => {
        canvas.reDeepMoveConnection('nonexistent_id');
      });
    });
  });

  // ============================================================================
  // Performance Sanity Check
  // ============================================================================
  
  describe('性能基础检�?, () => {
    
    it('应能处理 100 个节�?, () => {
      const startTime = performance.now();
      
      for (let i = 0; i < 100; i++) {
        canvas.addNode('llm', i * 10, (i % 10) * 100);
      }
      
      const duration = performance.now() - startTime;
      
      assert.equal(canvas.nodes.size, 100);
      assert.isBelow(duration, 1000, '创建 100 个节点应�?1 秒内完成');
    });

    it('应能处理大量连接', () => {
      // Create a chain of 50 nodes
      const nodes = [];
      for (let i = 0; i < 50; i++) {
        nodes.push(canvas.addNode('llm', i * 100, 0));
      }
      
      const startTime = performance.now();
      
      // Create connections
      for (let i = 0; i < nodes.length - 1; i++) {
        canvas.addConnection(nodes[i].id, nodes[i + 1].id);
      }
      
      const duration = performance.now() - startTime;
      
      assert.equal(canvas.connections.length, 49);
      assert.isBelow(duration, 500, '创建 49 条连接应�?500ms 内完�?);
    });

    it('序列化大工作流应快�?, () => {
      // Create 50 nodes
      const nodes = [];
      for (let i = 0; i < 50; i++) {
        nodes.push(canvas.addNode('llm', i * 100, 0));
      }
      
      // Create connections
      for (let i = 0; i < nodes.length - 1; i++) {
        canvas.addConnection(nodes[i].id, nodes[i + 1].id);
      }
      
      const startTime = performance.now();
      const json = canvas.toJSON();
      canvas.toWorkflowDefinition();
      const duration = performance.now() - startTime;
      
      assert.isBelow(duration, 100, '序列化应�?100ms 内完�?);
    });
  });

  // ============================================================================
  // Undo Manager Integration
  // ============================================================================
  
  describe('撤销管理器集�?, () => {
    
    it('UndoManager 应能保存画布状�?, () => {
      const undoManager = new Utils.UndoManager();
      
      // Initial state
      undoManager.push(canvas.toJSON());
      
      // Add node
      canvas.addNode('start', 100, 100);
      undoManager.push(canvas.toJSON());
      
      // Add another node
      canvas.addNode('end', 200, 200);
      undoManager.push(canvas.toJSON());
      
      assert.isTrue(undoManager.canUndo());
    });

    it('应能撤销到之前的状�?, () => {
      const undoManager = new Utils.UndoManager();
      
      undoManager.push(canvas.toJSON());
      
      canvas.addNode('start', 100, 100);
      undoManager.push(canvas.toJSON());
      
      canvas.addNode('end', 200, 200);
      undoManager.push(canvas.toJSON());
      
      assert.equal(canvas.nodes.size, 2);
      
      // Undo
      const prevState = undoManager.undo();
      canvas.fromJSON(prevState);
      
      assert.equal(canvas.nodes.size, 1);
    });
  });
});
