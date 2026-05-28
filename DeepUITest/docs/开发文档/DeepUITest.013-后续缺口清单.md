# DeepUITest.013 - 后续缺口清单

> 状态：开发文档初版
> 用途：列出已从既有文档整理完成的内容，以及真正还需要补充讨论或实现验证的缺口

---

## 1. 已整理完成

```text
1. 产品定位与边界
2. 第一阶段战略定位
3. MVP 阶段划分
4. DeepLaunch 三条命脉链
5. MVP-1 已配置启动链
6. Runner 最小动作集
7. DeepUITestProbe.exe 基本设计
8. 红绿灯基本定义
9. BugRecord / BugDiagnosis / BugObjectLink 第一版边界
10. 16 张核心数据库表
11. VCL / FMX 支持策略
12. AI 生成候选配置的原则
13. DeepBase DB1 + DB2 + DB3 + DB4 的数据部署与 API 边界
```

---

## 2. 需要补字段或实现细节

### 数据库字段

已整理表名和字段草案，但还需要实现前确认：

```text
1. 主键类型：字符串 ID、GUID、还是自增整数。
2. VersionNo / IsSealed 是否所有核心对象都需要。
3. FallbackLocators 是否用 JSON 字段。
4. EvidenceSummary 是否拆表。
5. Runner 日志和截图路径的目录规范。
6. DB2 SQLite DDL 与 DB3 API DTO 的字段映射。
```

### Runner 执行细节

需要实现时验证：

```text
1. Windows 下发送 F1 / X 的技术方案。
2. DeepLaunch 主界面识别方式。
3. GridReadyGate 是否必须识别 60 格，还是只需确认可接收目标键。
4. Runner 运行时是否需要前台焦点控制。
5. 权限不足时如何提示。
```

### Probe 实现细节

需要确定：

```text
1. Probe 用 Delphi VCL、FMX 还是控制台 + 窗口。
2. 命令行参数解析方式。
3. signal.json 写入失败时的行为。
4. stay-seconds 到期后是否自动退出。
5. 是否第一版就支持失败模拟参数。
```

---

## 3. 需要后续讨论但不阻塞 MVP-1

```text
1. Designer 配置端完整界面草图。
2. VCL .dfm / .pas 解析规则细化。
3. FMX .fmx / .pas 解析规则细化。
4. TestId / OCGSId 工程规范。
5. AI 配置生成器提示词与输出 Schema。
6. BugPattern 成熟度与反证机制。
7. BugLearningRule 如何反哺 AI。
8. 深测与 GuidedUse 是否共享底层行为链模型。
9. 深测对外第一篇文章与商业化边界。
10. DB3 共享业务 API 的正式契约，以及 DeepBase Commerce/Auth 的产品接入参数。
```

---

## 4. 建议下一步开发文档

如果继续完善文档，建议按顺序补：

```text
1. DeepUITest.017-Runner执行配置Schema.md
2. DeepUITest.019-数据库DDL草案.md
3. DeepUITest.021-Designer最小界面PRD.md
4. DeepUITest.023-VCL-FMX代码读取规则.md
5. DeepUITest.025-AI配置生成器输出约束.md
6. DeepUITest.027-DB3业务API与DeepBase-Commerce接入.md
```

---

## 5. 建议下一步工程任务

```text
1. 创建数据库最小 Schema。
2. 创建 DeepUITestProbe.exe。
3. 写一个手工 TestCase JSON 或数据库记录。
4. Runner 读取该 TestCase。
5. Runner 执行 F1 + X。
6. Runner 验证 Probe。
7. Runner 写结果与灯色。
8. 故意制造失败，验证诊断卡和 BugRecord。
```

---

## 6. 注意事项

```text
1. 不要因为 AI 配置生成器很重要，就在 MVP-1 前做它。
2. 不要因为 Bug 库战略价值大，就先做重知识库。
3. 不要把 DeepLaunch 配置生效链压进第一条工程闭环。
4. 不要把 F2 语义候选链提前到 Runner 还没稳定之前。
5. 不要让深测拖慢 DeepLaunch / GuidedUse 主产品。
6. 不要让桌面端直连公网 DB3 / DB4；DB3 走产品业务 API，DB4 走 DeepBase Commerce/Auth 框架。
```
