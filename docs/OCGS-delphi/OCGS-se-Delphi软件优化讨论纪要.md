# OCGS-se Delphi 软件优化讨论纪要

> 版本：v1.0  
> 主题：OCGS-se 如何应用于 Delphi 软件系统  
> 讨论范围：Delphi 软件根据 OCGS-se 理论如何优化  
> 核心结构：AbilitySet → PurposeSet → DueSet  
> 说明：本文件用于承接后续关于 PurposeSet 状态变量、状态变化触发、保存、刷新、反馈机制的讨论。

---

## 一、总定位

OCGS-se 是 OCGS 在软件领域的展开，是软件创作从“功能生产”走向“能力治理”的范式级理论框架。

在 Delphi 软件系统中，OCGS-se 的目标不是推翻 Delphi，也不是重写 VCL / FMX，而是将 Delphi 原本混在窗体事件中的能力、目的与合当性重新分层。

Delphi 软件原来的典型结构是：

```text
Form / Frame
  ↓
ButtonClick / MenuClick / ActionExecute
  ↓
业务 Handler / Service / DataModule
```

这种方式容易导致：

- 主窗体越来越胖；
- ButtonClick / MenuClick / ActionExecute 到处散落；
- UI 状态判断写在窗体中；
- TActionList 只能解决一部分命令统一问题；
- Handler、权限、状态、门禁、日志混在一起；
- AI 或自动化工具未来容易直接调用裸 Handler。

OCGS-se 希望将其优化为：

```text
PurposeSet
  ↓ 投影 / 绑定
TAction / Button / MenuItem / Shortcut / CommandPalette
  ↓ 触发
PurposeSet.Run(PurposeKey)
  ↓
AbilitySet.Run(AbilityKey / AbilityChain)
  ↓
DueSet.Check / Evidence / Seal / Accountability
```

核心句：

> Delphi 软件应从 Form-centered / Event-driven 走向 Purpose-centered / Capability-governed / Due-constrained。

---

## 二、Delphi 中的三层结构

### 1. AbilitySet：能力集

AbilitySet 是对 Delphi 中既有能力的注册、识别、启停、分发、容错和观测层。

它可以接收：

- 普通 Handler；
- Service 方法；
- DataModule 方法；
- Controller 方法；
- Command 对象；
- API 调用；
- 文件操作；
- 数据库操作；
- AI 调用；
- 插件能力；
- 脚本能力；
- 后台任务。

AbilitySet 不负责解释目的，不负责判断合当性，也不直接绑定 UI。

它只回答：

```text
能不能做？
怎样执行？
执行结果如何返回？
失败如何处理？
是否可用？
是否可观测？
```

ActionGrid 可以成为 AbilitySet 的工程内核。

建议理解：

```text
Handler = 能力实现
Service / DataModule = 能力提供者
Command = 能力对象化形式
ActionGrid = AbilitySet 的执行内核
AbilitySet = 能力注册与治理层
```

---

### 2. PurposeSet：目的集 / 为集

PurposeSet 是 Delphi 优化的第一切入口。

它不是按钮，不是 TAction，也不是 Handler，而是一个软件目的的显现、状态、上下文、能力映射和合当引用的组织层。

PurposeSet 负责：

- 定义 PurposeKey；
- 统一按钮、菜单、快捷键、右键菜单、工具栏等显现口；
- 统一 Caption / Hint / Enabled / Visible / Shortcut；
- 统一状态解析；
- 提供禁用原因；
- 映射 AbilitySet；
- 引用 DueSet；
- 提供 AI 可读目的地图。

核心句：

> 一个 Purpose，多处显现；一个状态，统一解析。

---

### 3. DueSet：合当集 / 当集

DueSet 不是给所有操作都加复杂流程，而是按风险对重要操作建立合当治理。

它负责：

- BoundarySet：不可越界；
- ContractSet：合格结果的管道约定；
- OutputSet：被治理产出物；
- AcceptanceSet：验收标准；
- GateSet：门禁判断；
- EvidenceSet：证据记录；
- SealSet：封存；
- AccountabilitySet：责任锚点；
- RiskSet：治理强度。

Delphi 中必须进入 DueSet 的操作包括：

- 删除；
- 发布；
- 封存；
- 回滚；
- AI 自动应用代码；
- 批量修改；
- 执行 SQL；
- 覆盖文件；
- 修改核心配置；
- 数据库迁移；
- 提交正式交付物。

普通 UI 操作、预览、展开、选择、只读查看等不需要完整 DueSet。

---

## 三、PurposeSet 与 TActionList / ButtonClick / MenuItem / Shortcut 的关系

Delphi 已有 TActionList，它能统一：

- Caption；
- Hint；
- Enabled；
- Visible；
- Shortcut；
- OnExecute；
- OnUpdate。

但 TActionList 主要是 Delphi 原生命令载体，不是完整 PurposeSet。

PurposeSet 是 TActionList 的上位升级。

推荐关系：

```text
PurposeSet
  ↓ Project / Bind
TAction
  ↓ Native Delphi Binding
Button / MenuItem / ToolButton / Shortcut
```

触发路径：

```text
Button / MenuItem / Shortcut
  ↓
TAction.Execute
  ↓
PurposeSet.Run(PurposeKey)
  ↓
PurposeResolver.Resolve(Context)
  ↓
DueSet.CheckIfNeeded
  ↓
AbilitySet.Run(AbilityRefs)
  ↓
EvidenceSet.RecordIfNeeded
```

关键判断：

- ButtonClick 是最低层旧入口；
- MenuItem / Shortcut 是显现口；
- TAction 是 Delphi 原生命令载体；
- PurposeSet 是上位目的属集；
- TActionList 可以作为 PurposeSet 在 Delphi UI 中的投影层。

核心句：

> PurposeSet 管目的，TActionList 显现目的。

---

## 四、AbilitySet 与 Handler / Service / DataModule / Command / ActionGrid 的关系

### Handler

Handler 是具体执行代码。

```text
Handler = 能力实现
AbilitySet = 能力治理
```

### Service

Service 是能力提供者。

```text
Service 生产 / 承载能力
AbilitySet 注册 / 治理能力
```

### DataModule

DataModule 可以提供数据能力，但不应成为上帝对象。

DataModule 不应承担：

- 目的组织；
- UI 状态显现；
- 合当判断；
- 封存；
- 责任归属。

### TAction

TAction 更适合作为 PurposeSet 的显现投影层。

长期定位：

```text
TAction = PurposeSet 的 Delphi 原生投影对象
```

### Command

Command 可以作为 AbilityEntry 的实现形式，尤其适合 Undo / Redo / Queue / Macro / Replay。

### ActionGrid

ActionGrid 是 AbilitySet 的自然工程内核。

它负责：

- 能力注册；
- 能力启停；
- 分发；
- 优先级；
- DryRun；
- 容错；
- Metrics。

但 ActionGrid 不应吞并 PurposeSet 与 DueSet。

---

## 五、Delphi 中 DueSet 的落地范围

### L0：不需要 DueSet 的轻操作

- 切换 Tab；
- 展开树节点；
- 调整窗口大小；
- 临时搜索；
- 复制文本；
- 查看帮助；
- 预览只读内容。

### L1：轻 DueSet

- 保存草稿；
- 普通导出；
- 本地缓存；
- 普通格式化；
- 预览生成结果。

### L2：中等 DueSet

- 生成正式报告；
- 保存项目配置；
- 运行质量检查；
- AI 生成草稿并写入工作区；
- 构建；
- 安装插件；
- 同步数据。

### L3：完整 DueSet

- 删除文件 / 删除数据；
- 覆盖文件；
- 执行 SQL；
- 批量修改；
- 发布版本；
- 封存产出物；
- 回滚版本；
- 召回版本；
- 修改核心配置；
- AI 自动应用代码；
- 数据库迁移；
- 权限变更；
- 提交正式交付物。

---

## 六、Delphi 中 OCGS-se 的最小落地顺序

理论顺序是：

```text
AbilitySet → PurposeSet → DueSet
```

但 Delphi 工程落地不必按这个顺序。

推荐顺序是：

```text
1. PurposeSet 先行
2. TActionList 投影化
3. 状态 Resolver 统一
4. AbilitySet 逐步注册
5. 高风险 Purpose 接入 DueSet
6. EvidenceSet / SealSet / AccountabilitySet 按风险扩展
7. AI 读取 PurposeMap，而不是裸 AbilityMap
```

更简短：

> 先让显现有序，再让能力入册，最后让高风险结果合当。

---

## 七、Delphi 落地七步法

### 第一步：盘点现有显现口

整理按钮、菜单、右键菜单、快捷键、TAction、工具栏按钮、状态栏入口、命令面板入口、AI 操作入口。

### 第二步：建立 PurposeKey

不要用控件名或函数名命名。

错误：

```text
btnSaveClick
actSaveExecute
DoSave2
Button3
```

正确：

```text
file.save
file.export
project.build
output.quality_check
artifact.seal
evidence.view
ai.code.generate
ai.code.apply
```

### 第三步：让 TAction 成为 PurposeSet 投影

保留 Delphi 原生 TActionList，让 PurposeSet 管理 TAction。

### 第四步：统一状态解析

用 PurposeResolver 统一返回：

- visible；
- enabled；
- caption；
- hint；
- disabled_reason；
- warning_state；
- next_action。

### 第五步：把旧 Handler 注册为 AbilitySet

旧 Handler 不必立即重写，可逐步注册为 Ability。

### 第六步：选高风险 Purpose 接入 DueSet

优先接入：

- artifact.seal；
- artifact.rollback；
- ai.code.apply；
- db.sql.execute；
- file.batch_replace；
- project.publish；
- config.production.save；
- output.submit_acceptance。

### 第七步：形成 Delphi OCGS-se 标准模板

新功能不再先问“加哪个按钮”，而是先问：

1. PurposeKey 是什么？
2. 它显现在哪些位置？
3. 它调用哪些 Ability？
4. 它是否需要 DueSet？
5. 它的禁用原因如何解释？
6. 是否需要 Evidence？
7. 是否需要 AI 可读描述？

---

## 八、推荐试点

第一试点建议：

```text
output.quality_check
```

原因：

- 有按钮；
- 有菜单；
- 有状态；
- 有执行能力；
- 有 PASS / FAIL；
- 有 Evidence；
- 但不一定需要完整 Seal。

第二试点建议：

```text
artifact.seal
```

原因：

- 能体现 PurposeSet、AbilitySet、DueSet；
- 能展示 Gate / Evidence / Seal / Accountability；
- 理论表达完整；
- 实现稍重。

---

## 九、冻结句

> Delphi 落地 OCGS-se 的最小顺序，应以 PurposeSet 为第一切入口：先统一按钮、菜单、快捷键、TAction 和状态显现，建立稳定 PurposeKey；再把旧 Handler、Service、DataModule 方法逐步注册为 AbilitySet；最后把删除、发布、封存、AI 应用、数据库修改等高风险 Purpose 接入 DueSet。工程上不是先推倒重写，而是先让显现有序，再让能力入册，最后让高风险结果合当。

---

## 十、下一步讨论

下一步应讨论：

> 一个 PurposeSet 要设计哪些状态变量？状态变化如何触发、保存、刷新与反馈？

重点包括：

- PurposeSet 的状态字段；
- 状态来源；
- 状态触发机制；
- 状态保存机制；
- 状态刷新机制；
- UI 反馈机制；
- DueSet 状态如何投影到 PurposeSet；
- AbilitySet 状态如何影响 PurposeSet；
- AI 如何读取 Purpose 状态。
