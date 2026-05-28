/**
 * UniFlow Editor - Canvas Module Tests
 */

describe('WorkflowCanvas - 画布控制器测�?, () => {
  let canvas;
  let container;
  
  beforeEach(() => {
    // Use mock canvas container
    container = document.getElementById('mockCanvas');
    canvas = new WorkflowCanvas(container);
  });
  
  afterEach(() => {
    // Clear canvas
    if (canvas) {
      canvas.clear();
    }
    // Reset DOM
    document.getElementById('nodesLayer').innerHTML = '';
    document.getElementById('connectionsLayer').innerHTML = '';
  });

  // ============================================================================
  // Initialization
  // ============================================================================
  
  it('应正确初始化画布', () => {
    assert.isDefined(canvas.nodes);
    assert.isDefined(canvas.connections);
    assert.instanceOf(canvas.nodes, Map);
    assert.isArray(canvas.connections);
    assert.equal(canvas.zoom, 1);
  });

  it('应有事件发射�?, () => {
    assert.isDefined(canvas.events);
    assert.isFunction(canvas.events.on);
    assert.isFunction(canvas.events.emit);
  });

  // ============================================================================
  // Node Management
  // ============================================================================
  
  describe('节点管理', () => {
    
    it('addNode() 应添加新节点', () => {
      const node = canvas.addNode('start', 100, 100);
      
      assert.isDefined(node);
      assert.equal(node.type, 'start');
      assert.equal(node.x, 100);
      assert.equal(node.y, 100);
      assert.equal(canvas.nodes.size, 1);
    });

    it('addNode() 应为节点分配唯一 ID', () => {
      const node1 = canvas.addNode('start', 0, 0);
      const node2 = canvas.addNode('end', 100, 100);
      
      assert.notEqual(node1.id, node2.id);
    });

    it('addNode() 应为节点设置默认属�?, () => {
      const node = canvas.addNode('llm', 0, 0);
      
      assert.isDefined(node.properties);
      assert.isDefined(node.properties.name);
      assert.isDefined(node.properties.provider);
    });

    it('addNode() 应接受自定义属�?, () => {
      const props = { id: 'custom_id', name: '自定义节�? };
      const node = canvas.addNode('start', 0, 0, props);
      
      assert.equal(node.properties.id, 'custom_id');
      assert.equal(node.properties.name, '自定义节�?);
    });

    it('addNode() 对于未知类型应返�?null', () => {
      const node = canvas.addNode('unknown_type', 0, 0);
      
      assert.isNull(node);
    });

    it('addNode() 应触�?nodeAdded 事件', () => {
      let eventFired = false;
      let eventNode = null;
      
      canvas.events.on('nodeAdded', (node) => {
        eventFired = true;
        eventNode = node;
      });
      
      const node = canvas.addNode('start', 0, 0);
      
      assert.isTrue(eventFired);
      assert.equal(eventNode, node);
    });

    it('removeNode() 应移除节�?, () => {
      const node = canvas.addNode('start', 0, 0);
      canvas.removeNode(node.id);
      
      assert.equal(canvas.nodes.size, 0);
    });

    it('removeNode() 应触�?nodeRemoved 事件', () => {
      let eventFired = false;
      
      canvas.events.on('nodeRemoved', () => {
        eventFired = true;
      });
      
      const node = canvas.addNode('start', 0, 0);
      canvas.removeNode(node.id);
      
      assert.isTrue(eventFired);
    });

    it('removeNode() 应同时移除相关连�?, () => {
      const node1 = canvas.addNode('start', 0, 0);
      const node2 = canvas.addNode('end', 100, 100);
      canvas.addConnection(node1.id, node2.id);
      
      assert.equal(canvas.connections.length, 1);
      
      canvas.removeNode(node1.id);
      
      assert.equal(canvas.connections.length, 0);
    });
  });

  // ============================================================================
  // Connection Management
  // ============================================================================
  
  describe('连接管理', () => {
    let node1, node2, node3;
    
    beforeEach(() => {
      node1 = canvas.addNode('start', 0, 0);
      node2 = canvas.addNode('llm', 100, 100);
      node3 = canvas.addNode('end', 200, 200);
    });

    it('addConnection() 应添加连�?, () => {
      const conn = canvas.addConnection(node1.id, node2.id);
      
      assert.isDefined(conn);
      assert.equal(conn.from, node1.id);
      assert.equal(conn.to, node2.id);
      assert.equal(canvas.connections.length, 1);
    });

    it('addConnection() 应分配唯一 ID', () => {
      const conn1 = canvas.addConnection(node1.id, node2.id);
      const conn2 = canvas.addConnection(node2.id, node3.id);
      
      assert.notEqual(conn1.id, conn2.id);
    });

    it('addConnection() 不应创建自环', () => {
      const conn = canvas.addConnection(node1.id, node1.id);
      
      assert.isNull(conn);
      assert.equal(canvas.connections.length, 0);
    });

    it('addConnection() 不应创建重复连接', () => {
      canvas.addConnection(node1.id, node2.id);
      const duplicate = canvas.addConnection(node1.id, node2.id);
      
      assert.isNull(duplicate);
      assert.equal(canvas.connections.length, 1);
    });

    it('addConnection() 对于不存在的节点应返�?null', () => {
      const conn = canvas.addConnection(node1.id, 'nonexistent');
      
      assert.isNull(conn);
    });

    it('addConnection() 应触�?connectionAdded 事件', () => {
      let eventFired = false;
      
      canvas.events.on('connectionAdded', () => {
        eventFired = true;
      });
      
      canvas.addConnection(node1.id, node2.id);
      
      assert.isTrue(eventFired);
    });

    it('reDeepMoveConnection() 应移除连�?, () => {
      const conn = canvas.addConnection(node1.id, node2.id);
      canvas.reDeepMoveConnection(conn.id);
      
      assert.equal(canvas.connections.length, 0);
    });

    it('reDeepMoveConnection() 应触�?connectionRemoved 事件', () => {
      let eventFired = false;
      
      canvas.events.on('connectionRemoved', () => {
        eventFired = true;
      });
      
      const conn = canvas.addConnection(node1.id, node2.id);
      canvas.reDeepMoveConnection(conn.id);
      
      assert.isTrue(eventFired);
    });
  });

  // ============================================================================
  // Selection
  // ============================================================================
  
  describe('选择功能', () => {
    let node1, node2;
    
    beforeEach(() => {
      node1 = canvas.addNode('start', 0, 0);
      node2 = canvas.addNode('end', 100, 100);
    });

    it('selectNode() 应选中节点', () => {
      canvas.selectNode(node1);
      
      assert.isTrue(canvas.selectedNodes.has(node1.id));
    });

    it('selectNode() 默认应清除之前的选择', () => {
      canvas.selectNode(node1);
      canvas.selectNode(node2);
      
      assert.isFalse(canvas.selectedNodes.has(node1.id));
      assert.isTrue(canvas.selectedNodes.has(node2.id));
    });

    it('selectNode() 应支持多�?, () => {
      canvas.selectNode(node1);
      canvas.selectNode(node2, true);
      
      assert.isTrue(canvas.selectedNodes.has(node1.id));
      assert.isTrue(canvas.selectedNodes.has(node2.id));
    });

    it('deselectNode() 应取消选中', () => {
      canvas.selectNode(node1);
      canvas.deselectNode(node1.id);
      
      assert.isFalse(canvas.selectedNodes.has(node1.id));
    });

    it('clearSelection() 应清除所有选择', () => {
      canvas.selectNode(node1);
      canvas.selectNode(node2, true);
      canvas.clearSelection();
      
      assert.equal(canvas.selectedNodes.size, 0);
    });

    it('getSelectedNodes() 应返回选中的节�?, () => {
      canvas.selectNode(node1);
      canvas.selectNode(node2, true);
      
      const selected = canvas.getSelectedNodes();
      
      assert.equal(selected.length, 2);
    });

    it('selectNode() 应触�?selectionChanged 事件', () => {
      let eventData = null;
      
      canvas.events.on('selectionChanged', (nodes) => {
        eventData = nodes;
      });
      
      canvas.selectNode(node1);
      
      assert.isArray(eventData);
      assert.equal(eventData.length, 1);
    });
  });

  // ============================================================================
  // View Controls
  // ============================================================================
  
  describe('视图控制', () => {
    
    it('setZoom() 应设置缩放级�?, () => {
      canvas.setZoom(1.5);
      
      assert.equal(canvas.zoom, 1.5);
    });

    it('setZoom() 应限制最小�?, () => {
      canvas.setZoom(0.1);
      
      assert.equal(canvas.zoom, 0.25);
    });

    it('setZoom() 应限制最大�?, () => {
      canvas.setZoom(5);
      
      assert.equal(canvas.zoom, 2);
    });

    it('zoomIn() 应增大缩�?, () => {
      const initialZoom = canvas.zoom;
      canvas.zoomIn();
      
      assert.isAbove(canvas.zoom, initialZoom);
    });

    it('zoomOut() 应减小缩�?, () => {
      const initialZoom = canvas.zoom;
      canvas.zoomOut();
      
      assert.isBelow(canvas.zoom, initialZoom);
    });

    it('setZoom() 应触�?zoom 事件', () => {
      let eventValue = null;
      
      canvas.events.on('zoom', (zoom) => {
        eventValue = zoom;
      });
      
      canvas.setZoom(1.5);
      
      assert.equal(eventValue, 1.5);
    });

    it('screenToCanvas() 应转换坐�?, () => {
      canvas.panX = 100;
      canvas.panY = 50;
      canvas.zoom = 2;
      
      // Mock container getBoundingClientRect
      const originalRect = container.getBoundingClientRect;
      container.getBoundingClientRect = () => ({ left: 0, top: 0, width: 800, height: 600 });
      
      const pos = canvas.screenToCanvas(200, 100);
      
      // (200 - 0 - 100) / 2 = 50, (100 - 0 - 50) / 2 = 25
      assert.equal(pos.x, 50);
      assert.equal(pos.y, 25);
      
      container.getBoundingClientRect = originalRect;
    });
  });

  // ============================================================================
  // Serialization
  // ============================================================================
  
  describe('序列�?, () => {
    
    it('toJSON() 应导出节点和连接', () => {
      const node1 = canvas.addNode('start', 0, 0);
      const node2 = canvas.addNode('end', 100, 100);
      canvas.addConnection(node1.id, node2.id);
      
      const json = canvas.toJSON();
      
      assert.isArray(json.nodes);
      assert.isArray(json.connections);
      assert.equal(json.nodes.length, 2);
      assert.equal(json.connections.length, 1);
    });

    it('fromJSON() 应导入节点和连接', () => {
      const data = {
        nodes: [
          { type: 'start', x: 0, y: 0, properties: { id: 'n1', name: 'Start' } },
          { type: 'end', x: 100, y: 100, properties: { id: 'n2', name: 'End' } }
        ],
        connections: [
          { from: 'n1', to: 'n2', fromPort: 'out', toPort: 'in' }
        ]
      };
      
      canvas.fromJSON(data);
      
      assert.equal(canvas.nodes.size, 2);
      assert.equal(canvas.connections.length, 1);
    });

    it('toWorkflowDefinition() 应生成工作流定义', () => {
      const start = canvas.addNode('start', 0, 0);
      const llm = canvas.addNode('llm', 100, 100);
      const end = canvas.addNode('end', 200, 200);
      
      canvas.addConnection(start.id, llm.id);
      canvas.addConnection(llm.id, end.id);
      
      const workflow = canvas.toWorkflowDefinition();
      
      assert.isDefined(workflow.id);
      assert.isDefined(workflow.name);
      assert.isDefined(workflow.version);
      assert.isArray(workflow.steps);
      assert.equal(workflow.steps.length, 3);
    });

    it('toWorkflowDefinition() 应设�?next_step 关系', () => {
      const start = canvas.addNode('start', 0, 0);
      const end = canvas.addNode('end', 100, 100);
      canvas.addConnection(start.id, end.id);
      
      const workflow = canvas.toWorkflowDefinition();
      const startStep = workflow.steps.find(s => s.id === start.id);
      
      assert.equal(startStep.next_step, end.id);
    });
  });

  // ============================================================================
  // Clear
  // ============================================================================
  
  describe('清空功能', () => {
    
    it('clear() 应移除所有节点和连接', () => {
      canvas.addNode('start', 0, 0);
      canvas.addNode('end', 100, 100);
      
      canvas.clear();
      
      assert.equal(canvas.nodes.size, 0);
      assert.equal(canvas.connections.length, 0);
    });

    it('clear() 应清除选择', () => {
      const node = canvas.addNode('start', 0, 0);
      canvas.selectNode(node);
      
      canvas.clear();
      
      assert.equal(canvas.selectedNodes.size, 0);
    });
  });
});
