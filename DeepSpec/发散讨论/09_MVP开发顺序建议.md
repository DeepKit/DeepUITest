# DeepSpec MVP 开发顺序建议

## 一、P0：第一批必须完成

### 1. 文件夹拖入 / 打开

- 支持拖入项目文件夹；
- 支持打开文件夹；
- 记录最近项目；
- 显示项目路径。

### 2. 项目扫描器

- 递归扫描目录；
- 忽略 `.git / bin / obj / __history / node_modules` 等；
- 分类文档 / 代码 / UI / 配置 / AI 规则文件。

### 3. 扫描报告

- 生成 `scan-report.yaml`;
- 生成 `scan-report.html`;
- WebView2 显示扫描报告。

### 4. Delphi/VCL 识别

- 识别 `.dpr`;
- 识别 `.dproj`;
- 识别 `.pas`;
- 识别 `.dfm`.

### 5. UI 层次树

- 解析 `.dfm`;
- 生成 Form / 控件层级；
- 使用 VCL 原生树控件显示。

### 6. 模块树

- 从目录、Unit、Pas 文件生成模块树；
- 使用 VCL 原生树控件显示。

---

## 二、P1：第二批功能

### 1. 候选功能树

- 从 Caption / Action / 菜单 / 文档标题提取候选功能；
- 标记来源和可信度；
- 用 VCL 原生树控件显示。

### 2. 节点详情区

点击树节点后显示：

- 节点名称；
- 类型；
- 来源文件；
- Caption；
- 关联功能；
- 关联模块；
- 状态；
- 备注。

### 3. 确认基准

支持：

```text
candidate → confirmed
```

将当前树保存为 baseline。

### 4. AI 参考摘要

生成：

```text
ai-reference.md
ai-reference.html
```

只导出，不调用 AI。

---

## 三、P2：后续增强

- 三棵树之间的映射关系；
- 节点搜索；
- 节点过滤；
- 变更记录；
- 决定记录；
- 基准差异对比；
- Git Diff；
- 规格漂移检测；
- 多语言项目支持。

---

## 四、建议第一版演示场景

> 拖入一个 Delphi/VCL 项目目录，DeepSpec 显示扫描报告、UI 层次树、模块树和候选功能树。

这是最能打动用户的 Demo。
