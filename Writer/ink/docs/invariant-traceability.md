# Ink v2 Scene-first 不变量与测试追踪

> 只把已有自动化证据的规则登记为正式 `INV-*`。尚未实现的门禁列在末节，
> 不能用“计划中的测试”冒充已落实不变量。旧 Shot 基线在 Cutover 前继续回归，
> 但不得扩展为新的正文权威。

## Scene-first 已执行不变量

| ID | 不变量 | 自动化证据 |
|---|---|---|
| INV-SCENE-001 | Scene Revision创建后不可UPDATE | `test_scene_revision_update_is_blocked_by_database_trigger` |
| INV-SCENE-002 | 被Branch/Snapshot引用的Revision不可DELETE | `test_referenced_scene_revision_cannot_be_deleted` |
| INV-INTERNAL-SHOT-001 | Internal Shot无accepted/canonical/seal字段 | `test_internal_shot_has_no_canonical_or_acceptance_columns` |
| INV-BRANCH-001 | Frozen Branch Version及绑定不可修改 | `test_frozen_branch_blocks_revision_and_binding_mutation` |
| INV-BRANCH-002 | expected parent按Branch-local Scene head校验，可合法并行分叉 | `test_two_branches_can_fork_from_same_branch_local_parent` |
| INV-SCENE-CAS-001 | 过期Branch-local parent写入失败 | `test_stale_branch_local_parent_is_rejected` |
| INV-SNAPSHOT-001 | Snapshot及其Scene绑定不可修改 | `test_snapshot_and_snapshot_bindings_are_immutable` |
| INV-SNAPSHOT-002 | 同一project/chapter只有一个Chapter Head | `test_chapter_head_is_unique_per_project_chapter` |
| INV-SNAPSHOT-003 | 后续Scene Revision不改变旧Snapshot读取 | `test_snapshot_text_does_not_follow_later_scene_revision` |
| INV-CHAPTER-CAS-001 | 过期Head version不能Accept且事务不遗留Snapshot或Decision | `test_stale_expected_head_version_rolls_back_without_new_snapshot` |
| INV-ACCEPT-001 | Accept同事务创建Selection Decision、Human Decision、sealed Snapshot、Head CAS与Runtime Event | `test_accept_creates_sealed_snapshot_and_active_head` |
| INV-ACCEPT-002 | Accept任一权威写入阶段失败时全部回滚，不留孤儿Decision或半成品Snapshot/Head/Event | `test_accept_fault_rolls_back_all_authority_rows` |
| INV-SCENE-CONTRACT-001 | 同一Scene最多一个active Contract | `test_same_scene_allows_only_one_active_contract` |
| INV-SCENE-AI-001 | AI Revision必须绑定generation或repair task | `test_ai_revision_requires_auditable_generation_or_repair_task` |
| INV-ROUND-001 | 合法跳转限于跳转表所列条目；表外非法 | `test_round_legal_transitions_advance`, `test_round_transition_not_in_table_is_illegal` |
| INV-ROUND-002 | 非法跳转抛`IllegalTransitionError` | `test_round_illegal_transition_raises_illegal_transition_error` |
| INV-ROUND-003 | 状态迁移CAS，过期写入抛`ConcurrentModificationError` | `test_round_cas_rejects_stale_expected_status` |
| INV-ROUND-004 | 首批0过线→终态`initial_zero_pass` | `test_round_initial_zero_pass_terminates_round` |
| INV-ROUND-005 | 补稿仅一次，`supplementing`唯一前置`validating_initial`且不可回流 | `test_round_supplement_only_once_from_validating_initial` |
| INV-ROUND-006 | `ready_for_selection`后`begin_selection`硬守eligible_count≥3 | `test_round_ready_for_selection_requires_three_eligible` |
| INV-ROUND-007 | 终态不可继续迁移（抛`TerminalStateError`）；`superseded`只能从非终态进入 | `test_round_terminal_state_rejects_further_transition`, `test_round_superseded_only_from_non_terminal` |
| INV-ROUND-008 | `record_eligible_branch`同事务branch CAS+round.eligible_count CAS（原子） | `test_record_eligible_branch_increments_count_atomically` |
| INV-ROUND-009 | `call_count`单调非减记账（本轮不熔断，熔断留P0） | `test_increment_call_count_is_monotonic` |
| INV-ROUND-010 | 恢复点`RoundState`含status/eligible/call/failure_reason/target counts | `test_get_round_state_returns_full_recovery_point` |
| INV-ROUND-011 | 驱动器：planned→全路径→selected | `test_driver_advances_planned_to_selected` |
| INV-ROUND-012 | 驱动器：首批0过线→initial_zero_pass | `test_driver_initial_zero_pass_on_zero_eligible` |
| INV-ROUND-013 | 驱动器：1-2过线→补3篇 | `test_driver_supplements_when_partial_initial_pass` |
| INV-ROUND-014 | 驱动器：补稿后<3→candidate_shortage | `test_driver_candidate_shortage_after_supplement` |
| INV-ROUND-015 | 驱动器：>=3但无实质差异→diversity_shortage | `test_driver_diversity_shortage_when_no_substantive_difference` |
| INV-ROUND-016 | 驱动器：call_count熔断→failed | `test_driver_call_count_circuit_breaker` |
| INV-ROUND-017 | 驱动器幂等恢复（从中间态续跑不重做） | `test_driver_resumes_from_intermediate_state` |
| INV-ROUND-018 | `start_validating_branch` CAS拒非generating | `test_start_validating_branch_cas_rejects_non_generating` |
| INV-ROUND-019 | `advance_to_literary_review` CAS拒非eligible | `test_advance_to_literary_review_cas_rejects_non_eligible` |

## Cutover前必须保持的旧基线不变量

以下ID仍由现有测试保护，用于证明Scene-first影子层没有破坏当前生产系统。
它们是迁移回归法源，不代表Shot仍是目标正文原子。

| ID | 保留门禁 |
|---|---|
| INV-CONTRACT-001 | 契约字段消费lint |
| INV-SQL-001 | 受保护表SQL访问lint |
| INV-DDL-001 | 全量DDL可执行 |
| INV-CONFIG-001 | 项目配置校验 |
| INV-TIME-001 | UTC时间格式 |
| INV-STATE-001 | 旧状态机合法转移 |
| INV-STATE-002 | 状态更新lint |
| INV-REVISION-001 | 旧`v_current_text`迁移基线单行读取 |
| INV-REVISION-002 | 旧恢复映射 |
| INV-RUN-001 | 四轴隔离 |
| INV-SOFT-001 | soft gate计数权威 |
| INV-SOFT-002 | redo幂等 |
| INV-LLM-001 | LLM失败与预算熔断 |
| INV-LLM-002 | 总调用预算 |
| INV-LLM-003 | 调用审计与访问lint |
| INV-QUALITY-001 | winner质量底线 |
| INV-QUALITY-002 | 单维质量底线 |
| INV-QUALITY-003 | 裁判分歧门 |
| INV-QUALITY-004 | polish后重新过门 |
| INV-QUALITY-005 | 章节质量阻断accept |
| INV-QUALITY-006 | 篇级blocking阻断accept/export |
| INV-QUALITY-007 | 人类不能越过质量硬门 |
| INV-QUALITY-008 | 质量报告证据结构 |
| INV-QUALITY-009 | blind review与reader pull |
| INV-QUALITY-010 | 保留有效偏离 |
| INV-QUALITY-011 | polish模型不可静默降级 |
| INV-JURY-SELF-001 | 禁止自评 |
| INV-JURY-ROUND-001 | 基础/升级裁判轮 |
| INV-CHECKPOINT-001 | session checkpoint |
| INV-RECOVERY-001 | checksum恢复 |
| INV-PROMPT-001 | prompt supersede |
| INV-OUTLINE-001 | outline drift与winner唯一 |
| INV-OUTLINE-002 | task card完整性 |
| INV-HUMAN-001 | 人类accept审计 |
| INV-AUDIT-001 | 失败归因 |
| INV-IMPORT-001 | 导入dry-run/finalize |
| INV-EXPORT-001 | 旧accepted-only导出基线 |
| INV-BOOK-001 | 篇级滚动检查 |
| INV-WORKFLOW-001 | 六章旧流程回归 |
| INV-GATE-001 | hard gate 1 |
| INV-GATE-002 | hard gate 2 |
| INV-FACT-001 | fact anchor门 |
| INV-JURY-001 | 三模型全维评分 |
| INV-JURY-002 | winner选择 |
| INV-FACT-002 | Fact Proposal confirm写入version_hash与review证据 | `test_confirm_writes_anchor_with_version_hash_and_review_evidence` |
| INV-FACT-003 | Fact Proposal reject持久化review证据 | `test_reject_persists_review_evidence` |
| INV-FACT-004 | 绑定Fact要求active契约+confirmed anchor | `test_bind_contract_fact_requires_active_contract_and_confirmed_anchor` |
| INV-FACT-005 | Fact supersede移动status并记replacement | `test_supersede_fact_anchor_moves_status_and_records_replacement` |
| INV-FACT-006 | Fact supersede要求新旧均confirmed | `test_supersede_requires_confirmed_old_and_new` |
| INV-FACT-007 | Fact deprecate置deprecated无replacement | `test_deprecate_fact_anchor_marks_deprecated_with_no_replacement` |
| INV-FACT-008 | Fact supersede后受影响Branch消费门fail-closed | `test_accept_gate_refuses_branch_after_fact_supersede` |
| INV-FACT-009 | sealed Snapshot读取遇stale Scene binding fail-closed | `test_active_snapshot_read_refuses_stale_after_fact_supersede` |
| INV-GUIDANCE-001 | Guidance Card创建即active | `test_apply_flips_active_to_applied_and_bumps_use_count` |
| INV-GUIDANCE-002 | apply翻转active→applied并+1 use_count | `test_apply_flips_active_to_applied_and_bumps_use_count` |
| INV-GUIDANCE-003 | 非active(dismissed/stale/applied)卡禁止apply | `test_apply_refuses_non_active_card`/`test_apply_refuses_reapply_after_applied` |
| INV-GUIDANCE-004 | apply执行max_uses上限 | `test_apply_enforces_max_uses_ceiling` |
| INV-GUIDANCE-005 | Fact supersede联动scene active卡转stale | `test_fact_supersede_flips_scene_active_cards_stale` |
| INV-GUIDANCE-006 | Contract supersede联动scene active卡转stale | `test_contract_supersede_flips_scene_active_cards_stale` |
| INV-GUIDANCE-007 | stale卡禁止apply到fresh产出 | `test_fact_supersede_flips_scene_active_cards_stale` |

## 尚未登记为已执行不变量的P0门禁

以下仍必须完成，状态以`../tasks.md`为准：

1. AI不能Accept、Activate、Freeze或绕过Repository更新Chapter Head的权限反事实；
2. Scene-first受保护权威表只能由指定Repository/schema/migration访问的SQL lint；
3. Scene、Chapter、Book与伦理硬门进入Scene-first Accept权威事务；
4. 候选差异绝对门槛与少数冠军的Scene-first全链生产证据；
5. 契约架构师与最终批准者分离的actor权限证据；
6. 旧导出与Snapshot导出的hash parity及Cutover/回滚演练。

> 已转正：Fact Proposal生命周期（INV-FACT-002~007）、Fact supersede消费门
> （INV-FACT-008）、sealed Snapshot read-path stale门（INV-FACT-009）、
> Guidance Card完整生命周期及Fact/Contract supersede联动stale
> （INV-GUIDANCE-001~007）。

## 验收门

Scene-first不得标记投产，除非：

1. 上述P0门禁全部转为有真实测试证据的`INV-*`；
2. 旧基线测试继续通过；
3. 三类真实章节完成A/B；
4. Snapshot导出与旧导出完成一致性验证；
5. 未发现双正文权威读取路径。
