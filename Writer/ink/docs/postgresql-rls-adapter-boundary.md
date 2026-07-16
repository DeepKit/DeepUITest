# Scene-first PostgreSQL / RLS 边界

## 已实现的跨数据库适配器契约

- `connect(...)` returns rows addressable by column name，同时保留整数索引兼容；
- `transaction(conn)` commits on normal exit and rolls back on exception；
- transaction-local auth context 必须携带 project/session/actor 身份；
- 相同工作单元可使用 `pg_advisory_xact_lock` 串行化；
- No business module should contain PostgreSQL-only SQL，后端差异留在 adapter 或显式迁移层；
- 真实服务验收必须证明 RLS denies cross-project reads and writes。

## SQLite 当前边界

- 单作者本地运行；
- WAL；
- 单写入队列；
- Accept使用`BEGIN IMMEDIATE`；
- trigger保护不可变Revision/Snapshot；
- SQL lint限制正文表访问。

## PostgreSQL 锁

| 操作 | 锁粒度 |
|---|---|
| 创建Scene Revision | branch_id + scene_id |
| 冻结Branch Version | branch_version_id |
| 激活Scene Contract | scene_id |
| Accept Chapter | project_id + chapter_id |
| 更新Chapter Head | row lock + CAS version |

不能仅把旧shot advisory lock改名为scene lock；章节Accept跨多个Scene，必须是章节级事务。

## RLS角色

| 角色 | 权限 |
|---|---|
| ai_writer | INSERT candidate Scene Revision |
| ai_reviewer | INSERT review |
| contract_architect | INSERT draft Contract/Amendment |
| contract_reviewer | INSERT contract review |
| human_editor | Accept/Reject/Activate |
| exporter | SELECT active Snapshot |

Revision和Snapshot表对普通角色撤销UPDATE/DELETE。

## Cutover

PostgreSQL迁移不能与Shot→Scene迁移混在同一不可回滚步骤。先在SQLite完成Scene-first权威链和真实试点，再迁移数据库后端。
