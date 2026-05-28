/**
 * UniFlow Workflow Editor - Canvas Controller
 */

class WorkflowCanvas {
  constructor(container) {
    this.container = container;
    this.wrapper = document.getElementById('canvasWrapper');
    this.nodesLayer = document.getElementById('nodesLayer');
    this.connectionsLayer = document.getElementById('connectionsLayer');
    
    this.nodes = new Map();
    this.connections = [];
    this.selectedNodes = new Set();
    this.selectedConnection = null;
    
    this.zoom = 1;
    this.panX = 0;
    this.panY = 0;
    
    this.isDragging = false;
    this.isPanning = false;
    this.isConnecting = false;
    this.dragOffset = { x: 0, y: 0 };
    this.connectingFrom = null;
    this.tempConnection = null;
    
    this.events = new Utils.EventEmitter();
    
    this.init();
  }

  init() {
    this.setupEventListeners();
    this.centerView();
  }

  setupEventListeners() {
    // Mouse events on canvas
    this.container.addEventListener('mousedown', this.onMouseDown.bind(this));
    this.container.addEventListener('mousemove', this.onMouseMove.bind(this));
    this.container.addEventListener('mouseup', this.onMouseUp.bind(this));
    this.container.addEventListener('wheel', this.onWheel.bind(this));
    
    // Context menu
    this.container.addEventListener('contextmenu', (e) => e.preventDefault());
    
    // Keyboard events
    document.addEventListener('keydown', this.onKeyDown.bind(this));
    
    // Drag and drop from palette
    this.container.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });
    
    this.container.addEventListener('drop', this.onDrop.bind(this));
  }

  // ============================================================================
  // View Controls
  // ============================================================================

  setZoom(zoom) {
    this.zoom = Utils.clamp(zoom, 0.25, 2);
    this.updateTransform();
    this.events.emit('zoom', this.zoom);
  }

  zoomIn() {
    this.setZoom(this.zoom * 1.2);
  }

  zoomOut() {
    this.setZoom(this.zoom / 1.2);
  }

  centerView() {
    const rect = this.container.getBoundingClientRect();
    this.panX = -2000 + rect.width / 2;
    this.panY = -2000 + rect.height / 2;
    this.updateTransform();
  }

  fitView() {
    if (this.nodes.size === 0) {
      this.centerView();
      return;
    }
    
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    
    this.nodes.forEach(node => {
      minX = Math.min(minX, node.x);
      minY = Math.min(minY, node.y);
      maxX = Math.max(maxX, node.x + 180);
      maxY = Math.max(maxY, node.y + 80);
    });
    
    const padding = 50;
    const rect = this.container.getBoundingClientRect();
    const contentWidth = maxX - minX + padding * 2;
    const contentHeight = maxY - minY + padding * 2;
    
    const scaleX = rect.width / contentWidth;
    const scaleY = rect.height / contentHeight;
    this.zoom = Utils.clamp(Math.min(scaleX, scaleY), 0.25, 1);
    
    this.panX = -(minX - padding) * this.zoom + (rect.width - contentWidth * this.zoom) / 2;
    this.panY = -(minY - padding) * this.zoom + (rect.height - contentHeight * this.zoom) / 2;
    
    this.updateTransform();
    this.events.emit('zoom', this.zoom);
  }

  updateTransform() {
    this.wrapper.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`;
  }

  screenToCanvas(x, y) {
    const rect = this.container.getBoundingClientRect();
    return {
      x: (x - rect.left - this.panX) / this.zoom,
      y: (y - rect.top - this.panY) / this.zoom
    };
  }

  // ============================================================================
  // Node Management
  // ============================================================================

  addNode(type, x, y, properties = null) {
    const nodeType = NodeTypes[type];
    if (!nodeType) return null;
    
    const node = {
      id: properties?.id || Utils.generateId(),
      type,
      x,
      y,
      properties: properties || getDefaultProperties(type)
    };
    
    this.nodes.set(node.id, node);
    this.renderNode(node);
    this.events.emit('nodeAdded', node);
    this.updateCounts();
    
    return node;
  }

  removeNode(nodeId) {
    const node = this.nodes.get(nodeId);
    if (!node) return;
    
    // Remove connected connections
    this.connections = this.connections.filter(conn => {
      if (conn.from === nodeId || conn.to === nodeId) {
        this.reDeepMoveConnectionElement(conn);
        return false;
      }
      return true;
    });
    
    // Remove node element
    const el = this.nodesLayer.querySelector(`[data-id="${nodeId}"]`);
    if (el) el.remove();
    
    this.nodes.delete(nodeId);
    this.selectedNodes.delete(nodeId);
    
    this.events.emit('nodeRemoved', node);
    this.updateCounts();
  }

  renderNode(node) {
    const nodeType = NodeTypes[node.type];
    const template = document.getElementById('nodeTemplate');
    const el = template.content.cloneNode(true).querySelector('.workflow-node');
    
    el.dataset.id = node.id;
    el.dataset.type = node.type;
    el.style.left = `${node.x}px`;
    el.style.top = `${node.y}px`;
    
    el.querySelector('.node-icon').textContent = nodeType.icon;
    el.querySelector('.node-title').textContent = node.properties.name || nodeType.label;
    el.querySelector('.node-description').textContent = nodeType.description;
    
    // Configure ports based on node type
    const portsContainer = el.querySelector('.node-ports');
    if (nodeType.maxInputs === 0) {
      portsContainer.querySelector('.node-port-in')?.remove();
    }
    if (nodeType.maxOutputs === 0) {
      portsContainer.querySelector('.node-port-out')?.remove();
    }
    
    // Event listeners
    el.addEventListener('mousedown', (e) => this.onNodeMouseDown(e, node));
    el.querySelector('.node-delete').addEventListener('click', (e) => {
      e.stopPropagation();
      this.removeNode(node.id);
    });
    
    // Port events
    el.querySelectorAll('.node-port').forEach(port => {
      port.addEventListener('mousedown', (e) => this.onPortMouseDown(e, node, port));
      port.addEventListener('mouseup', (e) => this.onPortMouseUp(e, node, port));
    });
    
    this.nodesLayer.appendChild(el);
  }

  updateNodeElement(node) {
    const el = this.nodesLayer.querySelector(`[data-id="${node.id}"]`);
    if (!el) return;
    
    const nodeType = NodeTypes[node.type];
    el.style.left = `${node.x}px`;
    el.style.top = `${node.y}px`;
    el.querySelector('.node-title').textContent = node.properties.name || nodeType.label;
  }

  // ============================================================================
  // Connection Management
  // ============================================================================

  addConnection(fromId, toId, fromPort = 'out', toPort = 'in') {
    // Validate connection
    const fromNode = this.nodes.get(fromId);
    const toNode = this.nodes.get(toId);
    
    if (!fromNode || !toNode) return null;
    if (fromId === toId) return null;
    
    // Check if connection already exists
    const exists = this.connections.some(c => 
      c.from === fromId && c.to === toId && c.fromPort === fromPort
    );
    if (exists) return null;
    
    const connection = {
      id: Utils.generateId(),
      from: fromId,
      to: toId,
      fromPort,
      toPort
    };
    
    this.connections.push(connection);
    this.renderConnection(connection);
    this.events.emit('connectionAdded', connection);
    this.updateCounts();
    
    return connection;
  }

  reDeepMoveConnection(connectionId) {
    const index = this.connections.findIndex(c => c.id === connectionId);
    if (index === -1) return;
    
    const connection = this.connections[index];
    this.reDeepMoveConnectionElement(connection);
    this.connections.splice(index, 1);
    
    this.events.emit('connectionRemoved', connection);
    this.updateCounts();
  }

  renderConnection(connection) {
    const fromNode = this.nodes.get(connection.from);
    const toNode = this.nodes.get(connection.to);
    if (!fromNode || !toNode) return;
    
    const path = this.createConnectionPath(fromNode, toNode);
    const pathEl = Utils.createSVGElement('path', {
      d: path,
      class: 'connection',
      'data-id': connection.id
    });
    
    pathEl.addEventListener('click', (e) => {
      e.stopPropagation();
      this.selectConnection(connection);
    });
    
    this.connectionsLayer.appendChild(pathEl);
  }

  reDeepMoveConnectionElement(connection) {
    const el = this.connectionsLayer.querySelector(`[data-id="${connection.id}"]`);
    if (el) el.remove();
  }

  updateConnections() {
    this.connections.forEach(conn => {
      const el = this.connectionsLayer.querySelector(`[data-id="${conn.id}"]`);
      if (!el) return;
      
      const fromNode = this.nodes.get(conn.from);
      const toNode = this.nodes.get(conn.to);
      if (!fromNode || !toNode) return;
      
      el.setAttribute('d', this.createConnectionPath(fromNode, toNode));
    });
  }

  createConnectionPath(fromNode, toNode) {
    const fromEl = this.nodesLayer.querySelector(`[data-id="${fromNode.id}"]`);
    const toEl = this.nodesLayer.querySelector(`[data-id="${toNode.id}"]`);
    
    const fromRect = { width: fromEl?.offsetWidth || 180, height: fromEl?.offsetHeight || 60 };
    const toRect = { width: toEl?.offsetWidth || 180, height: toEl?.offsetHeight || 60 };
    
    const x1 = fromNode.x + fromRect.width / 2;
    const y1 = fromNode.y + fromRect.height;
    const x2 = toNode.x + toRect.width / 2;
    const y2 = toNode.y;
    
    return Utils.createConnectionPath(x1, y1, x2, y2);
  }

  // ============================================================================
  // Selection
  // ============================================================================

  selectNode(node, addToSelection = false) {
    if (!addToSelection) {
      this.clearSelection();
    }
    
    this.selectedNodes.add(node.id);
    const el = this.nodesLayer.querySelector(`[data-id="${node.id}"]`);
    if (el) el.classList.add('selected');
    
    this.events.emit('selectionChanged', this.getSelectedNodes());
  }

  deselectNode(nodeId) {
    this.selectedNodes.delete(nodeId);
    const el = this.nodesLayer.querySelector(`[data-id="${nodeId}"]`);
    if (el) el.classList.remove('selected');
    
    this.events.emit('selectionChanged', this.getSelectedNodes());
  }

  selectConnection(connection) {
    this.clearSelection();
    this.selectedConnection = connection;
    
    const el = this.connectionsLayer.querySelector(`[data-id="${connection.id}"]`);
    if (el) el.classList.add('selected');
  }

  clearSelection() {
    this.selectedNodes.forEach(id => {
      const el = this.nodesLayer.querySelector(`[data-id="${id}"]`);
      if (el) el.classList.remove('selected');
    });
    this.selectedNodes.clear();
    
    if (this.selectedConnection) {
      const el = this.connectionsLayer.querySelector(`[data-id="${this.selectedConnection.id}"]`);
      if (el) el.classList.remove('selected');
      this.selectedConnection = null;
    }
    
    this.events.emit('selectionChanged', []);
  }

  getSelectedNodes() {
    return Array.from(this.selectedNodes).map(id => this.nodes.get(id)).filter(Boolean);
  }

  // ============================================================================
  // Event Handlers
  // ============================================================================

  onMouseDown(e) {
    if (e.target === this.container || e.target === this.wrapper) {
      this.clearSelection();
      
      if (e.button === 0 || e.button === 1) {
        this.isPanning = true;
        this.dragOffset = { x: e.clientX - this.panX, y: e.clientY - this.panY };
      }
    }
  }

  onMouseMove(e) {
    if (this.isPanning) {
      this.panX = e.clientX - this.dragOffset.x;
      this.panY = e.clientY - this.dragOffset.y;
      this.updateTransform();
    }
    
    if (this.isDragging && this.selectedNodes.size > 0) {
      const pos = this.screenToCanvas(e.clientX, e.clientY);
      
      this.selectedNodes.forEach(id => {
        const node = this.nodes.get(id);
        if (node) {
          node.x = pos.x - this.dragOffset.x;
          node.y = pos.y - this.dragOffset.y;
          this.updateNodeElement(node);
        }
      });
      
      this.updateConnections();
    }
    
    if (this.isConnecting && this.tempConnection) {
      const pos = this.screenToCanvas(e.clientX, e.clientY);
      const fromNode = this.nodes.get(this.connectingFrom.nodeId);
      const fromEl = this.nodesLayer.querySelector(`[data-id="${fromNode.id}"]`);
      
      const x1 = fromNode.x + (fromEl?.offsetWidth || 180) / 2;
      const y1 = fromNode.y + (fromEl?.offsetHeight || 60);
      
      this.tempConnection.setAttribute('d', Utils.createConnectionPath(x1, y1, pos.x, pos.y));
    }
  }

  onMouseUp(e) {
    this.isPanning = false;
    this.isDragging = false;
    
    if (this.isConnecting) {
      if (this.tempConnection) {
        this.tempConnection.remove();
        this.tempConnection = null;
      }
      this.isConnecting = false;
      this.connectingFrom = null;
    }
  }

  onWheel(e) {
    e.preventDefault();
    const delta = e.deltaY > 0 ? 0.9 : 1.1;
    this.setZoom(this.zoom * delta);
  }

  onKeyDown(e) {
    if (e.key === 'Delete' || e.key === 'Backspace') {
      if (this.selectedConnection) {
        this.reDeepMoveConnection(this.selectedConnection.id);
      }
      this.selectedNodes.forEach(id => this.removeNode(id));
    }
    
    if (e.key === 'Escape') {
      this.clearSelection();
    }
  }

  onNodeMouseDown(e, node) {
    e.stopPropagation();
    
    if (!this.selectedNodes.has(node.id)) {
      this.selectNode(node, e.shiftKey || e.ctrlKey);
    }
    
    this.isDragging = true;
    const pos = this.screenToCanvas(e.clientX, e.clientY);
    this.dragOffset = { x: pos.x - node.x, y: pos.y - node.y };
  }

  onPortMouseDown(e, node, port) {
    e.stopPropagation();
    
    if (port.dataset.port === 'out') {
      this.isConnecting = true;
      this.connectingFrom = { nodeId: node.id, port: port.dataset.port };
      
      const fromEl = this.nodesLayer.querySelector(`[data-id="${node.id}"]`);
      const x = node.x + (fromEl?.offsetWidth || 180) / 2;
      const y = node.y + (fromEl?.offsetHeight || 60);
      
      this.tempConnection = Utils.createSVGElement('path', {
        d: `M ${x} ${y} L ${x} ${y}`,
        class: 'connection-temp'
      });
      this.connectionsLayer.appendChild(this.tempConnection);
    }
  }

  onPortMouseUp(e, node, port) {
    if (this.isConnecting && this.connectingFrom && port.dataset.port === 'in') {
      this.addConnection(this.connectingFrom.nodeId, node.id);
    }
  }

  onDrop(e) {
    e.preventDefault();
    
    const type = e.dataTransfer.getData('text/plain');
    if (!type || !NodeTypes[type]) return;
    
    const pos = this.screenToCanvas(e.clientX, e.clientY);
    const node = this.addNode(type, pos.x - 90, pos.y - 30);
    
    if (node) {
      this.selectNode(node);
    }
  }

  // ============================================================================
  // Serialization
  // ============================================================================

  toJSON() {
    return {
      nodes: Array.from(this.nodes.values()),
      connections: this.connections
    };
  }

  fromJSON(data) {
    this.clear();
    
    if (data.nodes) {
      data.nodes.forEach(node => {
        this.addNode(node.type, node.x, node.y, node.properties);
      });
    }
    
    if (data.connections) {
      data.connections.forEach(conn => {
        this.addConnection(conn.from, conn.to, conn.fromPort, conn.toPort);
      });
    }
    
    this.fitView();
  }

  toWorkflowDefinition() {
    const steps = [];
    
    this.nodes.forEach(node => {
      const nodeType = NodeTypes[node.type];
      if (nodeType.toWorkflowStep) {
        steps.push(nodeType.toWorkflowStep(node, this.connections));
      }
    });
    
    // Build next_step relationships from connections
    this.connections.forEach(conn => {
      const step = steps.find(s => s.id === conn.from);
      if (step) {
        step.next_step = conn.to;
      }
    });
    
    return {
      id: Utils.generateId(),
      name: 'Untitled Workflow',
      version: '1.0.0',
      steps
    };
  }

  clear() {
    this.nodes.forEach((_, id) => this.removeNode(id));
    this.connections = [];
    this.clearSelection();
    this.updateCounts();
  }

  updateCounts() {
    document.getElementById('nodeCount').textContent = `${this.nodes.size} 个节点`;
    document.getElementById('connectionCount').textContent = `${this.connections.length} 条连接`;
  }
}

// Export
window.WorkflowCanvas = WorkflowCanvas;
