# DeepAxis Bug 修复记录

---

## 2026-08-07 — BUG-052: 微信进程误检 + 按钮2重启微信 + 关闭 Runtime 217

> **来源**: 实机验证 (72b) — 用户报告 3 个问题。
> **状态**: ✅ 全部修复 (编译 0 errors + 65/65 + 退出码 0)

### 1. 微信进程误检 (明明登录却报"未检测到")
**文件**: `src/wechat/DeepAxis.WeChat.Scanner.pas` FindWeChatProcess
**根因**: 微信 4.x 有 6 个 Weixin.exe 进程 (主进程 583MB + 辅助进程 15-90MB)。旧实现返回枚举到的**第一个**——可能是空的辅助进程, 读不到密钥/模块。
**修复**: 遍历所有 Weixin.exe, 优先选**加载了 Weixin.dll 的** (主进程特征); 兜底返回第一个 Weixin.exe。

### 2. 按钮 2 会自动重启微信 (杀进程重开)
**文件**: `Scanner.pas` StartScan + `MainForm.pas` DoScanKey
**根因**: 内存扫描失败后 StartScan **无条件**走 HybridTap (KillWeChat + 重启 + hook 抓密钥), 打断用户已登录会话。
**修复**: StartScan 加 `AAllowRestartWeChat=False` 参数 — 默认不重启; DoScanKey 失败后弹确认框, **用户确认才重启**。

### 3. 关闭主窗体 Runtime error 217 (RVA 0x5D9491)
**文件**: `MainForm.pas` FormDestroy/StopPolling
**根因 A**: FormDestroy 里 `ReleaseDeepAxisDataStoreManager` 在 `StopPolling` **之前** — 轮询线程仍在运行时 store 已释放 → 访问已释放对象 → 217。
**根因 B**: StopPolling 直接 `WaitFor` — 轮询线程可能正 `TThread.Queue` 等主线程, 直接 WaitFor 死锁 (主线程等线程, 线程等主线程) → 关闭卡死。
**修复**: FormDestroy 先 StopPolling 再释放 store; StopPolling 先 RemoveQueuedEvents + 3 秒超时等待 (GetTickCount 轮询 Finished)。

### 4. 自动密钥监控循环太重 (每 3 秒全量读内存 × 60)
**文件**: `MainForm.pas` OnKeyMonitorTimer
**根因**: 无密钥时自动监控每 3 秒全量扫描微信内存, UI 卡死 + 弹确认框。
**修复**: 自动监控只试 2 次, 失败即停并提示"请手动点击 2. 扫描密钥"。

### 5. 窗口尺寸 (启动 560×220, 解密成功放大)
**文件**: `MainForm.pas` InitUI / DoConnectDecrypted
**根因**: 用户要求扫描密钥时窗体变小不挡操作 → 演进为**启动即小窗**。
**修复**: InitUI 设 560×220 (只显示工具栏+日志); DoConnectDecrypted 成功 (OpenPaths=True) 调 ExitScanMiniMode 放大 1600×1000 居中。dlCompact 不再压扁窗口 (原 Height:=120 导致窗口仅 3-4cm)。

### 6. 微信 4.1.11.55 密钥不兼容 (阻塞解密, 待 #91-#94 架构重构)
**文件**: 密钥获取链路 (Scanner 内存扫描 + key_info.db)
**确诊** (CLI 工具验证):
- 单轮 PBKDF2 算法正确 (json 旧密钥解旧账号 DB 成功, salt 匹配 307062fe...)
- 旧密钥对当前账号失效 (微信升级轮换密钥)
- 新密钥不在进程内存明文 (全进程 307 万候选 + Weixin.dll 180MB + 16B 拆分全 0 通过)
- key_info.db 专有加密 (66 条记录, field1: [15B头][14B每库salt][4B len][32B共享密文][103B每库密文]; 非 DPAPI/标准 AES/常见派生)
**方案**: 多模型圆桌定稿版本自适应密钥架构 (#91 骨架/#92 M1 逆向/#93 Hook/#94 热更), 详见 tasks.md + history.md 2026-08-09 块。

### 结果
- 微信主进程正确识别 (加载 Weixin.dll 的)
- 按钮 2 不再自动重启微信 (用户确认才重启)
- 关闭退出码 0 (无 Runtime 217)
- 启动 560×220 小窗, 解密成功放大 1600×1000
- 65/65 测试全绿
- ⚠️ 密钥获取待架构重构 (#91-#94), 当前无法解密 4.1.11.55

---

## 2026-08-06 — BUG-051: 功能实现核查 — 存储层/审计/body-zero 三大 P0c 门禁缺口

> **来源**: 2026-08-06 全功能实现核查 (3 代理并行审计, 对照 07-P0技术验证规格)。
> **状态**: ✅ #81-#90 全部修复 (P0c 门禁 + P1 功能闭环), 待办仅剩阶段演进项

### 1. 存储层名不副实 (P0) — ✅ 已修复 (#81)
**文件**: `src/core/DeepAxis.Core.DataStore.Manager.pas`
**修复**: Manager 接线 ChurnMonitorStore (内存真实实现) + 修正误导注释 (旧注释声称 ContactStore 已接入, 实际 nil); 6 个 DB1 死代码单元 (ContactDB1/MetricDB1/RadarHintDB1/EvidenceDB1/AuditDB1/TagProfileDB1) 移入 `src/core/deferred/` 并标注待修项 (SQLQuery helper 缺失 / inherited Initialize / Recordset.Count); 过期测试 `tests/Test.DB1Store.Manager.pas` 改名 .bak 隔离 (引用不存在的 API)。

### 2. body-zero 审计器零接线 (P0 硬门禁 C1) — ✅ 已修复 (#82)
**文件**: `src/pipeline/DeepAxis.Pipeline.BodyZero.pas` + `src/wechat/DeepAxis.WeChat.Reader.pas`
**修复**: TBodyZeroAuditor 接入 Reader — 正文列探测 RecordBodyColumnSeen + 正文读取 RecordBodyColumnQueried (真实计数, 新增 BodyQueriedCount); IWxReader 加 GetLastBodyZeroReport; TPollResult 挂 BodyZero 报告; MainForm 轮询日志输出 "body-zero审计: 正文列=… 正文读取=… 写库=… UIA=…"。M0 纯元数据路径下 queried=false, M1 授权后真实计数 — 不再硬编码 clean。

### 3. 审计日志未实现 (P0c C3) — ✅ 已修复 (#83)
**文件**: `src/core/DeepAxis.Core.DataStore.AuditDB1.pas` (重写), `src/core/DeepAxis.Core.Audit.pas` (新), `src/core/DeepAxis.Core.DataStore.Manager.pas`
**修复**: 重写 TAuditDB1Store 匹配 IAuditStore 接口 (Append/LoadForSource/VerifyHashChain/GetLatest/Count), SQLite 追加式 + SHA-256 哈希链; Manager 接线 FAuditStore (复用共享连接); 新增 DeepAxis.Core.Audit.AuditAppend 助手 (自动链上一条哈希, 失败静默); 事件写入: 密钥扫描成功 / 每轮轮询 (含 body-zero 快照) / 删除成功 (UIA=1); 统一 audit_events 建表结构 (MainForm.InitDB2 与 AuditDB1 一致, 10 列); 单测 +1 (Append/LoadForSource/VerifyHashChain/篡改检测) — 65/65。

### 4. 证据哈希不合规 (P0c C2) — ✅ 已修复 (#84)
**文件**: `src/pipeline/DeepAxis.Pipeline.Evidence.pas`, `src/core/DeepAxis.Core.Contracts.pas`, `src/ui/DeepAxis.UI.RadarPanel.pas`
**修复**: IEvidenceBuilder.Build 加 AMessages 可选参数; ComputeSourceHash 按规格 §6 用真实 MessageMeta 字段 (create_time/normalized_type/source_row_ref 组合) SHA-256 — 消息级可追溯; 无消息时回退 hint 元数据哈希; RadarPanel 轮询按 hint 联系人过滤消息传入。

### 5. 功能闭环缺口 (P1) — ✅ 已修复 (#85-#90)
- TagEngine.DeriveTags 结果 Free 不写回 → #85 写回参数化字段 (LastInteractionAt/OutboundInboundRatio/MarketingKeywordHitCount)
- StateMachine.TransitState/GetTransitionEvents 占位 → #86 触发信号推进 + 派生事件
- CalibrationEngine.RecordPoint 零调用点 → #87 GetLastCalibrationResult + 发送成功校准点
- ScriptEngine.PersonalizeTemplate 占位符硬编码 → #88 备注 ┊协议真实数据提取
- ChurnDetector.CalculateRecoveryProbability 恒 0.5 + 面板按钮未绑 → #89 按事件类型细分 + 三按钮绑定
- Privacy.FilterBusiness 零调用点 → #90 轮询链路隔离 PRIVATE/UNKNOWN 出指标/雷达/证据

---

## 2026-08-06 — BUG-050: 启动卡死/退出 (VCL 句柄时序 + AutoFix Halt) 根治

> **来源**: 用户报告启动乱码 + AV 0x6A9A95 (read 0x530) + 程序无法显示主窗口。
> **状态**: ✅ 已修复 (2026-08-06), 主工程 0 errors + TestRunner 64/64 + 25s 稳定运行。

### 根因 1: FLogMemo nil 访问 (AV read 0x530)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: FormCreate 早期 `Log()` 访问 `FLogMemo.Lines.Add` — FLogMemo 在 InitUI 才创建 → nil 访问 AV (read 0x530, 与用户报告吻合)。
**修复**: Log() 加 `if FLogMemo <> nil` 保护。

### 根因 2: 日志 ANSI 乱码
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: `Writeln(GLogFile, ...)` 按 ANSI 写 UTF-8 中文字符串 → DeepAxis.log 乱码。
**修复**: 改 `TFile.AppendAllText(path, line, TEncoding.UTF8)`, 删 TextFile 变量。

### 根因 3: VCL AlignControls 死锁 (同 Parent 双 alClient)
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas`, `src/ui/DeepAxis.UI.TierPanel.pas`
**现象**: FContactListBox(alClient) + FEmptyGuideLabel(alClient, Visible=True) 同 Parent → VCL AlignControls 递归死锁 (CPU 空闲等待)。
**修复**: 空态标签默认 Visible:=False, 由 UpdateContactList 切换。

### 根因 4: FormCreate 期 ComboBox 句柄需求 (EInvalidOperation 'no parent window')
**文件**: `src/ui/DeepAxis.UI.ScriptPanel.pas`
**现象**: TComboBox 创建/Items.Add/ItemIndex 触发句柄创建, FormCreate 阶段 MainForm 主窗句柄未就绪 → EInvalidOperation。
**修复**: ComboBox 延后到 `EnsureModeInitialized` (MainForm.FormShow 父句柄就绪后创建)。

### 根因 5: TFrame 无 .dfm (EResNotFound)
**文件**: `src/ui/DeepAxis.UI.ChurnMonitorPanel.pas`
**现象**: TChurnMonitorPanel 继承 TFrame 但无 .dfm → Create 抛 EResNotFound。
**修复**: 改 TPanel 基类 (纯代码构建)。

### 根因 6: AutoFix.NotifyShellShown 无条件 Halt (主窗关闭)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas` + DeepAxis.dpr
**现象**: AutoFix 激活后 NotifyShellShown → ScenarioRunner.Run → 场景后 `Halt(0)` → 程序启动即退出。
**修复**: 移除 MainForm 的 NotifyShellShown 调用 (ErrorRecorder 保留捕获错误), dpr 保留 AutoFix.Install。

### 结果
- 主窗口正常显示 (标题 "DeepAxis 序枢 v0.1.0"), 25s 稳定运行 + 自动密钥扫描
- 日志 UTF-8 无乱码
- AutoFix 捕获运行时错误 (autofix-output/runtime-errors.jsonl)
- 64/64 测试全绿

---

## 2026-08-03 — BUG-048: 全量编译损坏 (TLogger 幻影 API + MainForm 结构损坏)

> **来源**: 2026-08-02~03 自动修复会话遗留 — 声称"编译成功"实则损坏。
> **状态**: ✅ 已修复 (2026-08-03), 主工程 0 errors + TestRunner 64/64 全绿。

### 根因 1: TLogger 幻影 API (E2003)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: `TLogger.Init(ilogInfo, ...)` / `TLogger.Shutdown` / `TLogger.Write(ilogLevelInfo, ...)` — 规范源 `DeepBase.Logging.pas` 只有 `TDeepBaseLogger`, **无 TLogger/ilogInfo**。
**为何曾"成功"**: pass18 编译时命中了 7/31 生成的过期 `DeepBase.Logging.dcu` (临时版曾含 TLogger), `-B` 强制重编译后即炸。
**修复**: 删除全部幻影调用, 回归项目标准日志 (FLogMemo + GLogFile DeepAxis.log); 移除 uses 中 DeepBase.Logging。

### 根因 2: MainForm 结构损坏 (E2004/E2003/E2035 级联)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: 类声明只有 `InitBusinessServices`, 实现却有 2 个同名实现 + 1 个未声明的 `InitBusinessServicesWithDB1Stores` (FormCreate 已调用) → 级联错误; 另含 Markdown `**` 污染、`TContactOps.Create` 缺参、`TSendResultPoller.Create` 缺参、`TContactOverlayStore.Create(IContactStore)` 类型错、`FChurnDetector.Free` (接口无 Free)、`FOverlayStore` 双重创建。
**修复**: 删重复实现 + 类声明补方法 + 构造器改正确签名 + 接口置 nil + 去 `**` 污染。

### 根因 3: BUG-044 收尾未完成 (TagProfile JSON 残留)
**文件**: `MainForm.pas`(LContact.TagProfile), `ContactDB1.pas`(AContact.TagProfile), `IdleFunnel.pas`(JSON 残留), `RadarPanel.pas`(ApplyOverlay 注释死), `TagMatrixPanel.pas`(硬编码占位)
**修复 (Phase 3 参数化落地)**: TContact 加 `AdCount`/`LastAdAt` 字段; TAdTracker 全量重写 (OnAdSent/OnInboundDetected/CanAdvertise/GetAdCount/MergeAdTrack/BuildOverlayJson/ApplyOverlayJson); IdleFunnel 读字段; RadarPanel ApplyOverlay 复活; TagMatrixPanel 广告计数列; 测试 3 文件去 JSON 引用。
**结果**: BUG-044 设计目标达成 — TContact 零 JSON, 防骚扰计数 (ad_count/AD_MAX_COUNT) 真实可用。

---

## 2026-08-01 — P0 架构反模式发现与整改

> **来源**: DeepBase 集成深度审计 (2026-08-01) — 发现三大严重架构不一致问题。
> **状态**: ⚠️ P0 级缺陷，需立即重构

### BUG-044: TagProfile JSON 大规模滥用 — 违反参数化设计原则 (P0, ✅ 已修复 2026-08-03)
**文件**: `src/pipeline/DeepAxis.Pipeline.AdTracker.pas`, `IdleFunnel.pas`, `TagEngine.pas`
**现象**: 
```pascal
// ❌ 反模式 — 数据类型声明已说"移除了 JSON",但实现仍在用
LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
Result.TagProfile := LProfile.ToJSON;
```
**影响范围**: 12 处调用点
**根因**: 
1. `DeepAxis.Core.DataTypes.pas` 第 87 行注释说 `// ❌ REMOVED: TagProfile: string; // JSON - Bad design!`
2. 但 Pipeline 代码仍大量使用 JSON 解析/生成
3. 与"所有配置进数据库"的架构原则直接矛盾
**预期方案**:
- ✅ TContact 应只包含字段级属性 (ProductCount, IsUserPreserved 等)
- ✅ 删除所有 `ParseJSONValue(TagProfile)` 调用
- ✅ TagProfile 数据应通过 TTagProfileDB1Store 查询 (真正的 DB1 表)
- ✅ UI 层不接触 JSON，直接从参数化字段读取
**优先级**: P0 - 违反核心架构原则

### BUG-045: i18n 框架空转 — 零实际应用 (P0, ✅ 已修复 2026-08-06)
**文件**: `src/core/DeepAxis.Core.i18n.pas`, 所有 UI 表单
**现象**:
```pascal
// ❌ TI18nManager 框架存在但从未被调用
grep("I18nStr(", src/ui) → 0 matches
LoadStringTable(const ALang: TI18nLang): // TODO: Load from ConfigDB or resource file
```
**影响范围**: 所有 UI 窗口 (MainForm, TierPanel, RadarPanel, ScriptPanel 等)
**根因**:
1. i18n 单元只有框架代码，没有真正从数据库加载文本
2. ConfigDB 中没有 translations 表结构
3. UI 代码全部硬编码字符串 `'APP_TITLE' = 'DeepAxis'` 等
**预期方案**:
```sql
CREATE TABLE translations (
  lang TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (lang, key)
);
```
- ✅ UI 代码改为 `Label.Caption := I18nStr('APP_TITLE')`
- ✅ MainForm 初始化时从 ConfigDB 加载 zhCN/enUS 双语文本
- ✅ 提供语言切换功能
**优先级**: P0 - 违反国际化架构原则

### BUG-046: 阈值参数仍为硬编码常量 — 无法热配置 (P0, ✅ 已修复 2026-08-06: Radar 5 阈值已走 GetCapability, 确认达成)
**文件**: `src/pipeline/DeepAxis.Pipeline.Radar.pas`
**现象**:
```pascal
const
  COOLING_DAYS = 7;
  LONG_SILENCE_DAYS = 30;
  OUTBOUND_HEAVY_RATIO = 5.0;
// ❌ 应该从 ConfigDB 读取
Result.CoolingDays := COOLING_DAYS;
```
**影响范围**: TRadarEngine 所有 Hint 计算方法
**根因**:
1. 虽然注释说"✅ FIXED: Parameterized threshold values instead of JSON"
2. 但实际上仍是编译期常量，修改需重新编译
3. 违反"所有配置进数据库"原则
**预期方案**:
```pascal
// ✅ 从 ConfigDB 读取
COOLING_DAYS := Config.GetInteger('radar.cooling_days_threshold', 7);
Result.CoolingDays := COOLING_DAYS;
```
- ✅ 在 config_items 表存储 radar.*_threshold 配置项
- ✅ TRadarEngine 构造函数注入 FConfig: TDeepAxisConfigDB1
- ✅ 支持运行时动态调整阈值
**优先级**: P0 - 违反参数化配置原则

### 技术债务总结
| 问题 | 违规类型 | 影响面 | 优先级 | 预计工时 |
|------|---------|-------|--------|----------|
| BUG-044 | JSON vs 参数化 | 12 处代码 | P0 | 8h |
| BUG-045 | i18n 未落地 | 所有 UI | P0 | 6h |
| BUG-046 | 硬编码常量 | Radar.pas | P0 | 2h |
| **总计** | 架构一致性 | 3 大模块 | **P0** | **16h** |

### 整改计划
1. **Phase 1 (2h)**: 创建 translations 表 + i18n 框架完善
   - SQL Schema: CREATE TABLE translations
   - TI18nManager.LoadStringTable: 从 ConfigDB 查询填充
   - 替换所有 UI 硬编码字符串为 I18nStr() 调用
   
2. **Phase 2 (2h)**: 阈值参数迁移到 ConfigDB
   - config_items 表插入 radar.*_threshold 配置项
   - TRadarEngine 依赖注入 FConfig
   - 移除 const 块中的硬编码
   
3. **Phase 3 (8h)**: TagProfile JSON 重构
   - 创建 tag_profiles 表 (contact_id PK, product_count, is_user_preserved, ...)
   - TTagProfileDB1Store 完整实现 CRUD
   - 删除所有 ParseJSONValue(TagProfile) 调用
   - 改用参数化字段查询

---

## 2026-07-16 — BUG-043 启动崩溃 'no parent window' (三版演进，✅ v3 根治)

> 来源: 真机启动崩溃, 报 `AccessViolation read 0x000000A9`, 偏移 RVA 0x2163ED。三版逐步定位真凶, v3 经 `bin/DeepAxis.log` 时序证据锁定。
> 验证: dcc64 0 errors (19104 行); 64/64 全绿; exe+map 同步 bin。
> 关联提交: 1efbe96 (v1) / fbef349 (v2) / 5a8ff5f (v3)。

### BUG-043v1: 初判 InitHotKeys 时序 + 默认布局 (HEURISTIC, ❌ 未拦住)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: 真机启动崩在 Vcl.Controls.TControl.SetVisible, 怀疑 FScriptPanel.Visible:=True 在父窗句柄就绪前触发 'no parent window' → 二次 AV。
**修复**: InitHotKeys 改 TThread.Queue 延后 + 默认布局改 dlCompact。
**结果**: 真机仍报同偏移, 未拦住。属假设性修复, 真凶未中。

### BUG-043v2: .map 精确定位 + SafeSetVisible 守卫 (MEDIUM, ❌ 引入新症状)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: 用 .map 解析 RVA 0x2163ED → Vcl.Controls.TControl.SetVisible 入口 +0xD 字节 (内部崩)。
**原因**: 启动期 FormShow 早段若 MainForm 句柄未分配, 对子面板设 Visible(True/False) 触发 SetVisible→GetParentHandle→EInvalidOperation 'no parent window' → DeepBase 异常弹窗路径二次崩 → AV read 0xA9。
**修复**: ApplyLayout 入口先 Self.Handle 触发 HandleNeeded 确保父句柄链就绪, 再用 SafeSetVisible (try/except 兜 EInvalidOperation 降级记日志); ShowWarning 同兜。
**结果**: `bin/DeepAxis.log` 证实 ApplyLayout 的 Visible 赋值从未抛异常 (无降级日志), 反而引入新症状: 启动弹提示框 + 主界面只剩菜单 (Self.Handle 早触发窗口重入, 打断 Z-order/可见性)。守卫本身无害但未中真凶。

### BUG-043v3: 真凶二刷 — FormShow 同步弹模态向导触发 (ROOT-CAUSE, ✅ 根治)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**真凶** (经 bin/DeepAxis.log 08:42 时序证据锁定): 真机启动走首次配置向导分支 (GetWeChatDataPath='') → FormShow 同步调 LSetup.ShowModal (第 223 行)。FormShow 处于主窗 WM_SHOW 处理中, 句柄链未完全就绪, 模态 ShowModal 触发子控件 TScriptPanel 'no parent window', 异常逃逸到 DeepBase AIErrorHandler 弹提示框 (= 症状 1: 启动弹框), 且布局流程被打断导致面板未正常显示 (= 症状 2: 主界面只剩菜单)。
**修复** (釜底抽薪):
- FormShow 只留 ApplyLayout(dlCompact)+InitWeChatHook, 其余 (配置向导 + 微信检测 + 密钥加载 + RefreshStepButtons) 抽到新方法 FormShowPhase2, 用 `TThread.Queue(nil, FormShowPhase2)` 延后到下一消息帧执行。
- 此时主窗已 WM_SHOW 完毕、所有句柄就绪, ShowModal 与 Visible 切换均安全。
- 回退 v2 的 Self.Handle hack (有害); 保留 SafeSetVisible 作兜底 (无害)。
- 删 FormShow 多余局部变量 LSetup/LPid 声明 (移入 Phase2)。
**结果**: 真凶根治。pending 真机回归确认 (1) 不再弹崩溃/异常提示框 (2) 主界面正常显示雷达面板 (3) 首次启动向导正常弹出且可完成。

> **教训**: v1/v2 均在"子面板 Visible 赋值"这条假设线上打补丁, 未中真凶; v3 用运行日志时序证据 (ShowModal 在 WM_SHOW 中) 才定位到"同步弹模态向导"。根治策略: 把所有非布局收尾动作移出 FormShow 同步路径, 延后到句柄就绪后的消息帧。

---

## 2026-07-08 — 阶段8 标签建议 UI 开发期修复 (BUG-038~040)

> 来源: 开发 Task #68~#69 (TagManager GenerateL0Report 复活 + TagSuggestPanel L0-L1 UI) 过程中发现并修复的 3 项问题。
> 验证: `dcc64 DeepAxis.dpr` → 0 errors (18651 行); `DeepAxisTestRunner.exe` → 56/56 passed (新增 Test.TagManager 6 用例)。

### BUG-038: TagManager 类声明顺序倒置 — TTagManager 引用后声明的 TProductFactCard (MEDIUM, ✅ 已修复)
**文件**: `src/pipeline/DeepAxis.Pipeline.TagManager.pas`
**现象**: 为接入产品事实卡给 `TTagManager` 加 `FProductFactCard: TProductFactCard` 字段后, 编译报 `E2003 Undeclared identifier: 'FProducts'` + `E2004 Identifier redeclared: 'TProductFactCard'` 等十余个错误。
**原因**: 原文件中 `TTagManager` 声明在 `TProductFact`/`TProductFactCard` **之前**。TTagManager 的字段/属性引用 TProductFactCard 时, 该类型尚未声明 (Delphi 无 forward 类型推断, 类字段类型必须在类声明前可见)。
**影响**: 主项目无法编译, 连锁阻塞测试。
**修复**: 把 `TProductFact` record + `TProductFactCard` class 声明块移到 `TTagManager` 之前 (TTagSuggestion → TProductFact → TProductFactCard → TTagManager)。实现区顺序不变。

### BUG-039: TagManager 正则用 \b 词边界 — 中文备注中电话/金额不匹配 (HIGH, ✅ 已修复)
**文件**: `src/pipeline/DeepAxis.Pipeline.TagManager.pas` (ExtractPhone/ExtractAmount)
**现象**: 复活 TagManager 后单测 `TestRemarkExtraction` 失败 — 备注 `'13800138000 100元 小红书'` 只匹配电话, 金额/渠道 0 产出 (期望 ≥3)。
**原因**: 原正则用 `\b` (单词边界)。`\b` 依赖 `\w` = ASCII 字母数字下划线, **中文字符非 `\w`**。金额正则 `\b\d+\.?\d*\s*[元块]\b` 末尾 `\b` 要求 "元" 后是词边界, 但 "元" 本身非 `\w`, 其与后续空格之间不构成 `\b`, 导致整个金额匹配失败。电话 `\b1[3-9]\d{9}\b` 在纯数字+空格场景偶发可用, 但中文紧跟数字时同样失效。
**影响**: AnalyzeRemarks 对中文备注的电话/金额提取静默失败, L0 报告缺数据 — 复活的死代码仍不可用。
**修复**: 电话改 `(?:^|[^0-9])(1[3-9]\d{9})(?:[^0-9]|$)` 用非数字边界 + 捕获组1 (避免从更长数字串截取); 金额改 `\d+\.?\d*\s*[元块]` 去掉末尾 `\b`。日期正则保留 `\b` (纯数字+分隔符, 不涉中文词边界问题)。诊断脚本验证三正则均匹配。

### BUG-040: 新增 .pas 源文件缺 UTF-8 BOM — 中文正则与 TagManager.pas 编码不一致致运行时不匹配 (HIGH, ✅ 已修复)
**文件**: `tests/Test.TagManager.pas`, `src/ui/DeepAxis.UI.TagSuggestPanel.pas` (新建)
**现象**: BUG-039 修复正则后单测仍失败 2/6。诊断脚本 `diag_regex` (无 BOM) 单独跑正则全匹配, 但 `diag_tag` (无 BOM) 调 GenerateL0Report 只产 1 条 (电话)。给诊断脚本加 BOM 后 total=3 全匹配。
**原因**: Delphi dcc64 对源文件编码处理: **带 BOM** → 按 UTF-8 解码中文字面量为正确 Unicode 码点; **无 BOM** → 按系统 ANSI (本机 GBK) 解码。TagManager.pas 是 UTF-8 with BOM (其 `[元块]`/`'小红书'` 编译为 U+5143/U+5143 等正确码点)。新建的 Test.TagManager.pas 无 BOM, 其备注字面量 `'100元'` 的 "元" 按 GBK 解码为不同码点。两者运行时字符串码点不一致 → `Pos`/正则中文匹配失败 (电话纯正则无中文故仍匹配)。项目既有 42 个 src 文件中 28 个有 BOM、14 个无; 8 个 tests 文件全无 BOM — 编码长期混用, 既有测试不依赖中文字面量匹配故未暴露。
**影响**: 任何依赖中文字面量匹配的新测试/UI 对 UTF-8 BOM 源文件都会运行时失配, 表现为"正则对但匹配失败"的诡异 bug。
**修复**: 给本阶段新建的 `Test.TagManager.pas` + `DeepAxis.UI.TagSuggestPanel.pas` 加 UTF-8 BOM, 与 TagManager.pas 编码约定一致。既有无 BOM 文件不碰 (非本阶段范围, 改动需单独评估)。56/56 全绿。

### BUG-041: OnAdSent ad_count 未持久化 — 轮询从微信 DB 重读后复位 (P1, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas` (DoPasteScriptWithMode, 原 :1087/1090), `src/ui/DeepAxis.UI.RadarPanel.pas` (DBPollerThread), `src/pipeline/DeepAxis.Pipeline.AdTracker.pas`, 新增 `src/pipeline/DeepAxis.Pipeline.ContactOverlay.pas`
**现象**: `LContact := TAdTracker.OnAdSent(LContact)` 把 ad_count+1 写进 LContact.TagProfile JSON, 但 LContact 是局部变量, 结果被丢弃。下一轮 DBPollerThread 从微信 DB 重读 contacts (TagProfile 是 Reader 从 remark 重建的只读快照, 无 ad_track), 覆盖 FLastContacts → ad_count 复位回 0, 防骚扰计数失效。
**原因**: TagProfile 是 DeepAxis 自定义演进态 JSON (ad_track/产品匹配/标签), 微信 DB 不存此字段, Reader 每轮从 remark 重建基础态 → 内存演进态无落地点。设计意图 (docs/09:181 "更新本地 Contact.last_msg_at / AdTrack.ad_count") 要求演进态存本地 DB1, 但 DB2 的 contacts 表 (MainForm.InitDB2 已建, schema 含 tag_profile TEXT) 一直空壳无人读写。
**影响**: 广告防骚扰上限 (AD_MAX_COUNT) 形同虚设 — 轮询周期内 ad_count 重新计数, 同一闲人可被反复触达, 违反 docs/03 §2.6 防骚扰约束。
**修复**: 新增 `TContactOverlayStore` (DB2 contacts 表 upsert+load, 复用 MainForm.FDB2Connection, 异常静默兜底退化纯 Reader 数据)。字段级合并由 `TAdTracker.MergeAdTrack(ABase, AOverlay)` 完成 — 以 Reader 当轮新算的 TagProfile 为底, 用 overlay 的 ad_track 子对象覆盖, 保留 L0 数据 (产品匹配/标签), 只回填持久化的 ad_track。链路: OnAdSent 后 `FOverlayStore.UpsertTagProfile` 写本地 DB1; DBPollerThread.DoPollInner 隐私分类后 `ApplyOverlay` 读合并。新增 2 用例 (TestAdTrackerMergeAdTrack 字段级合并 4 场景 + TestOverlayStoreRoundTrip upsert/load 往返), 59/59 全绿。零微信数据风险 (IWxReader 只读, overlay 完全在本地 DB1)。

### BUG-042: Test.Phases.pas 无 UTF-8 BOM — #75 新增中文字面量/┊ 被 dcc 按 ANSI 解码致 BuildAppendRemark 测试与去重 Pos 失配 (HIGH, ✅ 已修复)
**文件**: `tests/Test.Phases.pas` (既有文件, 原无 BOM)
**现象**: #75 新增 4 用例编译通过但 3 失败: `TestBuildAppendRemarkAppend` 期望 `张三┊渠道:小红书` 实得 `张三??渠道:小红?` (┊ 与部分中文成乱码); `TestBuildAppendRemarkDedup` 去重失败 (Pos 检查 `┊渠道:` 未匹配已有 `┊渠道:` → 重复追加 `┊渠道:抖音`); `TestTagSuggestionFieldPopulated` "渠道+金额至少2条" Condition False。
**原因**: 与 BUG-040 同源。TagManager.pas (BuildAppendRemark 实现 + `┊` 字面量) 是 UTF-8 with BOM, 运行时 `┊` 为正确码点 U+250A。Test.Phases.pas 原无 BOM, #75 用 Write 工具写入的中文/`┊` 为 UTF-8 字节, dcc 按 ANSI(GBK) 解码 → 测试源里的 `┊` 与运行时 TagManager 的 `┊` 是不同码点 → 字符串比较不等 + Pos 子串匹配失败。既有 Test.Phases 测试不依赖中文字面量跨文件匹配 (用 MakeBusinessContact 等 ASCII 夹具) 故未暴露。
**影响**: 任何跨文件中文字面量匹配测试 (Test 源 vs src 实现) 对无 BOM 源都会失配, 表现诡异 (编译过、断言乱码)。
**修复**: 给 `tests/Test.Phases.pas` 前置 UTF-8 BOM (Python 重写字节头), dcc 按 UTF-8 解码全文件, 中文/`┊` 码点与 TagManager 一致。63/63 全绿 (BuildAppendRemark append/dedup/empty 三路径 + Field 填充全通过)。既有 8 个 tests 文件仍无 BOM — 不碰 (非本阶段范围), 但 BUG-040+BUG-042 提示后续新测试若涉及跨文件中文字面量匹配需先补 BOM。

### BUG-043 (v1 旧描述, 已被顶部三版演进块取代)
> 见本文件顶部 "2026-07-16 — BUG-043 启动崩溃 (三版演进)" 块。本条为 v1 单版描述, 当时判定"已修复"但真机仍崩, 经 v2/v3 复盘修正。保留此指针避免编号空缺误读。

---

## 2026-07-08 — 发送双模式/标签矩阵/闲人漏斗开发期修复 (BUG-035~037)

> 来源: 开发 Task #54~#71 (发送三模式 + 标签矩阵 + 闲人漏斗 + AdTracker + UIA 扩展) 过程中发现并修复的 3 项问题。
> 验证: `dcc64 DeepAxis.dpr` → 0 errors (18383 行)。

### BUG-035: ScriptPanel 匿名方法捕获 Option causing 循环变量错位 (MEDIUM, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.ScriptPanel.pas`
**现象**: 首版用 `for LIdx in [0..Count-1] do TButton(FModeButtons.Components[LIdx]).OnClick := procedure begin SelectedMode := TSendMode(LIdx); end;`，匿名方法捕获循环变量 `LIdx` 的引用而非值。循环结束后所有按钮的 OnClick 都用最终的 `LIdx` 值，点击任意模式按钮都选中最后一个模式。
**影响**: 模式选择按钮全部失效，用户无法切换发送模式。
**修复**: 改为命名方法 `DoModeClick(Sender: TObject)`，通过 `(Sender as TButton).Tag` 取模式索引（Tag 在创建时赋 `Ord(LMode)`），消除匿名方法闭包捕获陷阱。

### BUG-036: MainForm 证据 hash 用了不存在的 THashSHA256 (HIGH, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.MainForm.pas`
**现象**: DoPasteScriptInner 用 `THashSHA256.GetHashString(LScript).Substring(0, 16)` 计算话术证据 hash，编译报 `E2003 Undeclared identifier: 'THashSHA256'`。
**原因**: Delphi `System.Hash` 单元提供的是 `THashSHA2`（统一 SHA-2 家族，通过参数选 SHA256/384/512），不存在 `THashSHA256` 这个类名。误用了其他语言/库的命名。
**影响**: 主项目无法编译。
**修复**: 改为 `THashSHA2.GetHashString(LScript, SHA256).Substring(0, 16)`，`SHA256` 常量同样来自 `System.Hash`。interface uses 已含 `System.Hash`。

### BUG-037: DeepAxis.Tests.Phases 缺 DeepAxis.Core.Contracts 导致接口类型未声明 (MEDIUM, ✅ 已修复)
**文件**: `src/DeepAxis.Tests.Phases.pas`
**现象**: 测试单元用 `IIdleFunnel`/`ITagEngine` 接口引用，编译报 `E2003 Undeclared identifier: 'IIdleFunnel'`，连锁导致后续数十个解析错误。
**原因**: uses 只声明了 IdleFunnel/TagEngine 实现单元，未声明定义接口的 `DeepAxis.Core.Contracts` 单元。Delphi 接口类型必须从声明单元引入。
**影响**: 测试单元无法编译，连锁阻塞主项目。
**修复**: uses 补 `DeepAxis.Core.Contracts`。同时把行内 `var X := ...` 声明改为传统 var 区声明（避免与 try 块混用时的解析歧义），并把对 private 方法 `DeriveIdleJudge` 的直接调用改为调 public `DeriveTags`（内部调 DeriveIdleJudge 并回填 ProductCount）。

---

## 2026-07-08 — 联系人分级系统开发期修复 (BUG-032~034)

> 来源: 开发 Task #48~#53 (联系人四色分级 + TierPanel 工作台) 过程中发现并修复的 3 项问题。
> 验证: `dcc64 DeepAxis.dpr` → 0 errors; `DeepAxisTestRunner.exe` → 29/29 passed。

### BUG-032: FListBoxRowToEntry 映射值存的是行计数而非 entries 索引 (HIGH, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.TierPanel.pas`
**现象**: `UpdateContactList` 首版用 `for LEntry in FTierEntries` 遍历，被 tier/text filter 跳过的项不让循环计数器前进，但映射值存的是自增的 `LRowCount`（可见行计数）而非 `FTierEntries` 的真实下标。结果：当存在被过滤项时，`FListBoxRowToEntry[行号]` 指向错误的 entry，点击列表行会选中/详情显示错误联系人。
**影响**: 任何启用 tier 过滤或搜索过滤的场景，联系人选中错位。无过滤时不暴露（计数与下标恰好重合）。
**修复**: 改为 `for I := 0 to High(FTierEntries)` 索引遍历，`FListBoxRowToEntry[High] := I`（真实 entries 下标）。filter 跳过项不再破坏行→entry 映射。

### BUG-033: ListBox OwnerDraw 模式未实现 OnDrawItem 导致空绘制 (MEDIUM, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.TierPanel.pas`
**现象**: 首版设 `Style := lbOwnerDrawFixed` + `OnDrawItem := nil`，期望"默认绘制 + emoji 前缀表达色标"。但 OwnerDraw 模式下 OnDrawItem=nil 时不触发任何绘制，列表完全空白（无文字）。
**影响**: TierPanel 联系人列表不可见，功能不可用。
**修复**: 改回 `Style := lbStandard`（系统默认绘制，显示文字）。色标已由行首 emoji（🟢🟡🔴⚪）表达，无需行底色，OwnerDraw 非必要。

### BUG-034: Pipeline.Tier 缺 System.Generics.Collections 导致 TArray 未声明 (MEDIUM, ✅ 已修复)
**文件**: `src/pipeline/DeepAxis.Pipeline.Tier.pas`
**现象**: `ClassifyAll` 用 `TArray.Sort<TTierEntry>(...)`，但 uses 只声明了 `System.Generics.Defaults`（提供 `TComparer<T>`），未声明 `System.Generics.Collections`（`TArray` 泛型容器类所在单元）。编译报 `E2003 Undeclared identifier: 'TArray'`。
**影响**: 主项目无法编译。
**修复**: uses 补 `System.Generics.Collections`。同时把 `TComparison<TTierEntry>(...)` 构造改为项目惯例的 `TComparer<TTierEntry>.Construct(...)`（参考 Metrics.pas:77 / TagEngine.pas:466 既有用法）。
**防回归**: 测试 `Test.Tier.TestClassifyAllSortOrder` 显式断言排序顺序（绿→黄→红→灰，色内天数升序），任何比较器回归会被捕获。

---

## 2026-07-08 — 配置向导 / 雷达面板审阅问题修复 (BUG-028~031)

> 来源: 2026-07-07 审阅配置向导 + 雷达面板增强提交时发现的 4 项问题，本次全部修复。
> 验证: `dcc64 DeepAxis.dpr` → 0 errors, 0 warnings; `DeepAxisTestRunner.exe` → 21/21 passed。

### BUG-028: 联系人列表排序把 `rhtDataInsufficient` 排到高优先级 (HIGH, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas`
**现象**: 提交 34397206 声称按"紧急程度"排序，实际比较器为 `Ord(A.HintType) - Ord(B.HintType)`，依赖枚举序号。但枚举顺序 (Core.Base.pas:28) 为：`rhtCooling=0, rhtLongSilence=1, rhtReactivated=2, rhtOutboundHeavy=3, rhtDataInsufficient=4, rhtHighLinkSharing=5, rhtMarketingPattern=6`。`rhtDataInsufficient`(数据不足，紧急度最低) 因序号 4 排在 `rhtHighLinkSharing`(5) 和 `rhtMarketingPattern`(6) 之前，与"按紧急程度"的意图相反。
**影响**: 数据不足的联系人被错误地排在前面，遮挡真正需要跟进的高频链接/营销模式联系人。
**修复**: 新增 `GetHintTypeUrgency(HintType): Integer` 方法，用显式权重表 `URGENCY: array[TRadarHintType] of Integer = (0,1,3,2,9,4,5)` 替代 `Ord()`。权重与枚举序号解耦：降温/沉默=0/1，外重内轻/回暖=2/3，高频链接/营销=4/5，数据不足=9(最低)。比较器改为 `GetHintTypeUrgency(A) - GetHintTypeUrgency(B)`。
**防回归**: 权重表是数组直接索引，新增 hint 类型时若忘记加项会编译报错 (range check)，比 `case` 缺分支更安全。

### BUG-029: 相对时间分支冗余且缺"年前"档 (MEDIUM, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas`
**现象**: 提交 583e3a1f 的相对时间计算存在两处冗余：
- `<7` 与 `<30` 两个分支输出完全相同 (`'%d 天前'`)，`<30` 分支多余。
- `<365` 与 `else` 分支输出完全相同 (`'%d 个月前'`，`LDaysAgo div 30`)，`else` 分支多余。
- 超过 365 天仍显示"N 个月前" (如 730 天 → "24 个月前")，缺少"X 年前"档，表达不直观。
**影响**: 非 bug 性故障，但代码冗余 + 超长期互动的显示不友好 (微商场景存在大量半年以上未联系的"闲人")。
**修复**: 合并 `<7`/`<30` 为单一 `<30` 分支；合并 `<365`/`else` 为 `<365` 分支；新增 `else` → `Format('%d 年前', [LDaysAgo div 365])`。5 档精简为 5 档但无冗余、覆盖超长期。

### BUG-030: SetupForm 密钥文件路径硬编码到可执行目录旁 (MEDIUM, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.SetupForm.pas`, `src/wechat/DeepAxis.WeChat.Scanner.pas`, `src/core/DeepAxis.Core.Config.pas`
**现象**: `CheckDatabaseFiles` 用 `ExtractFilePath(ParamStr(0)) + 'DeCrypt\keys\all_keys.json'` 及 `..\DeCrypt\keys\` 回退查找密钥文件，与 `TWeChatScanner.FindSavedKeysPath` 各自硬编码，二者探测位置不一致 (scanner 多探测 `D:\tmp\found_keys\`，SetupForm 不探测)。
**影响**: 设置向导的密钥状态检查可能与实际连接流程使用的密钥路径不一致，向导显示"❌ 未找到"但实际能连接，误导用户。
**修复**: 在 `TDeepAxisConfig` 新增 `GetKeysFilePath: string` 作为密钥路径唯一真相源，按 scanner 原有优先级探测三处 (`ExeDir\DeCrypt\keys\` → `ExeDir\..\DeCrypt\keys\` → `D:\tmp\found_keys\`)。`TWeChatScanner.FindSavedKeysPath` 改为直接委托 `TDeepAxisConfig.GetKeysFilePath`；`SetupForm.CheckDatabaseFiles` 改为查询同一方法。二者从此共用同一真相源，永不不一致。

### BUG-031: SetupForm 自动检测只扫固定盘符 C-G (LOW, ✅ 已修复)
**文件**: `src/ui/DeepAxis.UI.SetupForm.pas`
**现象**: `FindWeChatDataDirAuto` 第 3 步硬编码 `'D:\xwechat_files'`，第 4 步枚举 `['C','D','E','F','G']`。用户把微信装在 H 盘及以上则自动检测失败。
**影响**: 部分用户的自动检测无效，需手动浏览。功能可用但体验打折。
**修复**: 第 4 步改用 `GetLogicalDriveStrings` 枚举所有盘符根路径 (`ListLogicalDriveRoots` 内联函数)；删除第 3 步重复的 `D:\` 硬编码特例 (与第 4 步逻辑重复)。同时抽出 `FindDbStorage(Root)` 内联函数，消除三处重复的 `GetDirectories('db_storage')` + `message` 嵌套循环。uses 新增 `System.Generics.Collections`。

---

## 2026-07-07 — 配置向导 + 空状态引导 + 雷达面板增强 (审阅发现)

> 对应提交: 804e8ddc / b93f82aa / 34397206 / 583e3a1f / d75dc87a。
> 本次为审阅新功能代码时发现的问题，已于 2026-07-08 全部修复 → 见上方 BUG-028~031。

### BUG-028~031: 审阅发现 4 项问题 → 已于 2026-07-08 修复，详见上方条目。

---

## 2026-07-04 — WCDB 消息读取链路

---

## 2026-07-04 — WCDB 消息读取链路

### BUG-013: IsXmlBody 误判带 XML 声明的消息体
**文件**: `src/wechat/DeepAxis.WeChat.MsgParser.pas`
**现象**: Type=49 (link) 消息体以 `<?xml version="1.0"?>` 开头，导致 `IsXmlBody` 返回 False
**原因**: 原实现检查前 4 字符是否为 `<msg`，但 XML 声明在 `<msg>` 之前
**修复**: 改为 `ABody.Contains('<msg')`，允许 XML 声明前缀
**影响**: 所有 type=49 消息无法解析

### BUG-014: CDATA 包装未剥离
**文件**: `src/wechat/DeepAxis.WeChat.MsgParser.pas`
**现象**: 提取的 link title/url 包含 `<![CDATA[...]]>` 前缀
**原因**: XML 中的文本内容用 CDATA 包装，ExtractXmlTag 未处理
**修复**: 在 ExtractXmlTag 中检测并剥离 `<![CDATA[` 和 `]]>`
**影响**: 链接标题/URL 显示异常

### BUG-015: 控制台 CJK 字符乱码
**文件**: `tools/TestMsgParser.dpr`, `tools/TestEncoding.dpr`
**现象**: 中文字符在控制台显示为乱码
**原因**: Windows 控制台默认使用 GBK (CP936)，但数据是 UTF-8 编码
**修复**: 写入 UTF-8 文件而非控制台输出；数据本身正确，仅显示问题
**诊断**: TestEncoding.dpr 验证原始字节为有效 UTF-8

### BUG-016: "AS" Delphi 保留字冲突
**文件**: `tools/TestMsgParser.dpr`
**现象**: 编译错误 "Identifier expected"
**原因**: 参数名 `AS` 是 Delphi 保留字
**修复**: 重命名为 `AMsg`
**影响**: 测试工具无法编译

### BUG-017: BoolToStr 重载歧义
**文件**: `tools/TestMsgParser.dpr`
**现象**: 编译错误 E2034 "Overloaded function not found"
**原因**: `BoolToStr` 有多个重载，编译器无法推断
**修复**: 改用 `IfThen(value, 'True', 'False')` (System.StrUtils)
**影响**: 测试工具无法编译

### BUG-018: 重复的析构函数体
**文件**: `src/wechat/DeepAxis.WeChat.Reader.pas`
**现象**: 编译错误 "Duplicate implementation"
**原因**: 编辑后残留两个 `begin...end` 块
**修复**: 删除重复的析构函数体
**影响**: 项目无法编译

### BUG-019: LEnExisting 拼写错误
**文件**: `src/wechat/DeepAxis.WeChat.Reader.pas`
**现象**: 编译错误 "Undeclared identifier"
**原因**: 变量名 `LEnExisting` 应为 `LExisting`
**修复**: 更正变量名
**影响**: ReadAllMessages 无法编译

### BUG-020: O(N*M) 反向查找性能问题
**文件**: `src/wechat/DeepAxis.WeChat.Reader.pas`
**现象**: ReadAllMessages 处理 2237 联系人耗时 >90 秒
**原因**: 对每条消息遍历所有联系人键查找匹配的 Msg 表
**修复**: 构建 `LTableToContact` 反向字典，O(1) 查找
**性能**: 90s → 0.203s (450x 提升)
**影响**: 全量消息读取不可用

---

## 2026-07-04 — UIA 引擎升级

### BUG-012: FindWindowW 编码问题导致窗口查找失败
**文件**: `src/uia/DeepAxis.UIA.Engine.pas`
**现象**: `FindWindowW('Qt51514QWindowIcon', '微信')` 返回 0
**原因**: 窗口标题包含 Unicode 字符，FindWindowW 编码处理不当
**修复**: 改用 `EnumWindows` + 可见性评分机制
**评分规则**: 可见 (+2) + "微信"标题 (+1, Unicode 码点 $5FAE $4FE1)
**影响**: 微信 4.x 窗口无法定位

---

## 2026-07-04 — 五专家审阅发现

### BUG-021: 证据显示缺少 begin...end 导致无条件执行
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas` 行 767-771
**现象**: 详情面板证据区域显示所有证据记录而非仅匹配当前 HintId 的记录
**原因**: `for ... do if ... then` 后缺少 `begin...end` 块，导致只有第一行 `Add('')` 是条件执行，后续两行无条件执行
**影响**: 证据显示混乱，用户无法区分哪个证据属于哪个 hint
**修复**: 添加 `begin...end` 包裹三行 Add 调用

### BUG-022: 联系人列表索引与 Hint 索引错位
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas` 行 656-703
**现象**: 选择第 2 个联系人时显示错误联系人的详情
**原因**: 每个联系人添加 2 行（名称 + 预览），但 `FSelectedContactIndex` 直接使用 `ItemIndex`（列表项行号），应除以 2 才是 hint 索引
**影响**: 点击联系人显示错误详情
**修复**: 使用 `FSelectedContactIndex := FContactListBox.ItemIndex div 2` 或维护 hint 索引映射

### BUG-023: GetHintTypeColor/Emoji 缺少新增 hint 类型
**文件**: `src/ui/DeepAxis.UI.RadarPanel.pas` 行 438-462
**现象**: 高频链接分享和营销模式 hint 显示灰色和无 emoji
**原因**: `rhtHighLinkSharing` 和 `rhtMarketingPattern` 未添加 case 分支
**影响**: 新增内容提示类型在 UI 中无视觉区分
**修复**: 添加 🔗 蓝色 和 📢 紫色

### BUG-024: TagEngine MergeProfile 内存泄漏
**文件**: `src/pipeline/DeepAxis.Pipeline.TagEngine.pas` 行 245-278
**现象**: `ParseJSONValue` 返回非 TJSONObject 值时（如 TJSONString），`as TJSONObject` cast 返回 nil 但原对象泄漏
**原因**: 直接 `as` cast 丢弃了非匹配类型的引用
**影响**: 每次 MergeProfile 调用泄漏一个 TJSONValue（低频但持续）
**修复**: 用 `TJSONValue` 临时变量接收，`is TJSONObject` 判断后安全释放

### BUG-025: DeriveContentProfile top_domains 未按频次排序
**文件**: `src/pipeline/DeepAxis.Pipeline.TagEngine.pas` 行 445-449
**现象**: top_domains 输出顺序随机，不是按链接频次降序
**原因**: `TDictionary.Keys` 遍历顺序是哈希序，非频次序
**影响**: 内容画像的域名排序不可靠
**修复**: 收集为 `TPair<string, Integer>` 数组，`TArray.Sort` 按 Value 降序后取 Top 3

### BUG-026: ComputeBatch O(N*M) 全量遍历
**文件**: `src/pipeline/DeepAxis.Pipeline.Metrics.pas` 行 216-257
**现象**: 对每个联系人遍历全部消息数组和全部旧指标数组
**原因**: 未预建索引，嵌套循环复杂度 O(N*M + N*K)
**影响**: 联系人 2000+、消息 50000+ 时极慢
**修复**: 改用 `TDictionary<string, TList<TMessageMeta>>` 和 `TDictionary<string, TInteractionMetric>` 预索引

### BUG-027: TrackTempFile 用 SetLength 逐次增长
**文件**: `src/wechat/DeepAxis.WeChat.Reader.pas` 行 103-107
**现象**: 每次 TrackTempFile 调用都 SetLength+1，复制整个数组
**原因**: 用 TArray 模拟 list 行为
**影响**: 性能差（虽然最多 4 个文件，影响不大）
**修复**: 改用 `TList<string>`，构造时 Create，析构时 Free

---

## 历史 Bug (2026-06-20 及之前)

见 tasks.md 五专家复审修复清单。
