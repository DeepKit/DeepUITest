# OCGS.077-DeepJourney标准业务旅程包Schema

> 文档性质：数据结构 / Schema 草案  
> 产品：DeepJourney 企业版  
> 对象：BusinessJourneyPackage / 标准业务旅程包  
> 版本：v0.1  
> 底层方法：OCGS

---

## 0. Schema 目标

标准业务旅程包用于把企业专家经验封装成可执行、可播放、可检查、可恢复、可留痕的业务旅程。

它不是普通流程文档，而是一个结构化运行包，必须支持：明确宝物、意图匹配、图卡/步骤播放、分支路由、风险确认、迷路恢复、版本管理、执行留痕、测试与封版。

---

## 1. 顶层结构

```json
{
  "package_key": "tax.invoice_check.v1",
  "package_name": "发票核验业务旅程包",
  "package_type": "business_journey",
  "version": "1.0.0",
  "status": "draft",
  "domain": "tax_service",
  "owner_org": "某税务服务中心",
  "outputs": [],
  "intent_triggers": [],
  "journeys": [],
  "fields": [],
  "gates": [],
  "guide_cards": [],
  "route_rules": [],
  "risk_policies": [],
  "lost_recoveries": [],
  "trace_schema": {},
  "test_cases": [],
  "human_decision_log": []
}
```

---

## 2. Package 元信息

```json
{
  "package_key": "string",
  "package_name": "string",
  "package_type": "business_journey",
  "version": "string",
  "status": "draft | reviewed | published | deprecated | archived",
  "domain": "string",
  "owner_org": "string",
  "created_by": "string",
  "reviewed_by": ["string"],
  "published_at": "datetime | null",
  "effective_from": "datetime | null",
  "effective_to": "datetime | null"
}
```

状态说明：draft 草稿不可前台使用；reviewed 已审核待发布；published 前台 Coach 可用；deprecated 被新版本替代但可查；archived 归档。

---

## 3. Output / 宝物定义

```json
{
  "output_key": "invoice_check.completed",
  "output_name": "完成发票核验",
  "description": "一线人员成功完成客户发票真实性与合规性核验。",
  "final_state": [
    "客户身份已确认",
    "发票信息已核验",
    "系统记录已保存",
    "风险提示已处理",
    "客户已获得明确结果"
  ],
  "risk_level": "L1",
  "evidence_required": true,
  "completion_gate_key": "gate.invoice_check.verify_result"
}
```

每个旅程包必须至少有一个 Output。宝物是倒推门禁的起点。

---

## 4. IntentTrigger / 意图触发

```json
{
  "intent_key": "intent.invoice_check",
  "phrases": [
    "我要核验发票",
    "客户要查发票",
    "怎么判断这张发票能不能用",
    "发票真假怎么查"
  ],
  "normalized_intent": "invoice_check",
  "entities": [{"name": "invoice_type", "required": false}],
  "candidate_outputs": ["invoice_check.completed"],
  "confidence_threshold": 0.75,
  "fallback_question": "你是要核验发票真实性，还是检查报销材料？"
}
```

要求：每个旅程包配置常见说法；低置信度必须给数字候选；不允许低置信度直接进入高风险旅程。

---

## 5. BusinessJourney / 业务旅程

```json
{
  "journey_key": "journey.invoice_check.standard",
  "journey_name": "发票核验标准旅程",
  "output_key": "invoice_check.completed",
  "start_gate_key": "gate.customer_intent_confirm",
  "start_card_key": "card.customer_intent_confirm",
  "mode": "guide",
  "audience": "frontline_new_employee",
  "steps": [
    {"step_no": 1, "gate_key": "gate.customer_intent_confirm", "card_key": "card.customer_intent_confirm"}
  ]
}
```

一个 Output 可以有多条 Journey，如标准办理旅程、新人简化旅程、专家快速旅程、异常处理旅程。

---

## 6. Field / 场域定义

```json
{
  "field_key": "field.customer_reception",
  "field_name": "客户接待场域",
  "field_type": "conversation | system_page | document_check | decision | confirmation | risk | completion",
  "description": "一线员工与客户确认办理目标的场域。",
  "parent_field_key": null,
  "visual_context": {
    "has_screen": false,
    "has_form": false,
    "has_customer_dialogue": true
  }
}
```

场域是用户当下所处的业务上下文。门禁必须归属于场域。

---

## 7. AccessGate / 门禁定义

```json
{
  "gate_key": "gate.invoice_material_ready",
  "gate_name": "发票材料齐全门",
  "gate_type": "ConditionGate",
  "field_key": "field.document_check",
  "description": "确认客户提供的发票材料是否齐全。",
  "conditions": [
    {
      "condition_key": "cond.invoice_image_exists",
      "condition_name": "发票图片或纸质票据存在",
      "required": true,
      "failure_feedback_key": "feedback.invoice_missing"
    }
  ],
  "next_routes": [
    {"route_key": "route.material_ready.to.system_input", "when": "all_required_conditions_pass", "target_gate_key": "gate.system_input"}
  ],
  "risk_level": "L1"
}
```

门类型建议：FieldGate、ConditionGate、ActionGate、StateGate、RiskGate、HumanConfirmGate、CompletionGate。

---

## 8. GuideCard / 图卡定义

```json
{
  "card_key": "card.invoice_material_check",
  "card_name": "检查发票材料",
  "gate_key": "gate.invoice_material_ready",
  "field_key": "field.document_check",
  "card_type": "visual_text",
  "title": "请先确认客户是否提供发票材料",
  "instruction": "请查看客户是否提供纸质发票、电子发票截图或发票号码。",
  "visual": {
    "visual_type": "focus_sketch",
    "anchors": [
      {"anchor_key": "anchor.invoice_material", "role": "primary_focus", "style": "pink_solid", "label": "发票材料"}
    ]
  },
  "buttons": [
    {"index": 1, "label": "材料齐全", "route_key": "route.material_ready"},
    {"index": 2, "label": "材料不齐", "route_key": "route.material_missing"},
    {"index": 3, "label": "我不确定", "route_key": "route.ask_expert"}
  ]
}
```

所有前台候选必须使用 1-9 阿拉伯数字编号。

---

## 9. RouteRule / 路由规则

```json
{
  "route_key": "route.material_missing",
  "source_gate_key": "gate.invoice_material_ready",
  "trigger": {"type": "user_choice", "choice_index": 2},
  "target_gate_key": "gate.material_missing_recovery",
  "target_card_key": "card.material_missing_recovery",
  "trace_required": true
}
```

触发类型：user_choice、condition_pass、condition_fail、risk_confirmed、timeout、manual_jump、lost_recovery。

---

## 10. LostRecovery / 迷路恢复

```json
{
  "recovery_key": "recovery.invoice_page_not_found",
  "problem": "我找不到发票核验页面",
  "source_gate_key": "gate.system_input",
  "possible_causes": ["当前账号权限不足", "系统菜单位置变化", "用户进入了错误模块"],
  "choices": [
    {"index": 1, "label": "带我重新找入口", "target_gate_key": "gate.system_menu_entry"},
    {"index": 2, "label": "我已经在页面里了", "target_gate_key": "gate.system_input"},
    {"index": 3, "label": "呼叫专家", "target_gate_key": "gate.ask_expert"}
  ]
}
```

每个关键门至少有一个 LostRecovery。恢复项必须数字化，不能只写“联系管理员”，要给可执行下一步。

---

## 11. RiskPolicy / 风险策略

```json
{
  "risk_policy_key": "risk.invoice_submit",
  "risk_level": "L2",
  "description": "提交后会生成正式业务记录。",
  "confirm_required": true,
  "confirm_message": "提交后将生成正式业务记录，请确认信息无误。",
  "choices": [
    {"index": 1, "label": "确认提交", "action": "continue"},
    {"index": 2, "label": "返回检查", "action": "back_to_gate", "target_gate_key": "gate.final_check"}
  ],
  "trace_required": true
}
```

风险级别：L0 只读/浏览；L1 低风险可撤回；L2 影响业务记录/客户结果/已有配置；L3 高风险、不可逆、法律或资金相关。

---

## 12. TraceSchema / 留痕结构

```json
{
  "trace_schema": {
    "trace_required": true,
    "fields": ["user_id", "journey_key", "package_version", "gate_key", "card_key", "choice_index", "timestamp", "result", "risk_level", "evidence"]
  }
}
```

TraceEvent 应记录用户、旅程、版本、门、卡、选择、时间、结果、风险和证据。

---

## 13. TestCase / 测试样例

```json
{
  "test_case_key": "test.invoice_check.normal",
  "test_case_name": "发票核验正常路径",
  "journey_key": "journey.invoice_check.standard",
  "input_intent": "我要核验发票",
  "expected_output_key": "invoice_check.completed",
  "expected_route": ["gate.customer_intent_confirm", "gate.invoice_material_ready", "gate.system_input", "gate.invoice_submit_confirm", "gate.invoice_check_completed"],
  "expected_result": "success"
}
```

测试类型：normal_path、branch_path、risk_path、lost_recovery_path、invalid_input、permission_denied。

---

## 14. HumanDecisionLog

```json
{
  "decision_id": "hdl_001",
  "topic": "宝物定义",
  "question": "本旅程最终要让一线员工完成什么结果？",
  "options": ["完成发票核验", "完成发票报销", "完成客户咨询"],
  "selected": "完成发票核验",
  "reason": "这是当前窗口业务最频繁且错误率较高的任务。",
  "decided_by": "业务专家A",
  "decided_at": "2026-05-12T10:00:00"
}
```

HumanDecisionLog 用于记录 AI 主持式倒推过程中人类的关键选择。

---

## 15. 可发布包最小要求

一个可发布的 BusinessJourneyPackage 至少必须包含：Package 元信息、至少 1 个 Output、至少 1 个 IntentTrigger、至少 1 条 Journey、至少 1 个 CompletionGate、所有 Journey Step 对应 GuideCard、有效 RouteRule、高风险 RiskPolicy、关键 LostRecovery、至少 1 个正常路径测试样例、审核记录、版本号。

---

## 16. Schema 校验规则

发布前必须检查：每个 journey 有 start_gate；每个 step 绑定有效 gate；每个 gate 有 field；每个 card 有 gate；每个 route 的 target_gate 存在；高风险 gate 有 RiskPolicy；CompletionGate 能到达 Output；数字候选不超过 9 项；所有前台选择项有阿拉伯数字 index；关键 gate 至少有 LostRecovery；draft 未审核不得发布。

---

## 17. 一句话总结

> DeepJourney 标准业务旅程包不是文档，而是一个可运行的 OCGS 业务能力包。它把宝物、场域、门禁、图卡、路由、风险、恢复、测试、留痕和人类决策记录组织在一起，使企业专家经验可以被前台助手播放、执行、检查和持续迭代。
