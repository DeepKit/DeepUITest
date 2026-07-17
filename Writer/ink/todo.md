# InkFlow v2 工作快照（todo）

> **用途**：近期完成工作与尚未闭环事项。长期队列见 `tasks.md`，缺陷见 `bugfix.md`，里程碑见 `history.md`。
> **最后更新**：2026-07-11

---

## ✅ 近期已完成

### P0 跨章质量病灶全部落地

1. **末段 POV 无转场切换**
   - jury prompt 新增最后 25% POV/全知滑出硬审计。
   - chapter review 新增结构化 `pov_tail_audit`；违规独立写入 `pov_tail_transition` blocking issue，不允许被平均分掩盖。
   - 生产 c03 旧稿真实复评准确检出林远征末段 POV 切换；修订稿又检出“有限视角滑成作者结论”，经真实模型定点修订后通过。

2. **章续硬衔接**
   - 新增 `core/chapter_continuity.py`，通过 `TextRepository` 读取同章上一 shot 或上一章最终正文。
   - continuity context 同时注入 outline 和 task card，要求开头承接人物位置、时间、未完成动作/悬念；切时空/POV 必须显式锚点。
   - chapter review 新增结构化 `continuity_audit` 和 `chapter_continuity_anchor` blocking issue。

3. **工业失效机制判据**
   - 事实漂移 prompt 区分 `observation_only / causal_claim / institutional_claim`。
   - 只有正文明确作因果断言，且缺可观测参数或“条件→材料/工艺变化→缺陷→后果”链，才判 `failure_mechanism_vague`。
   - “微裂纹像蛛网”“露天堆放四天”等具体症状/背景线索不再被误判为机理结论。

### 真实模型与生产验收

- 本机 WiseGateway `127.0.0.1:8000/v1` 真模型池已用于全部最终验收，`mock_used=false`。
- 真实 failover：primary 故意配置不存在模型，收到 HTTP 400 后自动切到 secondary `claude-xunfei-glm-5-1` 成功；`model_role_failover` event 已落库。
- 生产 DB 已备份并改为本地代理模型映射；atomic clauses 已确认存在 11 条，不再阻塞。
- 生产 c03：
  - run2：4 shot 全 `soft_sealed`，初评高分，但新程序门检出 polish 元话语，质量门回退为 false。
  - run3：4 shot 全 `soft_sealed`；定点 POV 修订后 review_id=4：
    - chapter continuity 92
    - POV 95
    - character 88
    - hook 90
    - rhythm 85
    - motif 78
    - info-gap 89
    - `quality_gate_passed=1`、`blocking_issues=[]`
  - 4 shot 正文无“好的，收到 / 以下是润色版本 / 调整说明 / markdown fence”等出版污染。

### 真实实跑额外修复

- outline drift 从 Jaccard 改为“契约源 bigram recall”，详细长大纲不再因正常扩写被长度惩罚。
- polish 新增出版正文提取/元话语清洗；hard gate 与 chapter review 同时增加 `publication_artifact` 防线。
- chapter review 重评在调用 LLM 前清理旧 idempotency attempt，修复 UNIQUE 冲突。
- 本地代理/官方 baseline 文件 DB 脚本补 commit/rollback；不再出现快照有内容但 DB 关闭后为空库。
- 默认测试恢复离线快速执行；真实 6/10 章 pytest 验收需显式设置 `INK_RUN_REAL_LLM_TESTS=1`。
- 全量离线回归：`431 passed, 9 skipped`；9 个 skip 全是显式 opt-in 的真实供应商测试。
- PostgreSQL adapter 边界已实现：SQLite/PG adapter、mapping row、参数占位符安全转换、transaction-local RLS auth context、同 shot/run advisory lock；fake-driver 与 SQLite 边界测试通过。尚缺真实 PostgreSQL schema/RLS 集成，未虚报上线。
- Event log replay CLI 已实现：可重建 session/contract 最新状态，也可用 `--at-event-id` / `--at-time` 查看历史切片。
- Shot 级 source-clause coverage 已闭环：可列出每个 shot 的 book/chapter/shot 适用条款、gap/conflict 和正文/草稿证据，并追加审计记录。
- 批量 chapter review 已实现：章节范围解析、单 gateway 连续真实评审、fail-fast/continue-on-error 汇总。
- 个人生产上线已完成：新增 `ink doctor` 和完整性校验 backup；《白灯法则》生产 DB doctor 无 blocking failure，真实代理冒烟通过，正式上线备份已生成。

---

## ⏳ 尚未闭环

### P0/P1 生产质量

1. **c03 人工接受**：run3 已过全部程序质量门，但按系统铁律仍需作者本人决定是否 `accept`；AI 不代替作者作正式接受裁决。
### 非个人上线阻断项

2. PostgreSQL schema/RLS：用户当前明确不考虑团队服务器。
3. CLI TUI、通用导入向导、契约 diff：均为体验增强，不阻断《白灯法则》继续生产。
4. 当前目录不是独立 Git worktree；本轮未擅自提交。
