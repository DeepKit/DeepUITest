# DeepSpec 三棵树通用协议 — 标准化圆桌讨论纪要 v1

> 日期：2026-05-15
> 主题：DeepSpec 协议能否成为 AI 时代需求规范化的行业标准？需要做哪些准备？
> 参与专家：标准化协议设计 / AI 产品战略 / 开发者体验 / 企业需求工程 / 开源生态建设

---

## 一、专家一：标准化协议设计（IETF/W3C 背景）

### 判断

协议骨架具备标准潜质，但需要补齐形式化定义层。

### 优势

1. **关注点分离清晰**：三棵树 + 关系边 + 证据 + 问题 + 决策，五个正交维度各自独立演化。
2. **双界面原则**是关键的元洞察：承认 AI 和人类共存。
3. **宽松/严格模式分离**解决了"鸡生蛋"问题。

### 要走向标准必须做的事

- **用 JSON Schema 重写 Schema 定义**。当前用 Markdown + YAML 示例描述 Schema，对人类阅读好但对机器校验不够精确。建议为每个 YAML 文件类型提供 JSON Schema 定义。
- **建立 Schema Registry**。类似 IANA 的媒体类型注册表，让社区可以提交新的 kind 值。当前 `x_` 前缀是好的开始，但缺乏治理流程。
- **定义兼容性测试套件**。一个声称"兼容 DeepSpec v1"的工具必须通过哪些测试？

### 风险

- **过早标准化**。如果协议只在一个产品和一种技术栈上验证过，可能捕获的是生态偏见而非通用需求。建议至少在 3 种不同技术栈上验证后再推动标准化。

---

## 二、专家二：AI 产品战略（LLM 平台背景）

### 判断

时机非常好，但标准竞争窗口只有 12-18 个月。

### 为什么现在有机会

```text
代码层：有 LSP（Language Server Protocol）标准化
测试层：有各种测试框架的通用格式
需求层：没有 AI 原生的标准化格式 ← 这是 DeepSpec 的位置
```

当前 AI 编程工具在需求理解上完全依赖自然语言。`.deepspec/` 目录本质上是 **"AI 的 LSP for requirements"**。

### 要抓住窗口必须做的事

1. **先成为 AI 工具的上下文消费者，再成为生产者**。更大的杠杆点是让 Claude Code、Cursor、Copilot 直接读取 `.deepspec/` 目录作为项目上下文。
2. **协议必须独立于 DeepSpec 产品**。类似 Git（协议）vs GitHub（产品）的关系。
3. **定义最小消费协议（Reader Profile）**。一个 AI 工具如果只想"读取"DeepSpec 的事实，需要实现的最小子集是什么？建议 30 分钟内可以集成。

### 风险

- **大厂的 "good enough" 方案**。如果 Anthropic 或 OpenAI 内置了类似格式，窗口就会关闭。

---

## 三、专家三：开发者体验与采纳（DX 背景）

### 判断

协议对早期采纳者友好，但标准化需要跨越"鸡生蛋"鸿沟。

### 采纳障碍分析

| 障碍 | 严重程度 | 应对策略 |
|------|----------|----------|
| "为什么要多一个 `.deepspec/` 目录？" | 高 | 让它对现有工具零侵入 |
| "我不用 Delphi，跟我有什么关系？" | 高 | 必须先在 Web/Node 项目上跑通 Demo |
| "YAML 手工写太麻烦" | 中 | DeepSpec 自动生成，人类只做审阅 |
| "团队其他人不用怎么协作？" | 高 | `.deepspec/` 在 Git 中可读可 diff |

### 要走向标准必须做的事

1. **30 秒价值证明**。在线 Demo：粘贴 GitHub URL → 10 秒生成预览。
2. **定义采用梯度**：

```text
Level 0 - 扫描仪：只生成 project-spec.yaml + scan-report.yaml
          价值：文件分类 + 项目类型识别
          集成成本：1 天

Level 1 - 结构树：生成三棵树 + 关系边
          价值：功能/模块/视图的结构化视图
          集成成本：1 周

Level 2 - 完整协议：+ evidence + issues + decisions + 校验器
          价值：需求审阅、AI 上下文、决策追溯
          集成成本：1 月
```

3. **提供参考实现**。Python 或 TypeScript（不是 Delphi），只实现 Reader Profile + 宽松模式校验，MIT 许可。

### 风险

- **"足够好"陷阱**。Level 0 就提供了明显价值，团队可能停在 Level 0 不升级。

---

## 四、专家四：企业需求工程（ReqIF/DOORS 背景）

### 判断

填补了重要空白，但必须与传统需求工程标准建立桥接。

### 独特价值

传统需求工程假设**需求是人为撰写的、自上而下的**。DeepSpec 的洞察：**AI 时代，大量需求是 AI 逆向推断的，人类只做审阅和决策**。

```text
传统：人写需求 → 人审阅 → 人实现
DeepSpec：AI 推断需求 → 人审阅决策 → AI 辅助实现
```

### 要走向标准必须做的事

1. **与 ReqIF 建立互操作映射**：

```text
DeepSpec 节点    ←→  ReqIF SpecObject
DeepSpec 关系边  ←→  ReqIF SpecRelation
DeepSpec 证据    ←→  ReqIF SpecObject 的 AttributeValues
DeepSpec 决策    ←→  ReqIF 中无直接对应（这是 DeepSpec 的创新）
```

2. **增加测试追溯**。关系类型枚举中增加 `verified_by`（需求由哪个测试验证）。没有"需求 → 测试"的追溯链，企业不会考虑。

3. **支持需求基线（Baseline）**。节点级 `revision` 之外，需要项目级基线机制。

4. **多人协作机制**。当前 LOCKED/GUARDED/OPEN 是单用户场景。需要 `locked_by` 或 Git merge 策略文档。

### 风险

- **"玩具化"偏见**。必须有至少一个中大型项目（100+ 节点、10+ 人团队）的验证案例。

---

## 五、专家五：开源生态与社区建设

### 判断

协议设计足够好，但标准不是技术问题而是社区问题。

### 标准成功的真实因素

```text
1. 解决了一个真实痛点
2. 有一个杀手级实现
3. 采用成本极低
4. 不绑定在单一产品或公司上
5. 社区有参与感和拥有感
```

### 要走向标准必须做的事

1. **协议与产品分家，现在就做**：

```text
deep-spec/               协议仓库（MIT）
  schemas/               JSON Schema 定义
  examples/              多语言项目示例
  conformance/           兼容性测试套件

deep-spec-tools/         工具仓库（可选开源）
  python-reader/         最小 Python 读取器
  typescript-reader/     最小 TypeScript 读取器

DeepSpec/                产品仓库（商业许可）
```

2. **发布 "10 分钟集成指南"**。目标读者是其他工具的开发者，不是 DeepSpec 用户。

3. **种子项目策略**：

```text
seed-delphi-vcl/         Delphi VCL + 完整 .deepspec
seed-react-web/          React SPA + 完整 .deepspec
seed-go-microservice/    Go 微服务 + 完整 .deepspec
seed-python-fastapi/     Python API + 完整 .deepspec
seed-mixed-monorepo/     混合技术栈 + 完整 .deepspec
seed-docs-only/          纯文档项目 + 完整 .deepspec
seed-legacy-chaos/       遗留项目 + 问题诊断
```

4. **建立 governance 文件**。协议演进由社区决定，RFC 流程提交扩展，破坏性变更需 2/3 维护者投票。

5. **中文生态先发优势**。国内没有本土需求规范化工具。先在国内社区推广，考虑提交信标委。

### 风险

- **"又一个 YAML 格式"综合症**。必须有"10 秒 Wow Moment"克服惯性。

---

## 六、五位专家的共识与分歧

### 共识（5/5 同意）

1. 协议的设计骨架是好的，三棵树 + 证据 + 决策的模型有独创性。
2. 协议必须与产品分离。
3. 需要至少一个非 Delphi 的参考实现和验证案例。
4. 窗口期有限，AI 需求规范化是多个玩家会进入的空白领域。

### 分歧

| 问题 | 专家一 | 专家二 | 专家三 | 专家四 | 专家五 |
|------|--------|--------|--------|--------|--------|
| 优先级 | 先标准化 | 先产品 | 先体验 | 先企业验证 | 先社区种子 |
| JSON Schema 形式化 | 必须 | 有帮助非紧急 | 不重要 | 企业需要 | 有帮助 |

---

## 七、推荐路线图

```text
Phase 0（现在，1-2 周）
  ├─ 协议独立仓库，MIT 发布
  ├─ 补齐 JSON Schema 形式化定义
  ├─ 补充非 Delphi 种子项目示例（至少 React + Go）
  └─ 发布 10 分钟集成指南

Phase 1（1-3 月）
  ├─ DeepSpec 产品 MVP 发布
  ├─ 3 个种子项目公开
  ├─ 发布 Python/TypeScript 最小 Reader
  └─ 在 Claude Code / Cursor 社区推广 Context Pack 消费

Phase 2（3-6 月）
  ├─ 非 Delphi 项目的完整验证
  ├─ 社区贡献的 kind 扩展和工具
  ├─ 定义 "DeepSpec Reader Profile" 最小兼容性标准
  └─ 考虑提交标准化组织或建立独立工作组

Phase 3（6-12 月）
  ├─ 企业场景验证（100+ 节点项目）
  ├─ 与 ReqIF/SysML 的互操作映射
  ├─ 需求基线和多人协作机制
  └─ 如果社区采纳良好，推动成为事实标准
```

---

## 八、结论

DeepSpec 协议有可能成为 AI 时代需求规范化的早期标准——不是因为技术最完美，而是因为第一个系统地解决了"AI 如何结构化理解和追溯软件需求"这个空白问题。但标准的胜负不在协议本身，而在**生态建设的速度和开放性**。协议准备好之后，重心应从"写好 Schema"转向"让 10 个不同工具都愿意读取 `.deepspec/` 目录"。

---

*文档版本：v1 · 2026-05-15 · 五专家圆桌讨论*
