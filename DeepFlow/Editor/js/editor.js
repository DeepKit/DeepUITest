/**
 * UniFlow Workflow Editor - Main Editor
 */

class WorkflowEditor {
  constructor() {
    this.canvas = null;
    this.properties = null;
    this.undoManager = new Utils.UndoManager(50);
    
    this.workflowName = 'Untitled Workflow';
    this.workflowVersion = '1.0.0';
    this.isDirty = false;
    
    this.init();
  }

  init() {
    // Initialize canvas
    const canvasContainer = document.getElementById('canvas');
    this.canvas = new WorkflowCanvas(canvasContainer);
    
    // Initialize properties panel
    const propertiesPanel = document.getElementById('propertiesPanel');
    this.properties = new PropertiesPanel(propertiesPanel);
    
    // Wire up events
    this.setupCanvasEvents();
    this.setupToolbarEvents();
    this.setupPaletteEvents();
    this.setupKeyboardShortcuts();
    this.setupPropertyEvents();
    
    // Load from localStorage if available
    this.loadFromLocalStorage();
    
    // Update UI
    this.updateZoomDisplay();
  }

  // ============================================================================
  // Event Setup
  // ============================================================================

  setupCanvasEvents() {
    this.canvas.events.on('selectionChanged', (nodes) => {
      if (nodes.length === 1) {
        this.properties.showNode(nodes[0]);
      } else {
        this.properties.showEmpty();
      }
    });
    
    this.canvas.events.on('nodeAdded', () => {
      this.markDirty();
      this.saveState();
    });
    
    this.canvas.events.on('nodeRemoved', () => {
      this.markDirty();
      this.saveState();
    });
    
    this.canvas.events.on('connectionAdded', () => {
      this.markDirty();
      this.saveState();
    });
    
    this.canvas.events.on('connectionRemoved', () => {
      this.markDirty();
      this.saveState();
    });
    
    this.canvas.events.on('zoom', (zoom) => {
      this.updateZoomDisplay();
    });
  }

  setupToolbarEvents() {
    // File operations
    document.getElementById('btnNew').addEventListener('click', () => this.newWorkflow());
    document.getElementById('btnOpen').addEventListener('click', () => this.openWorkflow());
    document.getElementById('btnSave').addEventListener('click', () => this.saveWorkflow());
    document.getElementById('btnExport').addEventListener('click', () => this.exportWorkflow());
    
    // Edit operations
    document.getElementById('btnUndo').addEventListener('click', () => this.undo());
    document.getElementById('btnRedo').addEventListener('click', () => this.redo());
    
    // View operations
    document.getElementById('btnZoomIn').addEventListener('click', () => this.canvas.zoomIn());
    document.getElementById('btnZoomOut').addEventListener('click', () => this.canvas.zoomOut());
    document.getElementById('btnFitView').addEventListener('click', () => this.canvas.fitView());
  }

  setupPaletteEvents() {
    document.querySelectorAll('.palette-item').forEach(item => {
      item.addEventListener('dragstart', (e) => {
        e.dataTransfer.setData('text/plain', item.dataset.type);
        e.dataTransfer.effectAllowed = 'copy';
      });
      
      item.addEventListener('dblclick', () => {
        const rect = this.canvas.container.getBoundingClientRect();
        const pos = this.canvas.screenToCanvas(
          rect.left + rect.width / 2,
          rect.top + rect.height / 2
        );
        const node = this.canvas.addNode(item.dataset.type, pos.x - 90, pos.y - 30);
        if (node) {
          this.canvas.selectNode(node);
        }
      });
    });
    
    // Palette section collapse
    document.querySelectorAll('.palette-section-header').forEach(header => {
      header.addEventListener('click', () => {
        const section = header.parentElement;
        section.classList.toggle('collapsed');
      });
    });
  }

  setupKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Ignore if focused on input
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      
      // Ctrl/Cmd shortcuts
      if (e.ctrlKey || e.metaKey) {
        switch (e.key.toLowerCase()) {
          case 'n':
            e.preventDefault();
            this.newWorkflow();
            break;
          case 'o':
            e.preventDefault();
            this.openWorkflow();
            break;
          case 's':
            e.preventDefault();
            if (e.shiftKey) {
              this.exportWorkflow();
            } else {
              this.saveWorkflow();
            }
            break;
          case 'z':
            e.preventDefault();
            if (e.shiftKey) {
              this.redo();
            } else {
              this.undo();
            }
            break;
          case 'y':
            e.preventDefault();
            this.redo();
            break;
          case '0':
            e.preventDefault();
            this.canvas.fitView();
            break;
          case '=':
          case '+':
            e.preventDefault();
            this.canvas.zoomIn();
            break;
          case '-':
            e.preventDefault();
            this.canvas.zoomOut();
            break;
        }
      }
    });
  }

  setupPropertyEvents() {
    this.properties.onChange = (node, propName, value) => {
      this.canvas.updateNodeElement(node);
      this.markDirty();
      this.saveStateDebounced();
    };
  }

  // ============================================================================
  // File Operations
  // ============================================================================

  newWorkflow() {
    if (this.isDirty) {
      if (!confirm('当前工作流有未保存的更改。确定要创建新工作流吗？')) {
        return;
      }
    }
    
    this.canvas.clear();
    this.workflowName = 'Untitled Workflow';
    this.workflowVersion = '1.0.0';
    this.isDirty = false;
    this.undoManager.clear();
    this.properties.showEmpty();
    this.updateStatus('已创建新工作�?);
    
    localStorage.removeItem('uniflow_editor_workflow');
  }

  openWorkflow() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json';
    
    input.onchange = async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      
      try {
        const text = await file.text();
        const data = JSON.parse(text);
        this.loadWorkflow(data);
        this.updateStatus(`已加�? ${file.name}`);
      } catch (error) {
        this.updateStatus(`加载失败: ${error.message}`, true);
      }
    };
    
    input.click();
  }

  loadWorkflow(data) {
    if (data.editor) {
      // Editor format
      this.canvas.fromJSON(data.editor);
      this.workflowName = data.name || 'Untitled Workflow';
      this.workflowVersion = data.version || '1.0.0';
    } else if (data.steps) {
      // Workflow definition format - convert to editor format
      this.importWorkflowDefinition(data);
    } else if (data.nodes) {
      // Direct canvas format
      this.canvas.fromJSON(data);
    }
    
    this.isDirty = false;
    this.undoManager.clear();
    this.saveState();
  }

  saveWorkflow() {
    const data = {
      name: this.workflowName,
      version: this.workflowVersion,
      savedAt: new Date().toISOString(),
      editor: this.canvas.toJSON()
    };
    
    // Save to localStorage
    localStorage.setItem('uniflow_editor_workflow', JSON.stringify(data));
    
    this.isDirty = false;
    this.updateStatus('已保存到浏览�?);
  }

  exportWorkflow() {
    // Export as workflow definition JSON
    const workflow = this.canvas.toWorkflowDefinition();
    workflow.name = this.workflowName;
    workflow.version = this.workflowVersion;
    
    const blob = new Blob([JSON.stringify(workflow, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = `${this.workflowName.replace(/\s+/g, '_')}.json`;
    a.click();
    
    URL.revokeObjectURL(url);
    this.updateStatus('已导出工作流定义');
  }

  importWorkflowDefinition(workflow) {
    // Convert workflow definition to editor format
    this.canvas.clear();
    
    const stepPositions = new Map();
    let y = 100;
    
    // First pass: create nodes
    workflow.steps.forEach((step, index) => {
      const nodeType = this.mapStepTypeToNodeType(step.type);
      if (!nodeType) return;
      
      const x = 200 + (index % 3) * 250;
      const node = this.canvas.addNode(nodeType, x, y);
      
      if (node) {
        node.properties = { ...node.properties, ...this.extractStepProperties(step) };
        stepPositions.set(step.id, node.id);
      }
      
      if ((index + 1) % 3 === 0) y += 120;
    });
    
    // Second pass: create connections
    workflow.steps.forEach(step => {
      if (step.next_step && stepPositions.has(step.id) && stepPositions.has(step.next_step)) {
        this.canvas.addConnection(stepPositions.get(step.id), stepPositions.get(step.next_step));
      }
    });
    
    this.workflowName = workflow.name || 'Imported Workflow';
    this.workflowVersion = workflow.version || '1.0.0';
    
    this.canvas.fitView();
  }

  mapStepTypeToNodeType(stepType) {
    const mapping = {
      'start': 'start',
      'end': 'end',
      'llm': 'llm',
      'skill': 'skill',
      'http': 'http',
      'script': 'script',
      'assign': 'assign',
      'log': 'log',
      'condition': 'condition',
      'loop': 'loop',
      'parallel': 'parallel',
      'wait': 'wait',
      'subworkflow': 'subworkflow',
      'guard': 'guard'
    };
    return mapping[stepType] || stepType;
  }

  extractStepProperties(step) {
    const props = { name: step.name || step.id };
    
    // Copy relevant properties
    const copyKeys = ['prompt', 'model', 'provider', 'skill_name', 'skill_params',
                      'url', 'method', 'headers', 'body', 'script', 'language',
                      'assignments', 'message', 'level', 'condition', 'branches',
                      'items', 'iterator', 'duration', 'wait_for', 'workflow_id',
                      'rules', 'action'];
    
    copyKeys.forEach(key => {
      if (step[key] !== undefined) props[key] = step[key];
    });
    
    return props;
  }

  loadFromLocalStorage() {
    const saved = localStorage.getItem('uniflow_editor_workflow');
    if (saved) {
      try {
        const data = JSON.parse(saved);
        this.loadWorkflow(data);
        this.updateStatus('已恢复上次编�?);
      } catch {
        // Ignore
      }
    }
  }

  // ============================================================================
  // Undo/Redo
  // ============================================================================

  saveState() {
    const state = this.canvas.toJSON();
    this.undoManager.push(state);
  }

  saveStateDebounced = Utils.debounce(() => {
    this.saveState();
  }, 500);

  undo() {
    const state = this.undoManager.undo();
    if (state) {
      this.canvas.fromJSON(state);
      this.properties.showEmpty();
      this.updateStatus('撤销');
    }
  }

  redo() {
    const state = this.undoManager.redo();
    if (state) {
      this.canvas.fromJSON(state);
      this.properties.showEmpty();
      this.updateStatus('重做');
    }
  }

  // ============================================================================
  // UI Updates
  // ============================================================================

  markDirty() {
    this.isDirty = true;
  }

  updateZoomDisplay() {
    document.getElementById('zoomLevel').textContent = `${Math.round(this.canvas.zoom * 100)}%`;
  }

  updateStatus(message, isError = false) {
    const statusEl = document.getElementById('statusMessage');
    statusEl.textContent = message;
    statusEl.style.color = isError ? 'var(--color-red)' : '';
    
    // Clear after 3 seconds
    setTimeout(() => {
      statusEl.textContent = '就绪';
      statusEl.style.color = '';
    }, 3000);
  }
}

// Initialize editor when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.editor = new WorkflowEditor();
});
