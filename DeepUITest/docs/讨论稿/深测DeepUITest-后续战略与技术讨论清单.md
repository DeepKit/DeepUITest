# 深测 DeepUITest：后续战略与技术讨论清单

> 用途：新会话继续讨论时使用。  
> 当前状态：已完成 DeepUITest 的技术定位、战略定位、MVP 总路线、DeepLaunch 三条命脉链、红绿灯、Bug 库、护城河和目标客户的初步讨论。  
> 下一步应避免重新从头发散，而是从以下清单继续。

---

# 一、最高优先级：战略验收标准

## 1. DeepUITest 第一阶段成功标准

待讨论问题：

```text
做到什么程度，就算 DeepUITest 第一阶段成功？
```

候选标准：

```text
1. DeepLaunch 三条命脉链可被深测守住；
2. Runner 能回放并生成红绿灯；
3. 失败能生成诊断卡；
4. BugRecord 能入库；
5. 至少一个 Bug 经验能反哺下一次配置生成；
6. 形成 OCGS 样板文档；
7. 不拖慢 DeepLaunch / 善用主产品开发。
```

建议下一轮优先讨论。

---

# 二、战略定位继续讨论

## 2. DeepUITest 在 OCGS 产品矩阵中的归类

待讨论问题：

```text
深测在整个 OCGS 产品矩阵中应归为：
1. 工具产品；
2. 基础设施；
3. 质量治理产品线；
4. 开发者产品；
5. 以上分阶段成立？
```

建议方向：

```text
内部：质量治理基础设施；
外部：开发者行为回归测试工具；
OCGS 体系：能力质量治理产品线。
```

---

## 3. DeepUITest 与 DeepGuide / DeepLaunch / 善用的关系

待讨论问题：

```text
深测未来是否独立品牌？
还是作为 OCGS / DeepGuide / DeepLaunch 的技术支撑隐藏存在？
```

候选方向：

```text
1. 独立品牌 DeepUITest；
2. OCGS Quality 子产品；
3. DeepLaunch / 善用内部测试工具；
4. 先隐藏，后独立；
5. 对内 DeepUITest，对外 OCGS Quality。
```

---

## 4. 商业化边界

待讨论问题：

```text
未来如果对外收费，免费版 / 专业版 / 团队版如何划分？
```

可讨论维度：

```text
1. 支持项目数量；
2. 测试链数量；
3. AI 生成次数；
4. Bug 库容量；
5. VCL / FMX 深度适配；
6. 批量回归；
7. 团队协作；
8. 报表；
9. CI/CD 集成；
10. 商业用途。
```

建议后置，不急。

---

# 三、DeepLaunch 三条命脉链继续讨论

## 5. 第一样板：已配置启动链详细封版标准

当前已定：

```text
F1 → X → 指定程序启动
```

待讨论：

```text
1. 最小 JourneyStep；
2. 断言级别；
3. 红 / 黄 / 绿 / 灰判定；
4. 失败诊断卡；
5. BugRecord 结构；
6. 是否必须使用 DeepUITestProbe.exe；
7. 如何作为第一阶段验收 Demo。
```

---

## 6. 第二样板：配置生效链详细封版标准

当前已定：

```text
绑定程序 → 保存 → F1 + X → 指定程序启动
```

待讨论：

```text
1. 最小配置生效链 A；
2. 完整用户配置链 B；
3. 配置写入断言；
4. Grid 显示断言；
5. 运行时 KeyMap / 缓存刷新断言；
6. 最终启动断言；
7. 典型 BugPattern；
8. 红绿灯如何变化。
```

战略重点：

```text
它是 DeepUITest 区别于普通 UI 测试工具的关键样板。
```

---

## 7. 第三样板：F2 候选执行链

当前已定：

```text
F2 → 输入 / 转录 → 1-9 候选 → 执行 → 0 返回 / 取消
```

待讨论：

```text
1. F2-A 文本候选链；
2. F2-B 取消返回链；
3. F2-C 语音转录链；
4. F2-D 习惯链路学习链；
5. 哪些进入第一阶段，哪些后置；
6. 如何避免语义识别测试拖慢 DeepUITest。
```

已定边界：

```text
第一阶段只测固定文本候选执行，不测开放式自然语言理解和真实语音鲁棒性。
```

---

# 四、红绿灯与 Bug 库继续讨论

## 8. 红绿灯规则模板化

待讨论：

```text
1. LampRule 是否需要独立表；
2. BugPattern 如何影响 LampRule；
3. 哪些情况直接红灯；
4. 哪些情况黄灯；
5. 用户怎样把黄灯变绿；
6. 红绿灯界面是否采用诊断卡式表达。
```

---

## 9. Bug 库第一版边界

待讨论：

```text
1. BugRecord 第一版字段；
2. BugObjectLink 最小可用结构；
3. BugDiagnosis 与 HumanDecisionLog 的关系；
4. BugPattern 是否第一版就做；
5. BugLearningRule 何时引入；
6. 如何避免 Bug 库变成人工维护负担。
```

已形成原则：

```text
Bug 库从 Runner 失败中自然生长；
不要一开始要求人工维护大量模式。
```

---

## 10. Bug 经验反哺机制

待讨论：

```text
一次失败经验如何影响下一次 AI 生成配置？
```

候选链：

```text
Runner 失败
→ BugRecord
→ AI 候选原因
→ 用户数字选择
→ BugPatternCandidate
→ 下次生成同类测试时命中
→ 提醒补断言
→ 用户接受
→ 配置增强
→ 灯色变化
```

---

# 五、MVP 开发节奏继续讨论

## 11. MVP-0 到 MVP-6 的开发任务清单

待讨论：

```text
每个 MVP 阶段具体开发任务、验收标准、不要做的事。
```

当前阶段划分：

```text
MVP-0：数据库与双端骨架
MVP-1：DeepLaunch 已配置启动测试
MVP-2：DeepLaunch 配置生效测试
MVP-3：红绿灯与失败诊断卡
MVP-4：AI 读取 VCL 代码 / 文档生成测试草稿
MVP-5：Bug 经验反哺
MVP-6：FMX 支持增强
```

---

## 12. Designer 配置端界面草图

待讨论：

```text
1. 项目页；
2. 源码 / 文档索引页；
3. 测试用例页；
4. 红绿灯审核页；
5. 失败诊断页；
6. Bug 库页是否第一版需要。
```

---

## 13. Runner 测试端执行流程

待讨论：

```text
1. 加载测试任务；
2. 启动被测程序；
3. 执行 JourneyStep；
4. 采集截图 / 日志；
5. 执行 AssertRule；
6. 写 RunnerResult；
7. 生成 LampEvaluation；
8. 失败进入 Bug 诊断卡。
```

---

## 14. DeepUITestProbe.exe 是否立项

待讨论：

```text
1. 是否第一阶段必须做；
2. 用 VCL 还是控制台程序；
3. 是否支持 signal.json；
4. 是否支持 runId / caseId；
5. 是否支持失败模拟；
6. 是否作为 DeepUITest 内置工具分发。
```

---

# 六、与善用 / OCGS-d 的关系继续讨论

## 15. 深测与善用是否共用底层模型

待讨论：

```text
善用的 GuideJourney / GuideCardSequence
和深测的 TestJourney / JourneyStep
是否可以共享一套“行为链模型”？
```

可能共用：

```text
Output
Gate
Field
TargetObject
Action
State
Recovery
HumanDecisionLog
```

差异：

```text
善用：面向用户看图操作；
深测：面向 Runner 自动回放和断言。
```

---

## 16. 深测与 OCGS-d 的关系

待讨论：

```text
OCGS-d 讨论出来的宝物 / 门禁链，
是否可以直接生成 DeepUITest 测试配置草稿？
```

这可能形成闭环：

```text
OCGS-d 设计
→ DeepLaunch / 善用 实现
→ DeepUITest 测试封版
→ Bug 库反哺 OCGS-d
```

---

# 七、对外表达与内容

## 17. 第一篇对外文章

待讨论：

```text
深测第一篇对外文章应面向谁？
```

候选主题：

```text
1. AI 改 Delphi 老项目之前，先建立行为基线；
2. 老桌面软件为什么不敢改；
3. UI 自动化测试为什么不能只录制点击；
4. 从“按钮测试”到“行为链封版”；
5. OCGS 如何进入软件质量治理。
```

建议首选：

```text
AI 改代码之前，先建立行为基线；AI 改代码之后，再回放验证。
```

---

## 18. 对外一句话继续打磨

已有候选：

```text
深测 DeepUITest：
给 Delphi / Windows 桌面老项目建立关键行为回归测试基线。

AI 帮你改代码；
深测帮你确认旧行为有没有坏。
```

待讨论：

```text
1. 更偏开发者；
2. 更偏小团队老板；
3. 更偏 OCGS 理论；
4. 更偏产品销售页；
5. 更偏知乎文章标题。
```

---

# 八、建议下一轮开场

建议用户下一轮直接说：

```text
请阅读《深测DeepUITest-技术与战略讨论总归档.md》和《深测DeepUITest-后续战略与技术讨论清单.md》。
我们继续讨论“DeepUITest 第一阶段战略验收标准”。
请你继续做主持人，找 5 个专家发言，不要直接写大方案。
```

推荐下一题：

```text
DeepUITest 第一阶段做到什么程度，就算战略成功？
```
