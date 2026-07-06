# DeepAxis Bug 修复记录

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
