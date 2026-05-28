# UniFlow 工作流模�?

> 常用工作流模板集合，可直接使用或作为参�?

---

## 模板列表

| 模板 | 分类 | 描述 | 特�?|
|------|------|------|------|
| [01-sequential-approval](01-sequential-approval.json) | 审批 | 多级顺序审批 | 循环、等待、条件分�?|
| [02-data-sync](02-data-sync.json) | 集成 | ETL 数据同步 | 并行、批量、错误处�?|
| [03-ai-chat](03-ai-chat.json) | AI | 智能对话 | LLM调用、工具调用、会话管�?|

---

## 使用方式

### 1. 直接使用

```pascal
var
  Loader: TWorkflowLoader;
  Workflow: TWorkflowDefinition;
begin
  Loader := TWorkflowLoader.Create;
  try
    Workflow := Loader.LoadFromFile('Templates/01-sequential-approval.json');
    // 使用工作�?..
  finally
    Loader.Free;
  end;
end;
```

### 2. 作为基础扩展

```json
{
  "extends": "template-sequential-approval",
  "name": "请假审批",
  "variables": {
    "maxLevel": 2
  },
  "steps": [
    // 覆盖或添加步�?
  ]
}
```

### 3. 代码引用

```pascal
// 使用模板注册�?
TWorkflowTemplates.Register('approval', 'Templates/01-sequential-approval.json');

// 从模板创建实�?
var Workflow := TWorkflowTemplates.CreateFrom('approval', InputParams);
```

---

## 模板规范

### 必需字段

```json
{
  "$schema": "../schema/workflow.schema.json",
  "id": "template-xxx",           // �?template- 前缀
  "name": "模板名称",
  "description": "详细描述",
  "version": "1.0.0",
  "category": "分类",
  "tags": ["标签1", "标签2"],
  "input": { ... },
  "output": { ... },
  "steps": [ ... ]
}
```

### 推荐实践

1. **输入输出** - 明确定义类型和说�?
2. **变量初始�?* - �?`variables` 中设置默认�?
3. **错误处理** - 配置 `errorHandling` 策略
4. **超时设置** - 为长时间操作设置合理超时
5. **日志/通知** - 在关键节点添加通知

---

## 分类说明

| 分类 | 说明 | 典型场景 |
|------|------|----------|
| approval | 审批流程 | 请假、报销、采�?|
| integration | 系统集成 | ETL、API编排、数据同�?|
| ai | AI相关 | 对话、内容生成、数据分�?|
| notification | 通知触达 | 提醒、告警、营销 |
| task | 任务调度 | 定时任务、批处理 |

---

## 版本历史

- **v1.0.0** (2025-12-06)
  - 初始版本
  - 添加顺序审批、数据同步、AI对话模板
