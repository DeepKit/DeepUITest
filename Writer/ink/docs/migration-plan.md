# Ink v2 Shot→Scene 安全迁移计划

> 状态：当前迁移法源
> 原则：允许影子验证，不允许双正文权威

## 当前阶段状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| S0 规范冻结 | 进行中 | 当前法源已建立；剩余P0不变量未全部实现 |
| S1 新表与Repository | 已完成影子底座 | 内存SQLite与旧全量回归通过；未迁移既有文件库 |
| S2 旧数据回填 | 未开始 | 无正式migration/backfill工具 |
| S3 影子验证 | 未开始 | 尚无旧/新导出hash parity |
| S4 一次切换 | 未开始 | 禁止执行 |
| S5 移除旧权威后门 | 未开始 | 旧CLI仍是唯一生产路径 |
| S6 真实试点 | 未开始 | 待前三类章节A/B |

## S0：规范冻结

- 完成 `design.md`、`implementation-contract.md`；
- 完成 Scene-first P0 不变量；
- 定义 Scene 边界识别规则；
- 定义 Branch-local expected parent；
- 定义 Snapshot Accept 事务；
- 冻结旧 Shot schema 的新增功能。

退出条件：实现团队无需读取归档文档即可编码。

## S1：新表与Repository

- 新增 Scene/Contract/Revision/Branch/Snapshot/Head 表；
- 新增不可变 trigger 和唯一索引；
- 新增 SceneRepository、ChapterSnapshotRepository；
- 旧生产路径保持唯一权威；
- 新表只允许测试和 dry-run。

退出条件：内存SQLite测试通过，旧测试无回归。

当前结果：退出条件已满足；但这只表示影子底座完成，不表示既有生产数据库已经拥有新表。

## S2：旧数据回填

对每个 accepted 章节：

1. 读取旧 Shot 顺序和正文；
2. 生成 proposed Scene boundaries；
3. 记录置信度和歧义原因；
4. 低置信边界进入 DecisionSession；
5. 创建初始 Scene、Scene Revision；
6. 创建初始 Branch Version；
7. 创建初始 Chapter Snapshot；
8. 保存 legacy Shot lineage。

退出条件：所有 accepted 章节都有可追溯 Snapshot。

## S3：影子验证

比较：

```text
旧 accepted 导出
vs
新 Snapshot 导出
```

必须验证：

- 文本hash；
- Scene顺序；
- 标题与分隔；
- 来源血缘；
- Fact Anchor；
- 长篇连续性。

影子输出不对外，不进入正式上下文。

退出条件：差异为零，或全部有作者批准的差异记录。

## S4：一次切换

1. 备份生产库；
2. 暂停写入；
3. 完成增量回填；
4. 运行 FK、hash、唯一性和不可变检查；
5. 切换 accept/export/context/review 到 Scene-first；
6. 设置 schema marker；
7. 旧 Shot 正文路径改只读；
8. 恢复写入。

失败时恢复备份，不允许半切换。

## S5：移除旧权威后门

- export 不再读 `v_current_text`；
- accept 不再 hard-seal Shot；
- repair 命令定位 Scene；
- Shot 仅作为 Internal Shot；
- SQL lint 阻断新代码访问 legacy canonical 路径；
- 旧表归档，不急于删除。

## S6：真实试点

选择至少三类章节：

1. 工业/动作；
2. 人物关系/潜台词；
3. 低强度过渡/留白。

每类比较 Shot-first 历史结果与 Scene-first 新结果，记录：

- 作者偏好；
- 场景整体性；
- 人物可信度；
- 候选差异；
- 返工次数；
- 调用成本；
- 评审分歧；
- 少数冠军命中。

通过后才宣布 Scene-first 投产。
