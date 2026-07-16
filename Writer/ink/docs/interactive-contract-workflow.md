# Ink v2 Scene-first 主编台与契约工作流

## 1. 角色

| 前台角色 | 后台职责 |
|---|---|
| 主编台 | 会话、回读、选项、恢复 |
| 资料官 | 来源登记、去重、冲突和原子条款 |
| 契约架构师 | 起草和修订四层Scene Contract |
| 契约复审师 | 独立核源、过度约束和可执行性审查 |
| 事实审查员 | 时间线、人物关系、知识边界 |
| 文学评审团 | Scene基本门和Chapter选优 |
| 真相保管员 | Contract、Revision、Snapshot和Head |

## 2. 决策会话

状态：

```text
draft
→ parsed
→ awaiting_confirm
→ confirmed | rejected | superseded
```

作者确认前，意见不得进入Contract、Prompt、Candidate或Snapshot。

恢复必须展示原选项集，不能重新生成语义漂移的选项。

## 3. 来源规范化

来源分为：

- immutable source asset；
- atomic source clause；
- proposed interpretation；
- confirmed contract clause。

过程文件从工作目录清理前，应作为只读资产归档并登记hash；不能只保留hash而丢失作者原始意见。

## 4. 契约起草

架构师：

1. 冻结来源版本；
2. 分离事实与DNA；
3. 建立冲突表；
4. 写四层条款；
5. 做删除测试；
6. 保证至少两个创意开放口；
7. 提交复审。

## 5. 独立复审

每位复审师输出：

```text
clause_id
source_supported
classification_correct
necessary
executable
conflict
overconstraint_risk
recommendation
evidence
```

建议枚举：

```text
keep
soften
split
delete
add_source
needs_human
```

复审师不能直接修改契约。

## 6. 分歧

- 事实矛盾：定向核验；
- 两个以上模型认为过度约束：退回架构师；
- 文学偏好分歧：保留为软目标或开放口；
- 高影响冲突：主编台给作者最小裁定包。

## 7. 契约修正案

优秀偏离不能直接修改契约。流程：

```text
deviation
→ amendment proposal
→ architect revision
→ independent review
→ new active version
```

一次局部灵光只记录 local exception，不自动传播成全局模板。

## 8. Stale传播

上层契约变化后：

- 下游Scene Contract；
- Prompt/Context Snapshot；
- Candidate Branch；
- Review；
- 未接受Snapshot候选；

必须标记stale。

已接受Snapshot永远不变；需要修订时创建新Branch和新Snapshot。
