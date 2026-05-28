/**
 * UniFlow Editor - Utils Module Tests
 */

describe('Utils - 工具函数测试', () => {
  
  // ============================================================================
  // generateId()
  // ============================================================================
  
  it('generateId() 应生成唯一 ID', () => {
    const id1 = Utils.generateId();
    const id2 = Utils.generateId();
    
    assert.isString(id1);
    assert.isString(id2);
    assert.notEqual(id1, id2, 'IDs should be unique');
    assert.ok(id1.startsWith('node_'), 'ID should start with "node_"');
  });

  it('generateId() 返回�?ID 应包含时间戳和随机部�?, () => {
    const id = Utils.generateId();
    
    // Format: node_<timestamp36>_<random>
    assert.match(id, /^node_[a-z0-9]+$/);
    assert.isAbove(id.length, 10, 'ID should be reasonably long');
  });

  // ============================================================================
  // deepClone()
  // ============================================================================
  
  it('deepClone() 应深度克隆对�?, () => {
    const original = {
      name: 'test',
      nested: { value: 42, items: [1, 2, 3] },
      arr: [{ id: 1 }, { id: 2 }]
    };
    
    const cloned = Utils.deepClone(original);
    
    assert.deepEqual(cloned, original);
    assert.notEqual(cloned, original, 'Should be different reference');
    assert.notEqual(cloned.nested, original.nested);
    assert.notEqual(cloned.arr, original.arr);
  });

  it('deepClone() 修改克隆不应影响原对�?, () => {
    const original = { nested: { value: 1 } };
    const cloned = Utils.deepClone(original);
    
    cloned.nested.value = 999;
    
    assert.equal(original.nested.value, 1);
    assert.equal(cloned.nested.value, 999);
  });

  it('deepClone() 应正确克隆数�?, () => {
    const original = [1, [2, 3], { a: 4 }];
    const cloned = Utils.deepClone(original);
    
    assert.deepEqual(cloned, original);
    assert.notEqual(cloned[1], original[1]);
    assert.notEqual(cloned[2], original[2]);
  });

  // ============================================================================
  // debounce()
  // ============================================================================
  
  it('debounce() 应延迟执行函�?, async () => {
    let callCount = 0;
    const fn = Utils.debounce(() => callCount++, 50);
    
    fn();
    fn();
    fn();
    
    assert.equal(callCount, 0, 'Should not be called immediately');
    
    await new Promise(r => setTimeout(r, 100));
    
    assert.equal(callCount, 1, 'Should be called once after delay');
  });

  it('debounce() 应重置延迟计�?, async () => {
    let callCount = 0;
    const fn = Utils.debounce(() => callCount++, 50);
    
    fn();
    await new Promise(r => setTimeout(r, 30));
    fn(); // Reset timer
    await new Promise(r => setTimeout(r, 30));
    
    assert.equal(callCount, 0, 'Timer should be reset');
    
    await new Promise(r => setTimeout(r, 50));
    assert.equal(callCount, 1);
  });

  // ============================================================================
  // throttle()
  // ============================================================================
  
  it('throttle() 应限制函数调用频�?, async () => {
    let callCount = 0;
    const fn = Utils.throttle(() => callCount++, 50);
    
    fn(); // Call immediately
    fn(); // Ignored
    fn(); // Ignored
    
    assert.equal(callCount, 1, 'Should call immediately once');
    
    await new Promise(r => setTimeout(r, 60));
    fn();
    
    assert.equal(callCount, 2);
  });

  // ============================================================================
  // clamp()
  // ============================================================================
  
  it('clamp() 应限制值在范围�?, () => {
    assert.equal(Utils.clamp(5, 0, 10), 5);
    assert.equal(Utils.clamp(-5, 0, 10), 0);
    assert.equal(Utils.clamp(15, 0, 10), 10);
    assert.equal(Utils.clamp(0, 0, 10), 0);
    assert.equal(Utils.clamp(10, 0, 10), 10);
  });

  // ============================================================================
  // distance()
  // ============================================================================
  
  it('distance() 应计算两点间距离', () => {
    assert.equal(Utils.distance(0, 0, 3, 4), 5);
    assert.equal(Utils.distance(0, 0, 0, 0), 0);
    assert.approximately(Utils.distance(0, 0, 1, 1), Math.SQRT2, 0.0001);
  });

  // ============================================================================
  // pointInRect()
  // ============================================================================
  
  it('pointInRect() 应正确判断点是否在矩形内', () => {
    const rect = { x: 10, y: 10, width: 100, height: 50 };
    
    assert.isTrue(Utils.pointInRect(50, 30, rect), 'Center point');
    assert.isTrue(Utils.pointInRect(10, 10, rect), 'Top-left corner');
    assert.isTrue(Utils.pointInRect(110, 60, rect), 'Bottom-right corner');
    assert.isFalse(Utils.pointInRect(5, 30, rect), 'Outside left');
    assert.isFalse(Utils.pointInRect(50, 5, rect), 'Outside top');
    assert.isFalse(Utils.pointInRect(115, 30, rect), 'Outside right');
    assert.isFalse(Utils.pointInRect(50, 65, rect), 'Outside bottom');
  });

  // ============================================================================
  // createSVGElement()
  // ============================================================================
  
  it('createSVGElement() 应创�?SVG 元素', () => {
    const el = Utils.createSVGElement('path', {
      d: 'M 0 0 L 10 10',
      class: 'test-path',
      stroke: 'red'
    });
    
    assert.equal(el.tagName.toLowerCase(), 'path');
    assert.equal(el.getAttribute('d'), 'M 0 0 L 10 10');
    assert.equal(el.getAttribute('class'), 'test-path');
    assert.equal(el.getAttribute('stroke'), 'red');
    assert.equal(el.namespaceURI, 'http://www.w3.org/2000/svg');
  });

  // ============================================================================
  // createConnectionPath()
  // ============================================================================
  
  it('createConnectionPath() 应创建贝塞尔曲线路径', () => {
    const path = Utils.createConnectionPath(0, 0, 100, 100);
    
    assert.isString(path);
    assert.ok(path.startsWith('M '), 'Should start with M command');
    assert.include(path, 'C ', 'Should contain C command for curve');
  });

  it('createConnectionPath() 路径应从起点到终�?, () => {
    const path = Utils.createConnectionPath(10, 20, 110, 120);
    
    assert.ok(path.startsWith('M 10 20'), 'Should start at origin');
    assert.ok(path.endsWith('110 120'), 'Should end at destination');
  });

  // ============================================================================
  // EventEmitter
  // ============================================================================
  
  describe('EventEmitter', () => {
    let emitter;
    
    beforeEach(() => {
      emitter = new Utils.EventEmitter();
    });

    it('应注册和触发事件', () => {
      let received = null;
      emitter.on('test', (data) => received = data);
      
      emitter.emit('test', 'hello');
      
      assert.equal(received, 'hello');
    });

    it('应支持多个监听器', () => {
      let count = 0;
      emitter.on('test', () => count++);
      emitter.on('test', () => count++);
      
      emitter.emit('test');
      
      assert.equal(count, 2);
    });

    it('off() 应移除监听器', () => {
      let count = 0;
      const listener = () => count++;
      
      emitter.on('test', listener);
      emitter.off('test', listener);
      emitter.emit('test');
      
      assert.equal(count, 0);
    });

    it('on() 应返回取消订阅函�?, () => {
      let count = 0;
      const unsubscribe = emitter.on('test', () => count++);
      
      emitter.emit('test');
      assert.equal(count, 1);
      
      unsubscribe();
      emitter.emit('test');
      assert.equal(count, 1);
    });

    it('once() 应只触发一�?, () => {
      let count = 0;
      emitter.once('test', () => count++);
      
      emitter.emit('test');
      emitter.emit('test');
      emitter.emit('test');
      
      assert.equal(count, 1);
    });

    it('emit() 应传递多个参�?, () => {
      let args = null;
      emitter.on('test', (a, b, c) => args = [a, b, c]);
      
      emitter.emit('test', 1, 2, 3);
      
      assert.deepEqual(args, [1, 2, 3]);
    });
  });

  // ============================================================================
  // UndoManager
  // ============================================================================
  
  describe('UndoManager', () => {
    let manager;
    
    beforeEach(() => {
      manager = new Utils.UndoManager(5);
    });

    it('应保存状�?, () => {
      manager.push({ value: 1 });
      manager.push({ value: 2 });
      
      assert.isTrue(manager.canUndo());
    });

    it('undo() 应恢复上一个状�?, () => {
      manager.push({ value: 1 });
      manager.push({ value: 2 });
      manager.push({ value: 3 });
      
      const state = manager.undo();
      
      assert.deepEqual(state, { value: 2 });
    });

    it('redo() 应恢复下一个状�?, () => {
      manager.push({ value: 1 });
      manager.push({ value: 2 });
      manager.push({ value: 3 });
      
      manager.undo();
      manager.undo();
      const state = manager.redo();
      
      assert.deepEqual(state, { value: 2 });
    });

    it('新操作后不能 redo', () => {
      manager.push({ value: 1 });
      manager.push({ value: 2 });
      manager.undo();
      manager.push({ value: 3 });
      
      assert.isFalse(manager.canRedo());
    });

    it('应限制历史记录大�?, () => {
      for (let i = 1; i <= 10; i++) {
        manager.push({ value: i });
      }
      
      // maxHiDeepStory is 5, so only last 5 states should exist
      let count = 0;
      while (manager.canUndo()) {
        manager.undo();
        count++;
      }
      
      assert.isAtMost(count, 4); // Can undo at most (maxHiDeepStory - 1) times
    });

    it('clear() 应清空历�?, () => {
      manager.push({ value: 1 });
      manager.push({ value: 2 });
      manager.clear();
      
      assert.isFalse(manager.canUndo());
      assert.isFalse(manager.canRedo());
    });

    it('canUndo() �?canRedo() 边界条件', () => {
      assert.isFalse(manager.canUndo(), 'Empty hiDeepStory');
      assert.isFalse(manager.canRedo(), 'Empty hiDeepStory');
      
      manager.push({ value: 1 });
      assert.isFalse(manager.canUndo(), 'Single item');
      
      manager.push({ value: 2 });
      assert.isTrue(manager.canUndo());
      assert.isFalse(manager.canRedo());
    });
  });
});
