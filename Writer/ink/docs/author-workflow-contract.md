# Ink v2 Scene-first 作者工作流契约

> 状态：当前用户工作流法源

## 1. 总原则

- 作者只面对主编台和少量确认点；
- 自然语言意见必须回读确认并落库；
- 正式正文只来自 active Chapter Snapshot；
- AI 无权 accept、激活或原地改稿；
- Scene 是最小正式返工单位；
- Internal Shot 只用于局部生成和诊断；
- 文学选优比较完整章节候选。

## 2. Init

必须形成：

- 项目身份；
- 世界观、人物、时间线；
- 写作宪法；
- 写作指南；
- 悬疑/反转结构；
- 伏笔表；
- 地域/感官矩阵（适用项目）；
- 发布检查清单；
- 模型池与专家池。

所有资料必须登记来源和版本。

## 3. Contract

按 Book→Volume→Part→Chapter→Scene 逐层生成。

Scene Contract 包含：

- hard constraints；
- source DNA；
- soft goals；
- creative openings；
- entry/exit state；
- source references。

契约架构师起草，多模型契约复审师独立检查。未 active 的契约不得进入正式生成。

## 4. Chapter Generation

### 首批

生成两个完整 Chapter Candidate Branch。

### 门禁

每个候选：

1. Scene 契约符合性；
2. Scene 事实一致性；
3. Scene 文学基本门；
4. Chapter 连续性门。

### 补稿

- 首批0篇过线：本生产轮失败；
- 首批1—2篇过线：补充默认3篇；
- 每生产轮只补一次；
- 有效候选累计不少于3篇才进入文学选优。

### 选优

候选必须：

- 数量不少于3；
- 存在实质差异；
- 至少一篇达到绝对文学门槛。

少数冠军不得被多数票直接淘汰。

## 5. Review

作者看到：

- 完整章节候选；
- 关键Scene差异；
- 硬门结果；
- 文学证据；
- 少数意见；
- 返工归因；
- 成本和模型来源。

作者不需要逐项查看内部Shot。

## 6. Accept

Accept 前必须：

- winner Branch 冻结；
- Scene/Chapter/Book 门通过；
- 事实提案已处理；
- 无未解决 destructive issue；
- productive deviation 被保留；
- Human Decision 已确认。

Accept 创建新 Chapter Snapshot，并通过CAS更新Chapter Head。旧Snapshot永久保留。

## 7. Revise

返工必须：

- 指定目标 Scene；
- 指定允许修改范围；
- 指定 expected parent revision；
- 指定契约版本；
- 写明原因。

修改内部Shot后仍提交完整新Scene Revision。若章节已接受，必须新建Branch Version并再次Accept生成新Snapshot。

## 8. Export

Export 只读取 active Chapter Snapshot。任何导出文件修改都不改变数据库正式稿。

## 9. 有界回退

- 正文生产层最多2轮含首轮；
- 大纲层最多2轮含首轮；
- 契约层最多2轮含首轮；
- 回退前先快速归因；
- 进入上层后下层计数重置；
- 达到上限停止并通知作者。
