# DeepSpec MVP 最终边界：项目目录读取与结构树呈现

## 一、MVP 一句话

> **用户把一个项目文件夹拖进 DeepSpec，DeepSpec 从该目录中读取已有文档、代码、UI、配置和 AI 规则文件，生成项目扫描报告、模块树、UI 层次树和候选功能树。**

---

## 二、MVP 输入方式

### 第一入口

```text
拖入项目文件夹
```

### 第二入口

```text
打开项目文件夹
```

不以以下方式为主：

- 不是粘贴内容；
- 不是问答采集；
- 不是从零生成需求；
- 不是内置 AI 聊天。

---

## 三、MVP 读取对象

### 1. 文档文件

- `.md`
- `.txt`
- `.html`
- `.yaml`
- `.json`
- README
- CHANGELOG
- TODO
- Handoff
- 需求说明
- 接口说明
- 技术方案

### 2. 代码文件

优先支持 Delphi / VCL：

- `.dpr`
- `.dproj`
- `.pas`
- `.dfm`

后续扩展：

- `.fmx`
- `.ts`
- `.tsx`
- `.js`
- `.py`
- `.cs`
- `.go`
- `.java`

### 3. UI 文件

- `.dfm`
- `.fmx`
- HTML 原型；
- UI 说明文档；
- 截图；
- 图片；
- 手绘草图。

### 4. 配置文件

- `.ini`
- `.json`
- `.yaml`
- `.config`
- `.env.example`

### 5. AI 规则文件

- `AGENTS.md`
- `CLAUDE.md`
- `.cursor/rules`
- `opencode.json`
- `README_AI.md`

---

## 四、MVP 输出对象

MVP 输出：

1. 项目扫描报告；
2. 模块树；
3. UI 层次树；
4. 候选功能树；
5. 文档文件清单；
6. 代码文件清单；
7. UI 文件清单；
8. 配置文件清单；
9. AI 规则文件清单；
10. AI 参考摘要；
11. 可确认的结构基准。

---

## 五、MVP 最小闭环

```text
拖入项目文件夹
  ↓
扫描文件
  ↓
分类文档 / 代码 / UI / 配置 / AI 规则
  ↓
识别 Delphi 工程
  ↓
解析 .dfm 生成 UI 层次树
  ↓
解析目录与 .pas 生成模块树
  ↓
从 Caption / Action / 菜单 / 文档标题提取候选功能树
  ↓
生成 scan-report.html
  ↓
VCL 显示三棵树
  ↓
WebView2 显示报告和详情
  ↓
用户确认树或节点为基准
  ↓
导出 AI 参考摘要
```
