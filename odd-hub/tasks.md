# odd-hub 路线图任务清�?
> 更新日期�?026-02-23（第二步全部完成�?
---

## 第一步：odd-core MVP（目标：2周）�?
> 前提：完成后 GitHub 才有可运行工具，所有推广渠道才能启动�?
- [x] 搭建 odd-core 包结构（`src/odd/__init__.py`、`pyproject.toml`�?- [x] `odd init` �?在当前目录初始化 `.odd/` 目录和配置文�?- [x] `odd verify <file>` �?单文件契约验证（�?odd-demo 重构�?  - 加载契约 YAML，静态规则验证（must_contain_any / must_not_contain / should_contain�?  - 输出结构化验证报告（rich 表格�?- [x] `odd seal` �?本地封存
  - 计算契约 + 代码 + 验证结果�?SHA-256 哈希�?  - 输出 `.odd/seals/seal_<id>.json`
- [x] CLI 入口（click），支持 `odd --help`
- [x] 基础测试（`tests/test_core.py`�? 个用例全过）
- [x] README 可运行示�?
---

## 第二步：社区基础（目标：�?-4周）

 [x] `odd verify --all` �?项目级批量验�? [x] `odd template pull <name>` �?从模板库拉取契约模板（内�?15 个模板）
 [x] `odd template push <file>` �?向模板库贡献契约模板
 [x] FREEZE 状�?�?锁定契约，禁止未经审批的修改（`odd freeze` / `odd unfreeze`�? [x] AI 语义验证层（第二层）�?调用 LLM 对代码语义做深度验证（`odd verify --ai`，支�?OpenAI 兼容接口�? [x] 插件机制骨架 �?支持自定义验证规则插件（`odd/plugins.py`，BasePlugin ABC + PluginRegistry�?
---

## 第三步：Assayer 集成（目标：�?-6周）

 [ ] odd-core 内置 `Assayer-cloud` provider（由同事负责�? [ ] 注册 �?充�?�?`odd verify` 一条龙流程（由同事负责�? [ ] 云端封存（封存记录上链到 Assayer 服务）（由同事负责）
 [ ] 验证徽章生成（Markdown badge，可嵌入 README）（由同事负责）

---

## 第四步：社区运营（持续）

 [x] 契约模板库冷启动 �?内置 15 个常见场景模�?  - auth_login、crud_api、cache_layer、parser、filter、event_handler、config_loader、background_job、webhook、rate_limiter、logger �?- [ ] 语言插件扩展
  - Python（内置）
  - JavaScript / TypeScript（社区贡献）
  - Go（社区贡献）
  - Rust（社区贡献）
- [ ] 失效案例�?�?收集"�?ODD 做了但失败了"的案例，持续改进

---

## 推广任务（与开发并行）

> 详细执行方案�?`docs/推广/` 目录。前提：odd-core MVP 完成，GitHub 有可运行工具�?
- [ ] 知乎：潜伏期�?个月）�?�?AI 编程质量"相关问题下积�?10+ 高赞回答
- [ ] B站：录制实验视频 �?"同一个AI，两种工作流，缺陷率差了59%"
  - 前提：odd-core 有可运行 demo
  - 脚本�?`docs/推广/02.B站视频脚�?md`
 [x] GitHub：完�?odd-core 仓库
  - [x] README 含可运行示例
  - [x] 实验数据和论文链接（`README.md` 相关链接节）
  - [x] Contributing 指南（`CONTRIBUTING.md`�?- [ ] X / 即刻：高频短内容输出（每�?3-5 条）
- [ ] 掘金：深度实战文章（知乎/B站有流量后）

---

## 当前状�?
| 模块 | 状�?|
|------|------|
| odd-demo | 完成（有代码、文档、实验数据） |
| odd-core | **第二步完�?* �?MVP + 模板�?15 �?+ AI 验证 + 插件机制 + Contributing 指南 �?|
| 推广文档 | 完成（数据已修正为真实实验数据） |
| Assayer 集成 | 由同事负责，文档待对�?|
