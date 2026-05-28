# Progee Lite 开发任务清�?
> **对外产品�?*: `Progee Lite`
> **内部项目/历史代号**: `DeepDevLite`
> **技术栈**: Delphi 12 FMX + SQLite + FastAPI + PostgreSQL
> **快速上�?*: 请先阅读 `docs/DeepDevLite-开发指�?md`

---

## 快速导�?
| 状�?| 数量 | 说明 |
|:----:|:----:|------|
| �?| 45+ | 已完成，可直接使�?|
| 🔄 | 1-2 | 正在开�?|
| �?| ~10 | 待开�?|

---

## 🎯 开发重�?
### 本周（P1�?
| ID | 任务 | 预计 | 状�?|
|----|------|------|:----:|
| P6-005 | 手动修改后重�?| 2h | �?|
| P8-011 | PDF导出功能 | 4h | �?|

### 下周（P2�?
| ID | 任务 | 预计 | 状�?|
|----|------|------|:----:|
| P2-006 | 本地环境检�?| 2h | �?|
| P11-004 | 主题切换 | 2h | �?|
| P11-005 | 多语言支持 | 4h | �?|

---

## 完整任务列表（按Phase分组�?
### Phase 5-9: 验证与输�?
| Phase | 完成�?|
|-------|--------|
| P5 | 6/7 |
| P6 | 4/6 |
| P7 | 5/6 |
| P8 | 9/10 |
| P9 | 11/12 |

---

## 编译信息

- **输出**: `bin\DeepDevLite.exe` (20MB，内部构建名)
- **编译**: Delphi dcc64 (Win64)

---

### Phase 7-12: 待完成任�?
| Phase | 状�?| 待完�?|
|-------|------|--------|
| P7 | 5/6 | P7-006 输出选项界面 |
| P8 | 9/10 | P8-010 PDF导出 |
| P9 | 11/12 | P9-012 卡片PDF导出 |
| P10 | 8/10 | 徽章服务收尾 |
| P11 | 2/5 | 主题/多语言 |
| P12 | 2/4 | 发布打包 |

---

### Phase 7: 输出功能

| ID | 任务 | 状�?|
|----|------|:----:|
| P7-006 | 输出选项界面 | �?|

---

### Phase 8-9: 报告与卡�?
| ID | 任务 | 状�?|
|----|------|:----:|
| P8-010 | PDF导出功能 | �?|
| P9-012 | 卡片PDF导出 | �?|

---

### Phase 11-12: 设置与发�?
| ID | 任务 | 状�?|
|----|------|:----:|
| P11-004 | 主题切换 | �?|
| P11-005 | 多语言支持 | �?|
| P12-004 | 发布打包 | �?|

---

## 核心文件速查

### Delphi

| 文件 | 用�?|
|------|------|
| ViewMain.pas | 主窗�?状态机 |
| CtrlAIAdapter.pas | AI调用 |
| CtrlContracts.pas | 契约解析 |
| CtrlTestRunner.pas | 测试执行 |
| CtrlCardGenerator.pas | 卡片生成 |
| prompts/*.txt | AI提示�?|

### Backend

| 文件 | 用�?|
|------|------|
| main.py | FastAPI入口 |
| Backend/ | 徽章服务 |
| requirements.txt | Python 依赖 |
| .env | 环境变量 |
| templates/verify.html | 验证详情页模�?|

### 其他文件

| 文件 | 说明 |
|------|------|
| sql/schema.sql | SQLite 数据库脚�?|
| prompts/*.txt | AI提示词模�?|

---

## 状态说�?
| 状�?| 说明 |
|:----:|------|
| �?| 已完�?|
| �?| 待开�?|
| 🔄 | 进行�?|
| �?| 已取�?|

---

## 📋 ODD 方法论优化建议（基于专家审阅�?
> **背景**: `Progee Lite` �?ODD L1.5 增强层的落地实践，以下优化建议来自对 ODD 全套文档的深度审阅�?
### 当前定位

**Progee Lite = L1.5 增强�?*
```
AI生成契约 + 本地自动验证 + 软封存（本地哈希+徽章�?```

**已实现的 ODD 核心概念**�?- �?契约：AI推导 + 用户确认 + YAML输出 + Given-When-Then
- �?产出物：单文件验证闭�?+ 封存标记
- ⚠️ 门禁：PASS/FAIL判定（缺FREEZE状态）
- �?证据：验证报�?+ SHA-256 + 徽章服务
- �?封存�?seal.txt + 代码注释 + 证据�?
---

### Phase 13: ODD 理论增强（短�?1-2周）

| ID | 任务 | 优先�?| 预计 | 状�?| 说明 |
|----|------|--------|------|:----:|------|
| P13-001 | 契约质量评分 | P1 | 4h | �?| 在契约确认界面显示质量评分（完整�?清晰�?防御性），并给出改进建议 |
| P13-002 | FREEZE状态模�?| P1 | 2h | �?| 3轮修复仍失败时，标记�?需人工审查"而非直接失败 |
| P13-003 | L1.5定位说明 | P2 | 1h | �?| 在首�?ODD 介绍中明�?`Progee Lite = L1.5` 级工具，�?L1/L2 的区�?|
| P13-004 | 契约编写指导 | P2 | 3h | �?| 添加"如何写防弹契�?的交互式提示（边界条件检查清单） |
| P13-005 | 快照契约支持 | P2 | 6h | �?| 支持遗留代码的快照契约模式（录制输入输出作为基线�?|

**P13-001 实现要点**�?```pascal
// 契约质量评分算法
function EvaluateContractQuality(Contract: TContract): TQualityScore;
begin
  Result.Completeness := 
    (Length(Contract.Scenarios) >= 3) and
    (HasNormalCase and HasEdgeCase and HasErrorCase);
  
  Result.Clarity := 
    (Contract.Purpose.Length >= 20) and
    (AllScenariosHaveGivenWhenThen);
  
  Result.Defensiveness := 
    (HasBoundaryConditions >= 3) and
    (HasSecurityCheck);
  
  Result.Overall := (Result.Completeness + Result.Clarity + Result.Defensiveness) / 3;
  Result.Suggestions := GenerateSuggestions(Result);
end;
```

**P13-002 实现要点**�?```pascal
// �?HandleTestResults 中添�?if FRetryCount >= 3 then
begin
  SetState(vsFrozen);  // 新增状�?  ShowFreezeDialog(
    '验证无法自动通过，需要人工审查�? + #13#10 +
    '可能原因�? + #13#10 +
    '1. 契约定义与代码实现存在根本性矛�? + #13#10 +
    '2. 测试环境配置问题' + #13#10 +
    '3. AI模型理解偏差' + #13#10 +
    #13#10 +
    '建议：手动检查契约和代码，或联系技术支持�?
  );
end;
```

---

### Phase 14: 数据驱动优化（中�?1-2月）

| ID | 任务 | 优先�?| 预计 | 状�?| 说明 |
|----|------|--------|------|:----:|------|
| P14-001 | 契约逻辑静态检�?| P1 | 8h | �?| 分析契约中是否有互斥条件（如"A>0"�?A<0"同时存在�?|
| P14-002 | 徽章数据实证分析 | P1 | 6h | �?| 利用PostgreSQL统计通过率、返工率、模型效果对�?|
| P14-003 | 契约保鲜机制 | P2 | 4h | �?| 添加review_after字段，到期提醒用户复核契�?|
| P14-004 | 失效案例收集 | P2 | 6h | �?| 添加"验证通过但实际有问题"的反馈入口，建立失效案例�?|
| P14-005 | 模型效果对比 | P3 | 8h | �?| 统计Tier1/2/3模型的成功率、成本、速度，优化赛马策�?|

**P14-001 实现要点**�?```pascal
// 契约逻辑冲突检�?function DetectContractConflicts(Contract: TContract): TArray<string>;
var
  Conflicts: TArray<string>;
begin
  // 检测互斥条�?  if HasCondition('> 0') and HasCondition('< 0') then
    Conflicts := Conflicts + ['发现互斥条件：同一变量既要�?0又要�?0'];
  
  // 检测覆盖不�?  if not HasBoundaryCheck('空�?) then
    Conflicts := Conflicts + ['缺少空值边界检�?];
  
  // 检测安全漏�?  if HasUserInput and not HasSanitization then
    Conflicts := Conflicts + ['用户输入未进行安全校�?];
  
  Result := Conflicts;
end;
```

**P14-002 实现要点**�?```sql
-- 在徽章服务中添加统计视图
CREATE VIEW progeelite_analytics AS
SELECT
  language,
  model_used,
  AVG(CASE WHEN scenario_pass = scenario_total THEN 1.0 ELSE 0.0 END) AS pass_rate,
  AVG(retry_count) AS avg_retries,
  COUNT(*) AS total_verifications,
  AVG(scenario_total) AS avg_scenarios
FROM progeelite_badges
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY language, model_used
ORDER BY pass_rate DESC;
```

---

### Phase 15: 工具形态演进（长期 3-6月）

| ID | 任务 | 优先�?| 预计 | 状�?| 说明 |
|----|------|--------|------|:----:|------|
| P15-001 | VS Code 插件原型 | P1 | 40h | �?| 实现IDE集成，真正的"无感践行ODD" |
| P15-002 | FREEZE状态完整实�?| P2 | 16h | �?| 人工裁决界面 + 裁决记录 + 知识积累 |
| P15-003 | CAP对抗模式 | P2 | 24h | �?| Proposer/Challenger角色分离，自动化对抗博弈 |
| P15-004 | 用户反馈闭环 | P2 | 12h | �?| 收集线上实际问题，反哺契约模板库 |
| P15-005 | 契约模式�?| P3 | 20h | �?| 针对CRUD/Auth/Payment等常见场景的契约模板 |

**P15-001 核心价�?*�?```
专家判词�?不要让用户读文档来学习ODD，要让用户用工具来无感践行ODD�?

VS Code插件实现�?1. 右键菜单"验证此文�?
2. 实时契约质量提示（红色波浪线标记冲突�?3. 验证结果内嵌显示（无需切换窗口�?4. 自动封存�?seal.txt（无需手动操作�?```

**P15-003 CAP对抗实现**�?```yaml
cap_automation:
  max_rounds: 5
  roles:
    proposer: "claude-sonnet-4"    # 写契�?    challenger: "gpt-4o"            # 攻击契约
  convergence_check: "challenger找不到新漏洞"
  final_report:
    require_human_sign: true
```

---

### 关键差距与改进路�?
| 专家建议 | Progee Lite 现状 | 差距 | 改进路径 |
|----------|----------------|------|----------|
| L1.5为核心推�?| �?已实现L1.5 | 定位说明不够 | P13-003 |
| 工具链（IDE插件�?| ⚠️ 独立桌面应用 | 不是IDE集成 | P15-001 |
| 人类仲裁者培�?| ⚠️ 有契约确�?| 无防弹契约指�?| P13-004 |
| 失效安全�?| �?�?| 无偏差检�?| P14-004 |
| 实证研究 | ⚠️ 有徽章数�?| 缺统计分�?| P14-002 |

---

### 实施优先级总结

**立即启动（本月）**�?- P13-001 契约质量评分（提升用户契约编写能力）
- P13-002 FREEZE状态模拟（避免"强行判定"的异化）
- P14-002 徽章数据分析（用数据证明ODD有效性）

**近期规划（下月）**�?- P14-001 契约逻辑检查（降低契约错误率）
- P14-003 契约保鲜机制（避免契约过期失效）
- P13-005 快照契约支持（降低遗留系统接入阻抗）

**中长期愿景（Q2-Q3�?*�?- P15-001 VS Code插件（实�?无感践行"�?- P15-003 CAP对抗模式（提升契约防御性）
- P15-005 契约模式库（降低契约编写成本�?
---

### 参考文�?
- `D:\_Progs\01Center\ODD\ODD-main\docs\E21.哲学_术语表与优化记录.md` �?ODD优化建议�?6条）
- `D:\_Progs\01Center\ODD\ODD-main\docs\A03.了解_评级与选型指南.md` �?L0-L3等级体系
- `D:\_Progs\01Center\ODD\ODD-main\docs\C13.工程_验证_门禁_状态机.md` �?FREEZE状态定�?- `D:\_Progs\01Center\ODD\ODD-main\docs\E19.哲学_底层演算与对齐基�?md` �?五大原理与认知不对称

---

## 🐍 odd-core：Python �?ODD 引擎（规划中�?
> **状�?*: 方向已定，商业模式待讨论后确定开源层�?> **核心目标**: 构建社区生态，�?ODD �?一个人的方法论"变成"一群人的实�?

### 战略定位

**为什么用 Python？不是为了替�?Delphi，是为了构建社区�?*

- Delphi 太小众，无法形成贡献者社�?- Python 生态成熟，pip install 即用，降低准入门�?- 开�?Python 项目天然具备社区传播�?
### �?Progee Lite 的上下游关系

```
Progee Lite（Delphi�?           odd-core（Python�?─────────────────              ──────────────────
入门体验工具                      专业生产工具
拖拽验证 + 朋友圈卡�?            CLI + CI/CD + 插件生�?获客：让�?看到"ODD               留存：让�?用上"ODD
单文件，零配�?                   项目级，可配�?L1.5 固定流程                    L1.5 �?L2 �?L3 可升�?```

### 架构设计（可插拔引擎�?
```
odd-core（核心引擎，我们维护�?├── odd.contract    �?契约解析 / 验证 / 版本管理
├── odd.gate        �?门禁引擎（PASS / FAIL / FREEZE�?├── odd.seal        �?封存（哈�?+ 证据链）
├── odd.runner      �?测试执行�?└── odd.cli         �?命令行入�?
odd-plugins（社区贡献）
├── odd-ai-claude   �?Claude 适配�?├── odd-ai-openai   �?OpenAI 适配�?├── odd-lang-python �?Python 语言支持
├── odd-lang-js     �?JavaScript 语言支持
├── odd-seal-git    �?Git Tag 封存
├── odd-seal-s3     �?S3 封存
└── ...

odd-registry（共享资源）
├── contracts/      �?契约模板�?├── prompts/        �?AI 提示词库
├── rules/          �?门禁规则�?└── cases/          �?失效案例�?```

### 社区可共享的资源

| 资源类型 | 说明 | 社区价�?|
|----------|------|----------|
| 契约模板 | CRUD/Auth/Payment 等场景的标准契约 | 极高 �?降低契约编写成本 |
| 验证插件 | 针对特定语言/框架的验证器 | �?�?扩展语言支持 |
| AI Prompt 模板 | 契约推导/测试生成/修复的提示词 | �?�?社区优化提示词质�?|
| 门禁规则 | 自定义的 PASS/FAIL/FREEZE 判定逻辑 | �?�?行业特定规则 |
| 封存适配�?| 对接不同存储（Git/S3/IPFS）的封存后端 | �?�?企业集成 |
| 失效案例 | "我按ODD做了但失败了"的案�?| 极高 �?方法论迭代的核心输入 |

### 用户使用方式（预期）

```bash
# 安装
pip install odd-core

# 初始化项�?odd init

# 从社区拉取契约模�?odd template pull auth/login-basic
odd template pull crud/rest-api

# 验证单文件（Progee Lite CLI 平替�?odd verify login.py

# 验证整个项目
odd verify --all

# 查看契约状�?odd status

# 封存
odd seal

# 贡献契约模板到社�?odd template push my-payment-contract
```

### MVP 范围（第一版）

| 功能 | 说明 | 优先�?|
|------|------|--------|
| `odd verify <file>` | 单文件验证（Progee Lite CLI 平替�?| P0 |
| `odd init` | 项目初始化（生成 odd.yaml�?| P0 |
| `odd status` | 查看契约/封存状�?| P0 |
| `odd seal` | 封存 | P0 |
| 插件机制骨架 | 第一版只内置 Python + Claude | P0 |
| `odd verify --all` | 项目级多文件验证 | P1 |
| `odd template pull/push` | 契约模板共享 | P1 |
| FREEZE 状�?| 机器无法判定时的人类裁决 | P1 |

### ⚠️ 待决策：商业模式（最高优先级�?
**商业模式决定开源层次。以下问题需要先讨论清楚�?*

1. **核心引擎的开源程�?*
   - 完全开源（MIT/Apache）→ 最利于社区，但商业化需另找路径
   - 核心开�?+ 高级功能付费 �?Open Core 模式（类�?GitLab�?   - 核心开�?+ 托管服务付费 �?SaaS 模式（类�?GitHub Actions�?
2. **收入来源候�?*
   - 契约模板市场（社区免�?+ 企业级付费模板）
   - 托管封存服务（证据链云端存储 + 审计合规�?   - 企业版功能（团队协作、权限管理、审计报告）
   - AI 调用代理（统一 API Key 管理 + 用量计费�?   - 培训与认证（ODD 认证开发�?/ 认证团队�?   - 咨询服务（ODD 落地咨询�?
3. **社区与商业的边界**
   - 哪些功能永远免费？（决定社区信任度）
   - 哪些功能可以收费？（决定商业可持续性）
   - 社区贡献者的激励机制？（决定生态活力）

4. **竞争壁垒**
   - 如果完全开源，别人 fork 一份怎么办？
   - ODD 方法论本身是公开的，工具的护城河在哪�?   - 是靠"社区网络效应"还是"技术领先�?�?
**结论：先把商业模式想清楚，再决定代码写多少、开源多少�?*
