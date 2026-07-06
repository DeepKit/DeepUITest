# DeepAxis 开发任务
> **创建**: 2026-06-14
> **更新**: 2026-07-04 — 审阅发现 14 项：已修复 13 项，剩余 1 项 (MEDIUM, 跳过)
> **编译器**: Delphi 13.1 (Embarcadero Studio 37.0)
> **状态**: ✅ 编译通过 (0 errors, 21/21 tests passed) + 📋 1 项跳过 (标准命名惯例)
> **维护规则**: `tasks.md` 只保留当前待办和下一步任务；已完成任务归档到 `history.md`；Bug 修复记录写入 `bugfix.md`。

---

## 编译与测试

| 目标 | 命令 | 结果 |
|------|------|------|
| DeepAxis.exe | `dcc64 DeepAxis.dpr -B -Ebin -Ndcu` | ✅ 0 errors, 0 warnings |
| DeepAxisTestRunner.exe | `dcc64 DeepAxisTestRunner.dpr -B -E../bin -N../dcu` | ✅ 0 errors, 0 warnings |
| 单元测试 | `DeepAxisTestRunner.exe` | ✅ 21/21 passed |
| TestMsgParser.exe | `dcc64 TestMsgParser.dpr -B -E../bin -N../dcu` | ✅ 10/10 messages parsed |

---

## 文档导航

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 项目说明 |
| [docs/07.开发层-P0技术验证规格.md](docs/07.开发层-P0技术验证规格.md) | P0 开发唯一入口 |
| [docs/09.开发层-技术架构规格.md](docs/09.开发层-技术架构规格.md) | 技术架构 |
| [docs/10.开发层-UI设计规格.md](docs/10.开发层-UI设计规格.md) | UI 设计 |
| [bugfix.md](bugfix.md) | Bug 修复记录 |
| [history.md](history.md) | 已完成任务归档 |

## 架构口径

- [x] DeepAxis 没有 MVP 发布口径；用户使用完整成型产品。
- [x] 先开发作者个人使用的 `personal_full` 全功能版。
- [x] DeepAxis 尽量集成 DeepBase 框架，不刻意保持独立。
- [x] 外部发布前通过 Profile、参数收紧能力，不通过删除代码裁剪功能。

---

## 当前待办 — 五专家审阅发现

### 🔴 HIGH — 必须修复 (已全部修复 ✅)

#### Task #25: 修复 RadarPanel.pas 证据显示缺失 begin...end ✅
#### Task #26: 修复 RadarPanel.pas 联系人列表索引错位 ✅
#### Task #27: RadarHintTypeToStr 缺少新增 hint 类型 ✅
#### Task #28: GetHintTypeColor/GetHintTypeEmoji 缺少新增 hint 类型 ✅
#### Task #29: Metrics.pas 冒泡排序改为 TArray.Sort ✅
#### Task #30: ComputeBatch O(N*M) 全量遍历 → 字典索引 ✅
#### Task #32: UpdateStats 未统计新增内容提示类型 ✅
#### Task #33: GenerateMessagePreview 未处理 Location/ContactCard/Recall ✅
#### Task #34: TagEngine LOldProfile 内存泄漏 → 安全释放 ✅
#### Task #35: DeriveContentProfile top_domains 按频次排序 ✅
#### Task #36: TrackTempFile SetLength → TList<string> ✅
#### Task #37: ReadAllMessages 返回值所有权文档化 ✅
#### Task #38: docs/07 P0 验证门禁更新 (M0+M1) ✅

### 🟡 MEDIUM — 应当优化

#### Task #31: Reader.pas IsOpen 方法与字段同名
- **文件**: `src/wechat/DeepAxis.WeChat.Reader.pas` 行 559-562
- **问题**: `function IsOpen: Boolean` 与私有字段 `FIsOpen` 通过 property 暴露同名方法。Delphi 允许但容易混淆
- **修复**: 将方法改为 `GetIsOpen` 或将接口方法映射明确化
- **状态**: ⏭️ 跳过 — 标准 Delphi F-前缀命名惯例，改名会破坏接口契约

### 🟢 LOW — 可以改进 (已全部修复 ✅)

- Task #36: TrackTempFile → 改用 TList<string> ✅
- Task #37: ReadAllMessages → 添加所有权注释 ✅
- Task #38: docs/07 → 更新 M0+M1 状态 ✅

---

## 已完成

### Task #24: 补充消息类型解析 ✅ (2026-07-04)
- [x] 新增 `nmtLocation` (Type=48) — 位置消息解析
- [x] 新增 `nmtContactCard` (Type=40) — 好友推荐/名片解析
- [x] 新增 `nmtRecall` (Type=10002) — 撤回消息处理
- [x] `TLocationContent` 记录 (X/Y坐标, Scale, LocationLabel)
- [x] `TContactCardContent` 记录 (Username, Nickname, FullPy等)
- [x] `TRecallContent` 记录 (RecallText)
- [x] `TMessageParser` 新增 ParseLocationXml/ParseContactCardXml
- [x] `TWeChat411053Adapter.MapType` 更新映射
- [x] 编译通过，21/21 测试通过

### Task #23: UI 展示消息摘要 ✅ (2026-07-04)
- [x] `TContact` 新增 `MessagePreview` 字段
- [x] `TDBPollerThread.GenerateMessagePreview` 生成消息预览
- [x] `UpdateContactList` 显示消息预览 (最近3条, 带方向指示)
- [x] `UpdateDetail` 显示内容统计 (链接数/媒体数/平均字数/营销关键词)
- [x] 编译通过，21/21 测试通过

### Task #22: 消息内容用于 Metrics 计算 ✅ (2026-07-04)
- [x] `TInteractionMetric` 新增内容字段 (LinkCount/MediaCount/AvgTextLength/HasMarketingKeywords)
- [x] `TRadarHintType` 新增 rhtHighLinkSharing 和 rhtMarketingPattern
- [x] `Metrics.Compute` 使用 `TMessageParser` 解析消息内容
- [x] 统计链接数、媒体数、平均字数、营销关键词
- [x] `RadarEngine` 生成内容相关提示 (高频链接分享/营销模式)
- [x] 编译通过，21/21 测试通过

### Task #21: ReadAllMessages 接入 Pipeline ✅ (2026-07-04)
- [x] 添加 `ReadAllMessages` 到 `IWxReader` 接口
- [x] `ITagEngine.DeriveTagsBatch` 接受消息字典参数
- [x] `TagEngine` 使用 `TParsedMessage` 进行内容分析
- [x] `DeriveContentProfile` 统计消息类型/字数/链接域名/营销关键词
- [x] `RadarPanel.DoPoll` 构建消息字典并传递给 TagEngine
- [x] 移除 `BodyQueried` 断言，更新测试
- [x] 编译通过，21/21 测试通过

---

## 已完成阶段 (详见 history.md)

| 阶段 | 日期 | 说明 |
|------|------|------|
| WCDB 消息读取链路 | 2026-07-04 | zstd 解压 + MsgParser + 连接缓存 (450x) |
| UIA 引擎升级 | 2026-07-04 | 三层降级策略 + 微信 4.x 兼容 |
| 全面优化 | 2026-06-20 | Evidence hash + 测试自动化 + AutoFix |
| 五专家复审修复 | 2026-06-20 | 10 P0 bug + 4 P1 优化 |
| 产品设计 | 2026-06-14 | 文档体系 + 架构决策 |
