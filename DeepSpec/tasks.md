# DeepSpec 开发任务清单

> 基线：Delphi 13.1 / DeepBase / DeepShell / VCL / Win64
> 方法论：CTF（建构·追溯·可谬法）→ `docs/CTF.md`
> 协议：DeepSpec 四投影协议 v1.2-draft（data-tree 已就绪）
> 已完成：Phase 1~4（详见 `history.md`）
> Bug 记录：`bugfix.md`

---

## 当前：编译验证 + 收尾

### 编译验证（全部 Phase）
- [ ] Phase 2~4 所有新增/修改代码在 Delphi 13.1 中编译通过
- [ ] DUnitX 单元测试全部通过（41/41）
- 关联：C-P0 / A-P0 / D-P0 / A-P1 / C-P1

### 遗留：未完成的 Validation 用例
- [x] INV-2: parent_id 引用存在性 ✅
- [x] INV-4: gen_status / review_status 值合法性 ✅
- [x] INV-5: 循环依赖检测 ✅
- [x] INV-6: content_hash 一致性（ValidateNodeHashes 方法） ✅
- 关联公理：A2, A7

### 遗留：语义束 UI
- [x] 按束审阅 UI（bundles.html + Accept All / Reject All 按钮 + JS Bridge） ✅
- 关联公理：A1

---

## Phase 5: CLI + Tool Protocol

### B-P0：CLI-first 集成路径
- [ ] 拆分 DeepSpec.Core（库）+ DeepSpec.CLI（Console）+ DeepSpec.Desktop（VCL）
- [ ] 命令：`deepspec init / scan / generate / validate / render`
- [ ] 编译验证
- 关联公理：A5

### B-P1：DeepSpec Tool Protocol / MCP Server
- [ ] deepspec_read / deepspec_validate / deepspec_query / deepspec_update
- [ ] MCP Server 供 Claude / Cursor 调用
- 关联公理：A5

### B-P1：.deepspec/ 自动生成 CLAUDE.md
- [ ] init/scan 时生成 CLAUDE.md 提示 AI agent 参考 .deepspec/

---

## Phase 6: 加固与扩展

### D-P1：Accept 加摩擦 / Reject 减摩擦
- [ ] Accept 增加理由选择，区分"低置信度接受"
- 关联公理：A6

### D-P2：审阅节律 + 项目健康度仪表盘
- [ ] review_overdue 标记 + 仪表盘展示审阅积压
- [ ] 健康度指标：覆盖率 / 置信度 / 决策积压 / 新鲜度
- 关联公理：A2, A3, A6, A7

### C-P2：Kind 受控词表
- [ ] x_ 扩展前缀校验在 Validation 中实现
- 关联公理：A4

### A-P1：快照与回滚
- [ ] `.deepspec/snapshots/` + Generate 前自动快照
- 关联公理：A3, A7

### A-P1：部分成功模式
- [ ] 每棵树独立 gen_status / 错误信息
- 关联公理：A7

---

## 待做：Scan 增强

### DT-6：Scan 注册 data-tree 文件类型
- [ ] 识别 `.sql`, `.prisma`, `.migration.*` 数据模型文件
- [ ] Delphi: 识别 DataModule（.dfm + .pas 组合）

---

## 待做：协议 conformance

### CF-1：data-tree conformance fixtures
- [ ] `valid-with-data-tree` fixture：含 data-tree.yaml 的完整 .deepspec
- [ ] 验证 data-tree 节点 kind 枚举、ID 前缀、data 专属字段

### CF-2：bundle + review-decision fixtures
- [ ] `valid-with-bundles` fixture：含 bundles.yaml
- [ ] `valid-with-review-decisions` fixture：含 review-decisions.yaml

---

## 推荐实施顺序

```
当前 ← 编译验证（Delphi 13.1 dcc64）
Phase 5：B-P0 CLI + B-P1 Tool Protocol
Phase 6：其余 D/C/B/A P1/P2 按反馈推进
```

---

## 代码统计

| 模块 | 单元数 |
|------|--------|
| app/ | 4 |
| services/ | 10（+Context） |
| providers/ | 3 |
| controllers/ | 1 |
| models/ | 1 |
| core/ | 7 |
| **DeepSpec 单元总数** | **26** |

---

## 无法在 AI 会话独立完成的剩余工作

| 项 | 原因 | 谁来做 |
|----|------|--------|
| WebView2 Runtime 未安装时的体验 | 依赖运行环境 | 用户验证 |
| LLM 实际调用稳定性 | 依赖网络/模型 | 联调测试 |
| 跨平台测试 | Win64 only | 后续移植 |
| 真实项目封版验证 | 需要时间和样本 | P6 阶段 |
