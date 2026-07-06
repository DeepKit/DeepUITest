# DeepAxis 已完成任务
> **说明**: 从 `tasks.md` 归档的已完成任务。

---

## 2026-07-04 — 五专家审阅修复 (Tasks #25-#38)

### Bug 修复 (HIGH)

| # | 任务 | 修复内容 |
|---|------|---------|
| 1 | #25 证据显示 begin...end | RadarPanel.pas: for-if 缺少 begin...end 导致证据无条件显示 |
| 2 | #26 联系人列表索引错位 | RadarPanel.pas: 引入 FListBoxRowToHintIndex 映射数组 |
| 3 | #27 RadarHintTypeToStr 缺失 | Core.Base.pas: 添加 rhtHighLinkSharing/rhtMarketingPattern + else 分支 |
| 4 | #28 GetHintTypeColor/Emoji | RadarPanel.pas: 🔗蓝色/$00FFD080 和 📢紫色/$00C080FF |
| 5 | #29 Metrics 冒泡排序 | Metrics.pas: O(N²) → TArray.Sort<TMessageMeta> + TComparer |
| 6 | #32 UpdateStats 未统计新类型 | RadarPanel.pas: case 添加 rhtHighLinkSharing/rhtMarketingPattern 计数 |
| 7 | #33 GenerateMessagePreview 缺失 | RadarPanel.pas: 添加 pctLocation/pctContactCard/pctRecall 预览 |

### 性能修复 (MEDIUM)

| # | 任务 | 修复内容 |
|---|------|---------|
| 8 | #30 ComputeBatch O(N*M) | Metrics.pas: 改用 TDictionary 预分组，O(M+K+N) |

### 内存修复 (LOW)

| # | 任务 | 修复内容 |
|---|------|---------|
| 9 | #34 LOldProfile 泄漏 | TagEngine.pas: ParseJSONValue 非 TJSONObject 时安全释放 |
| 10 | #35 top_domains 无序 | TagEngine.pas: 改用 TArray.Sort 按频次降序排后取 Top 3 |
| 11 | #36 TrackTempFile | Reader.pas: TArray → TList<string>，消除 SetLength 逐次增长 |

### 文档修复

| # | 任务 | 修复内容 |
|---|------|---------|
| 12 | #37 所有权文档 | Contracts.pas: ReadAllMessages 添加 ownership 注释 |
| 13 | #38 P0 门禁更新 | docs/07 v0.6: 反映 M0+M1 实现状态 |

### 编译验证
- `dcc64 DeepAxis.dpr -B -Ebin -Ndcu` → 0 errors, 0 warnings
- `DeepAxisTestRunner.exe` → 21/21 tests passed

---

## 2026-06-14 — 产品设计阶段完成

### 文档体系建立

| # | 文档 | 状态 |
|---|------|------|
| 1 | README.md | ✅ 项目入口 + 架构说明 + 文档导航 |
| 2 | docs/00.DeepAxis 序枢的由来.md | ✅ 产品由来 |
| 3 | docs/00.研究-微商从业者真实需求与DeepAxis匹配度分析.md | ✅ 用户研究 |
| 4 | docs/01.重构讨论记录-2026-06-12.md | ✅ 决策历史 |
| 5 | docs/02.框架层-DeepAxis产品框架设计.md v2.1 | ✅ 纯PC工作台 + 标签矩阵 + 闲人漏斗 |
| 6 | docs/03.场域层-CRM+销售促进系统.md v2.1 | ✅ 闲人漏斗生命周期 + 发送双模式 |
| 7 | docs/04.场景层-首次导入与初始状态建立.md | ✅ 首次体验 |
| 8 | docs/05.场景层-半自动效率工具.md v1.2 | ✅ 双模式发送 |
| 9 | docs/06.场景层-效率设计与绿黄红发送系统.md v1.1 | ✅ 绿黄红审核 |
| 10 | docs/07.开发层-P0技术验证规格.md v0.4 | ✅ P0a/P0b/P0c 门禁 |
| 11 | docs/08.开发层-标签与备注整理规格.md v0.2 | ✅ L0-L3分级 |
| 12 | docs/09.开发层-技术架构规格.md v0.2 | ✅ Delphi + DeepBase + 五层 + Skia + UI |
| 13 | docs/10.开发层-UI设计规格.md v0.1 | ✅ 竖条面板三区布局 |
| 14 | docs/99.归档/ | ✅ 旧 MVP 文档归档 |

### DeepBase 底座文档

| # | 文档 | 状态 |
|---|------|------|
| 1 | docs/32.data.SQLCipher外部数据库读取-开发规格.md | ✅ IExternalDBReader + BodyZero |
| 2 | docs/33.data.SchemaAdapter通用适配器-开发规格.md | ✅ ISchemaAdapter + Registry |
| 3 | docs/34.data.UIA自动化引擎-开发规格.md | ✅ IUIAutomationEngine + CommandQueue |
| 4 | docs/35.data.剪贴板保护与窗口监控-开发规格.md | ✅ TClipboardGuard RAII + IWindowMonitor |
| 5 | docs/36.data.VCL桌面端独有能力-开发规格.md | ✅ Skia4Delphi + 全局热键 + 窗口管理 |

### 核心架构决策

| # | 决策 | 结论 |
|---|------|------|
| 1 | 架构模式 | 纯PC工作台 (非双端) |
| 2 | 技术栈 | Delphi 13.1 + VCL + DeepBase 底座 |
| 3 | 图形引擎 | Skia4Delphi 7.1.0 (GPU加速) |
| 4 | UI框架 | 不用 DeepShell IDE 布局, 自建 TForm |
| 5 | 密钥加解密 | BCrypt (Windows 内置, 零外部依赖) |
| 6 | 发送模式 | 辅助模式 (粘贴+用户Enter) + 手动模式 |
| 7 | 标签策略 | 只读 + L0-L3 分级整理 |
| 8 | 备注策略 | 只读信息源, 废弃 ┊ 协议 |
| 9 | 闲人定义 | 关联产品数=0, 可广告, N次无回应建议删除 |
| 10 | 标签矩阵 | DeepAxis 内部体系, 非微信标签 |
| 11 | P0 验证标准 | 务实版: 1个真实数据源跑通 |
| 12 | M1 数据清理 | 用户显式清理 |
| 13 | P1 优先级 | 客户雷达面板先于产品事实卡 |

### 四专家审查 — 10个Bug/冲突已解决

| # | 问题 | 状态 |
|---|------|------|
| 1 | M0与首屏冲突 | ✅ 已修复文档 |
| 2 | P0退出标准太弱 | ✅ 已更新为三段门禁 |
| 3 | UNKNOWN处理不够硬 | ✅ 默认拒绝策略 |
| 4 | 证据链模型不足 | ✅ 已扩展字段 |
| 5 | 状态自动推进冲突 | ✅ 冷启动只生成候选提示 |
| 6 | "数据不离开设备"表述不严谨 | ✅ 已改为准确表述 |
| 7 | 发送效率被高估 | ✅ 已修正为"5分钟决策与准备" |
| 8 | 绿灯规则依赖不存在的数据 | ✅ 加 P1.5 产品事实卡 |
| 9 | 备注/标签写回风险偏高 | ✅ 降级为可选, L2操作 |
| 10 | 数据保留过重 | ✅ M1 24h 快照清理 |

### WxDecryptProbe

| # | 版本 | 状态 |
|---|------|------|
| 1 | v0.1 (OpenSSL) | ✅ 设计完成 |
| 2 | v0.2 (BCrypt, 零外部依赖) | ✅ 编译通过, 微信4.x加密方案逆向进行中 |

---

## 2026-07-04 — UIA 引擎升级完成

> 微信 4.x 使用 Qt 5.15.14，UI 树完全不透明。实现三层降级策略（UIA → Win32 → 键盘模拟），支持微信 3.x/4.x 双版本。

### 完成内容

| Step | 功能 | 状态 |
|------|------|------|
| 1 | 微信版本检测 (TWeChatVersion) | ✅ |
| 2 | SendInput 替代 keybd_event | ✅ |
| 3 | IUIAutomation COM 接口 | ✅ |
| 4 | 三层降级策略 | ✅ |
| 5 | 粘贴验证循环 | ✅ |
| 6 | 文件/图片发送 | ✅ |
| 7 | 窗口状态感知 + 证据链 | ✅ |

### 微信 4.x 运行时验证

| 测试项 | 结果 | 策略 | 耗时 |
|--------|------|------|------|
| LocateWeChat | ✅ v4.1.10.53 | UIAutomation | 32ms |
| PasteScript | ✅ 成功 | UIAutomation | 406ms |
| SendFile | ✅ 成功 | KeyboardSim | 734ms |

### 关键发现

- 微信 4.x 主进程: `Weixin.exe` (非 `WeChatAppEx.exe`)
- UI 框架: Qt 5.15.14, 类名 `Qt51514QWindowIcon`
- 输入控件: `mmui::ChatInputField` (通过 UIA 可操作)
- UI 树完全不透明，但 UIA Layer 1 可用于文本粘贴

详见: `research/wechat-mcp/UIA_ENGINE_TEST_RESULTS.md`

---

## 2026-07-04 — WCDB 消息读取链路完成

> 实现从 WCDB 加密数据库读取消息正文的完整链路：zstd 解压 → UTF-8/GBK 解码 → XML 解析 → 结构化消息对象。

### Task #17: 修复 Reader 嵌套目录发现 ✅
**问题**: WCDB 使用 `contact/contact.db`, `message/message_*.db` 子目录结构，原代码只搜索顶层目录。
**修复**: `DiscoverDbFiles` 增加子目录回退搜索。

### Task #18: 创建消息类型解析器 ✅
**新建**: `src/wechat/DeepAxis.WeChat.MsgParser.pas`
**功能**: 支持 7 种消息类型 (text/image/voice/video/emoji/link/system)
**技术**: 正则表达式提取 XML 属性，CDATA 剥离，无 DOM 依赖

### Task #19: Reader 集成测试验证 ✅
**工具**: `tools/TestMsgParser.dpr`
**结果**: 10/10 消息正确解析，中文内容正确解码

### Task #20: Reader 性能优化 — 连接缓存 ✅
**问题**: 每次 ReadMessages 打开/关闭 DB 文件，2237 联系人 × 3 DB = 13,422 次连接操作
**修复**: 缓存 TFDConnection 和表映射，避免重复打开
**性能**: 90s → 0.203s (450x 提升)

### 新增文件

| 文件 | 说明 |
|------|------|
| `src/wechat/DeepAxis.WeChat.Zstd.pas` | zstd.dll 动态加载 + SmartDecode |
| `src/wechat/DeepAxis.WeChat.MsgParser.pas` | 消息类型解析器 |
| `tools/TestMsgParser.dpr` | 集成验证工具 |
| `tools/TestEncoding.dpr` | 编码诊断工具 |

### 关键技术点

- **zstd 压缩**: WCDB_CT_message_content = 4, magic `28 B5 2F FD`
- **编码检测**: IsValidUtf8 严格验证 + GBK (CP936) 回退
- **XML 解析**: `ABody.Contains('<msg')` 判断，支持 XML 声明前缀
- **CDATA 处理**: 剥离 `<![CDATA[...]]>` 包���

### 验证结果

```
Msg type=1: 亲，干饭大礼包来啦～ ✅点击蓝色链接领取外卖红包
Msg type=49: title="淘宝闪购领15-12元叠加红包" url=https://...
Msg type=10000: "尘羽"通过扫描"吃喝玩乐福利君"分享的二维码加入群聊
```

---

## 2026-07-04 — Task #24: 消息类型解析扩展完成

> 新增位置消息、好友推荐/名片、撤回消息的解析支持。

### 完成内容

1. **TNormalizedMsgType 扩展**
   - `nmtLocation` — Type=48 位置消息
   - `nmtContactCard` — Type=40 好友推荐/名片
   - `nmtRecall` — Type=10002 撤回消息

2. **内容记录定义**
   - `TLocationContent`: X/Y坐标, Scale, LocationLabel
   - `TContactCardContent`: Username, Nickname, FullPy, ShortPy, Alias
   - `TRecallContent`: RecallText, RawBody

3. **解析方法**
   - `ParseLocationXml`: 提取位置坐标和标签
   - `ParseContactCardXml`: 提取用户名和昵称
   - `ExtractDouble`: 辅助方法提取浮点数属性

4. **适配器更新**
   - `TWeChat411053Adapter.MapType` 新增 Type 40/48/10002 映射

5. **Parse 方法扩展**
   - 新增 nmtLocation/nmtContactCard/nmtRecall 分支
   - 位置/名片使用 XML 解析
   - 撤回消息使用纯文本

### 编译与测试

```
DeepAxis.exe: ✅ 0 errors, 0 warnings (14716 lines)
DeepAxisTestRunner.exe: ✅ 21/21 passed
```

### 支持的消息类型

| Type | 名称 | 解析状态 |
|------|------|----------|
| 1 | 文本 | ✅ pctText |
| 3 | 图片 | ✅ pctImage |
| 34 | 语音 | ✅ pctVoice |
| 40 | 好友推荐/名片 | ✅ pctContactCard (新增) |
| 43 | 视频 | ✅ pctVideo |
| 47 | 表情 | ✅ pctEmoji |
| 48 | 位置 | ✅ pctLocation (新增) |
| 49 | 链接 | ✅ pctLink |
| 10000 | 系统消息 | ✅ pctSystem |
| 10002 | 撤回消息 | ✅ pctRecall (新增) |

---

## 2026-07-04 — Task #23: UI 消息摘要展示完成

> 在 RadarPanel 中展示消息预览和内容统计。

### 完成内容

1. **TContact 扩展**
   - 新增 `MessagePreview: string` 字段
   - 存储最近消息的简要摘要

2. **消息预览生成**
   - `TDBPollerThread.GenerateMessagePreview` 方法
   - 提取最近 3 条消息
   - 根据消息类型生成预览:
     - 文本: 前50字符
     - 图片/视频/语音: [图片]/[视频]/[语音]
     - 链接: [链接] + 标题前30字符
     - 表情: [表情]
     - 系统: 前50字符
   - 添加方向指示: → (出) / ← (入)

3. **联系人列表更新**
   - `UpdateContactList` 显示消息预览
   - 预览截断至 60 字符
   - 缩进显示在联系人名称下方

4. **详情面板增强**
   - `UpdateDetail` 显示内容统计:
     - 链接消息数
     - 媒体消息数 (图片+视频+语音)
     - 平均文本长度
     - 营销关键词检测结果
   - 统计信息显示在证据备忘录中

### 编译与测试

```
DeepAxis.exe: ✅ 0 errors, 0 warnings (14588 lines)
DeepAxisTestRunner.exe: ✅ 21/21 passed
```

### UI 效果

**联系人列表**:
```
🔗 张三
  → [链接] 淘宝闪购领15-12元 | ← 好的谢谢
📊 李四
  ← 亲，干饭大礼包来啦～ ✅点击蓝色链接...
```

**详情面板**:
```
张三
🔗 高频链接分享
上次互动: 2026-07-04 15:30
置信度: 85%

--- 内容统计 ---
链接消息: 8
媒体消息: 3
平均字数: 29
检测到营销关键词

--- 证据 ---
最近7天分享8个链接...
```

---

## 2026-07-04 — Task #22: 消息内容用于 Metrics 计算完成

> 将消息内容分析集成到 Metrics 计算和 Radar 提示生成。

### 完成内容

1. **TInteractionMetric 扩展**
   - `LinkCount`: Integer — 链接消息数量
   - `MediaCount`: Integer — 媒体消息数量 (图片+视频+语音)
   - `AvgTextLength`: Integer — 平均文本长度
   - `HasMarketingKeywords`: Boolean — 是否包含营销关键词

2. **Metrics.Compute 内容分析**
   - 使用 `TMessageParser.Parse` 解析每条消息
   - 统计链接、媒体、文本类型分布
   - 计算平均文本长度
   - 检测营销关键词 (优惠/折扣/红包/活动/促销/下单/购买)

3. **Radar 提示扩展**
   - 新增 `rhtHighLinkSharing` (高频链接分享)
   - 新增 `rhtMarketingPattern` (营销模式)
   - `ComputeHighLinkSharingHint`: 链接数 >= 5 时触发
   - `ComputeMarketingPatternHint`: 检测到营销关键词时触发
   - 内容提示可与其他提示共存

4. **RadarHintTypeToChinese 更新**
   - `rhtHighLinkSharing` → "高频链接分享"
   - `rhtMarketingPattern` → "营销模式"

### 编译与测试

```
DeepAxis.exe: ✅ 0 errors, 0 warnings (14508 lines)
DeepAxisTestRunner.exe: ✅ 21/21 passed
```

### 技术细节

**内容指标计算**:
```pascal
for LMsg in LSorted do
begin
  LParsed := TMessageParser.Parse(LMsg);
  case LParsed.ContentType of
    pctLink: Inc(LLinkCount);
    pctImage, pctVideo, pctVoice: Inc(LMediaCount);
    pctText:
    begin
      Inc(LTextCount);
      LTotalTextLen := LTotalTextLen + Length(LParsed.TextBody);
      if LParsed.TextBody.Contains('优惠') or ... then
        LHasMarketing := True;
    end;
  end;
end;
```

**Radar 提示逻辑**:
- 高频链接分享: LinkCount >= 5 且占比 > 30%
- 营销模式: HasMarketingKeywords = True
- 内容提示与元数据提示独立，可同时触发

---

## 2026-07-04 — Task #21: Pipeline 消息内容分析完成

> 将消息内容分析接入 Pipeline，TagEngine 使用 TParsedMessage 进行标签推断。

### 完成内容

1. **接口扩展**
   - `IWxReader` 添加 `ReadAllMessages` 方法
   - `ITagEngine.DeriveTagsBatch` 接受消息字典参数

2. **TagEngine 内容分析**
   - 新增 `DeriveContentProfile` 方法
   - 统计消息类型分布 (text/link/image/video/voice/system)
   - 计算总字数和平均字数
   - 提取 Top 3 链接域名
   - 检测营销关键词 (优惠/折扣/红包/活动/促销)
   - 检测产品相关词 (产品/商品/下单/购买)

3. **Pipeline 集成**
   - `RadarPanel.DoPoll` 构建 `TDictionary<string, TArray<TMessageMeta>>`
   - 传递消息字典给 `TagEngine.DeriveTagsBatch`
   - 标签 JSON 新增 `content_profile` 字段

4. **测试更新**
   - 移除 `BodyQueried` 断言
   - `TestMessageMetaCreateM0` 更新为期望 `BodyQueried=True`
   - `TMockWxReader` 实现 `ReadAllMessages`

### 编译与测试

```
DeepAxis.exe: ✅ 0 errors, 0 warnings (14375 lines)
DeepAxisTestRunner.exe: ✅ 21/21 passed
```

### 技术细节

- `DeriveContentProfile` 返回 JSON:
  ```json
  {
    "text_count": 42,
    "link_count": 8,
    "image_count": 3,
    "video_count": 1,
    "voice_count": 0,
    "system_count": 2,
    "other_count": 0,
    "total_chars": 1234,
    "avg_chars": 29,
    "has_marketing": true,
    "has_product": false,
    "top_domains": ["taobao.com", "meituan.com", "weixin.com"]
  }
  ```

---

## 2026-07-04 — 联系人搜索过滤

### 功能: RadarPanel 联系人列表搜索

在联系人列表上方添加搜索栏，支持按名称、消息预览或 ContactId 实时过滤。

**新增组件** (RadarPanel.pas):
- `FSearchPanel: TPanel` — 24px 高搜索栏容器
- `FSearchEdit: TEdit` — 带 TextHint 提示的搜索输入框
- `FSearchClearBtn: TButton` — 清除搜索按钮（输入时自动显示）
- `OnSearchChange(Sender)` — 实时过滤，自动恢复首项选中
- `GetSearchFilter` — 返回 trim 后的搜索关键字
- `UpdateContactList` — 过滤匹配联系人名称/消息预览/ContactId（大小写不敏感）

**行为**:
- 输入即时过滤，列表自动刷新
- 匹配失败时显示 "(无匹配结果)"
- 过滤变更时清空选择并自动选中首项
- 搜索为空时显示全部联系人

### 功能: 统计面板可点击筛选

- 待跟进/待回复/降温预警/闲人可广告 标签可点击
- 点击后填入分类过滤词: [跟进]/[回复]/[降温]/[闲人]
- 再次点击取消 (toggle)
- crHandPoint 光标 + Hint 提示

### 功能: 键盘快捷键

- F1-F5: 启动微信/扫描密钥/连接解密/读取联系人/刷新
- Ctrl+F: 聚焦 RadarPanel 搜索框
- RadarPanel.FocusSearch 公开方法

### 功能: 自动连接流程

- 向导完成后自动加载已保存密钥并连接
- 密钥监控捕获后自动连接解密数据库
- 连接成功后立即 ForcePoll (不等待 30 秒)