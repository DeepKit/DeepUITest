# DeepAxis 开发任务
> **创建**: 2026-06-14
> **状态**: 产品设计完成 — 文档体系 (00-10) + 架构决策 + 底座文档 (32-36.data) | WxDecryptProbe v0.2 编译通过，微信 4.x key derivation 已阻塞
> **维护规则**: `tasks.md` 只保留当前待办和下一步任务；已完成任务归档到 `history.md`；Bug 修复记录写入 `bugfix.md`。

---

## 文档导航

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 项目说明 |
| [docs/07.开发层-P0技术验证规格.md](docs/07.开发层-P0技术验证规格.md) | P0 开发唯一入口 |
| [docs/09.开发层-技术架构规格.md](docs/09.开发层-技术架构规格.md) | 技术架构 |
| [docs/10.开发层-UI设计规格.md](docs/10.开发层-UI设计规格.md) | UI 设计 |
| [history.md](history.md) | 已完成任务归档 |
| [bugfix.md](bugfix.md) | Bug 修复记录 |

---

## P0 技术验证 — 待办 (BLOCKED)

### P0a: 数据可达性

- [ ] **P0a-1**: 完成微信 4.x 数据库加密方案逆向分析
  - 状态: 🔴 **BLOCKED** — Weixin.dll 内存扫描 0 密钥候选, header 非 "SQLite format 3"
  - 下一步: IDA/Ghidra 调试器动态分析 Weixin.dll 的 DB 打开调用
  - Bug 记录: [bugfix.md#1](bugfix.md)
- [ ] **P0a-2**: 实现微信 4.x 解密适配 (WxDecryptProbe v0.3+)
- [ ] **P0a-3**: 实现 SchemaAdapter 字段映射 (TWeChat4xAdapter)
- [ ] **P0a-4**: 实现 WxContactReader / WxMessageReader / WxPoller

### P0b: 元数据有效性

- [ ] **P0b-1**: 实现 RadarEngine (客户雷达提示引擎)
- [ ] **P0b-2**: 实现 InteractionMetric 计算 (频率/延迟/比率)
- [ ] **P0b-3**: 实现 TagEngine L0 (备注正则提取 + 微信标签推断)

### P0c: 隐私与证据

- [ ] **P0c-1**: 实现 BodyZeroAuditor
- [ ] **P0c-2**: 实现隐私分流 (PRIVATE/IDLE 隔离)
- [ ] **P0c-3**: 实现证据链导出 + 删除级联

---

## 底座能力 — DeepBase 32-36.data

- [ ] **32.data**: 实现 TExternalSQLiteReader (取决于 P0a 解密方案确定)
- [ ] **33.data**: 实现 TBaseSchemaAdapter 框架
- [ ] **34.data**: 实现 TUIAEngineWin32 (UIA COM 封装)
- [ ] **35.data**: 实现 TClipboardGuard + TWindowMonitor
- [ ] **36.data**: Skia4Delphi 7.1.0 集成 + TSparkline / TRingChart / THeatmap

---

## 文档待补

- [ ] **11.开发层-话术引擎规格.md**: 模板变量体系 + M1上下文 + LLM 三阶段
- [ ] **12.开发层-首次用户体验规格.md**: 5分钟 onboarding 五幕设计
- [ ] 更新 **09.技术架构规格.md** §5 P0 组件清单 (添加 probe 目录引用)
