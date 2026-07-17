# Ink v2 Scene-first 踩坑清单

1. 不把Shot重新升级为正式正文原子。
2. 不从latest/current Scene动态拼正式章节。
3. 不把Revision不可变误写成Canonical。
4. 不用全局Scene Head阻断合法候选分叉。
5. 不在Frozen Branch上原地替换Scene。
6. 不在Snapshot创建后修改Scene绑定。
7. 不允许AI执行accept、activate或更新Chapter Head。
8. 不让文件或导出物反向覆盖数据库。
9. 不把DB没有记录解释为事实不存在。
10. 不把软目标失败升级为越来越多的禁令。
11. 不把人类原稿整篇注入成隐性external draft。
12. 不把Guidance Card变成常驻模板。
13. 不以平均分强迫选出平庸winner。
14. 不把不同模型家族误认为不同审美。
15. 不让裁判看到其他裁判结论。
16. 不允许同一模型自评自己的候选。
17. 不在首批0篇过线时继续无界补稿。
18. 不把影子验证误称为双权威生产。
19. 不直接全局重命名Shot表为Scene表。
20. 不在缺少新不变量测试时切换生产库。
21. 不在文档、日志或测试中保存真实API密钥。
22. 不用固定阈值代替真实章节校准。
23. 不把库里游荡但 schema.sql/迁移/源码无定义的表当作正式权威表（BFX-093：`writing_schema_authority` 是 ad-hoc 手工建的游离表，新库不回灌，重建不创建，引用它当权威的描述已过时，改引 `schema_migrations`）。
24. 不靠人工记忆"跑了哪个 migrate_*.py"——统一迁移跟踪 `migrate_db` 按 `sql/migrations/` 文件名序幂等应用并写 `schema_migrations` 注册表（BFX-092），新迁移文件只追加不修改、命名 `YYYY-MM-DD_<slug>.sql`。
