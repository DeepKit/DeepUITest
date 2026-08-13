# ADR-001: Workflow 版本迁移策略

| 字段 | 类型 |
|------|-----|
| 状态 | 已批准 |
| 决策人 | 盘古（架构师）|
| 日期 | 2024-12-04 |
| 关联 | 03.01, 03.02, 06.14 |

## 背景

UniFlow 中 Workflow 定义会随业务演进而变化。当 Workflow 定义升级时，需要处理以下场景：

1. **运行中实例**: 正在执行的 Workflow 实例使用旧版本定义
2. **历史数据**: 已完成的实例记录引用旧版本
3. **回滚需求**: 新版本出问题需要回退
4. **兼容性**: 新旧版本可能共存一段时间

## 决策

采用 **版本快照 + 实例绑定** 策略。

### 核心原则

1. **Workflow 定义不可变**: 一旦发布，某版本的定义不再修改
2. **实例绑定版本**: 每个实例创建时绑定具体版本号
3. **运行中实例不迁移**: 运行中的实例继续使用创建时的版本
4. **新实例使用新版本**: 默认使用最新版本，可指定特定版本

### 版本号规范

```
<major>.<minor>.<patch>

示例: 1.0.0, 1.1.0, 2.0.0

Major: 不兼容的结构变更（如删除步骤、改变关键流程）
Minor: 向后兼容的功能增强（如添加可选步骤）
Patch: Bug 修复、文案调整
```

### 数据模型

```sql
-- Workflow 定义表（版本化）
CREATE TABLE workflow_definitions (
    id TEXT PRIMARY KEY,                    -- UUID
    workflow_type TEXT NOT NULL,            -- 业务类型标识
    version TEXT NOT NULL,                  -- 版本号(1.0.0)
    definition TEXT NOT NULL,               -- JSON 定义
    status TEXT NOT NULL DEFAULT 'draft',   -- draft/published/deprecated/archived
    created_at TEXT NOT NULL,
    published_at TEXT,
    deprecated_at TEXT,
    UNIQUE(workflow_type, version)
);

-- Workflow 实例表
CREATE TABLE workflow_instances (
    id TEXT PRIMARY KEY,
    workflow_def_id TEXT NOT NULL,          -- 关联的定义ID
     workflow_version TEXT NOT NULL,         -- 冗余存储版本号
    state TEXT NOT NULL DEFAULT 'pending',
     context TEXT,                           -- JSON 运行上下文
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (workflow_def_id) REFERENCES workflow_definitions(id)
);
```

 ### 生命周期状态

```
draft ──────→?published ──────→?deprecated ──────→?archived
  →?              →?                 →?
   └── 可修复     └── 不可修改        └── 停止创建新实例
                       运行中实例继续执行  历史数据保留
```

### 迁移流程

 #### 场景 1: 发布新版本

```
1. 创建新版本定义（status=draft）?
2. 测试验证
3. 发布新版本（status=published）?
4. （可选）废弃旧版本（old.status=deprecated）?
5. 新实例自动使用新版本
6. 旧版本运行中实例继续执行
```

#### 场景 2: 回滚

```
 1. 将新版本标记为 deprecated
 2. 将旧版本重新标记为 published
3. 新实例使用旧版本
4. 已创建的新版本实例继续执行（不中断）
```

#### 场景 3: 强制迁移运行中实例（谨慎使用）?

```
前提条件：?
- 新旧版本步骤兼容（仅添加可选步骤）
 - 实例当前游标位置在两个版本中都存在

步骤2
1. 暂停实例执行
2. 验证游标兼容性
3. 更新 workflow_def_id, workflow_version
4. 恢复执行
```

### API 设计

```pascal
type
  IWorkflowVersionManager = interface
    // 获取指定类型的最新发布版本
    function GetLatestVersion(AWorkflowType: string): string;
    
    // 获取指定版本的定义
    function GetDefinition(AWorkflowType: string; AVersion: string): TWorkflowDefinition;
    
    // 发布新版本
    procedure PublishVersion(AWorkflowType: string; AVersion: string);
    
    // 废弃版本
    procedure DeprecateVersion(AWorkflowType: string; AVersion: string);
    
    // 检查版本兼容性
    function CheckCompatibility(AOldVersion, ANewVersion: string): TCompatibilityResult;
    
    // 获取版本迁移路径
    function GetMigrationPath(AFromVersion, AToVersion: string): TArray<TMigrationStep>;
  end;
```

### 兼容性检查规则

| 变更类型 | 兼容性 | 说明 |
|----------|--------|------|
| 添加可选步骤 | ✓ 兼容 | 旧实例跳过新步骤 |
| 添加必需步骤 | ✓ 不兼容 | 旧实例缺少必需步骤 |
| 删除步骤 | ✓ 不兼容 | 旧实例可能正在该步骤 |
| 修改步骤参数（添加可选） | ✓ 兼容 | 使用默认值 |
| 修改步骤参数（删除/改类型） | ✓ 不兼容 | 数据格式不匹配 |
| 修改流程分支 | ⚠️ 视情况 | 需具体分析 |

### 监控指标

```json
{
  "workflow_versions": {
    "active_versions": ["1.0.0", "1.1.0", "2.0.0"],
    "instances_by_version": {
      "1.0.0": { "running": 5, "completed": 1000, "failed": 10 },
      "1.1.0": { "running": 20, "completed": 500, "failed": 5 },
      "2.0.0": { "running": 100, "completed": 50, "failed": 2 }
    },
    "deprecation_warnings": [
      { "version": "1.0.0", "deprecated_at": "2024-12-01", "running_instances": 5 }
    ]
  }
}
```

## 后果

### 正面

- 清晰的版本追踪，便于审计
- 运行中实例不受升级影响
- 支持灰度发布和回滚
- 历史数据完整保留

### 负面

- 多版本共存增加维护复杂度
- 需要定期清理废弃版本
- 强制迁移场景需要人工介入

### 风险缓解

1. **版本膨胀**: 设置自动归档策略，超过 N 个版本自动归档最旧的
2. **遗留实例**: 监控旧版本运行中实例数，超时未完成发出告警
3. **兼容性错误*: 提供兼容性检查工具，上线前强制验证

## 替代方案（已否决）

### 方案 A: 原地升级
- 描述: 直接修改 Workflow 定义，所有实例使用最新版
- 否决原因: 运行中实例可能中断，无法回滚

### 方案 B: 完全隔离
- 描述: 不同版本完全独立，无共享
- 否决原因: 资源浪费，历史数据难以关联

## 相关文档

- `03.01.Arch-UniFlow架构设计-v1.0.md` - 整体架构
- `03.02.Arch-UniFlow-版本与实验策略-v1.0.md` - 版本策略
- `04.01.Data-UniFlow数据模型-v1.0.md` - 数据模型
