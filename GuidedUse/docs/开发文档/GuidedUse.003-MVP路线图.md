# GuidedUse.003 - MVP 路线图

> 状态：开发文档初版
> 用途：把善用第一版拆成可开发、可验收的阶段

---

## 1. MVP 总原则

第一版只证明一件事：

```text
善用能加载一个本地 GuidePackage，
悬浮在目标软件旁边，
按步骤播放 FocusSketch 和提示语，
让用户完成一个真实任务，
并在迷路时进入恢复路径。
```

不以功能数量判断成败，以“用户是否能跟着它完成任务”判断成败。

---

## 2. MVP-0：数据模型与本地样例包

目标：

```text
定义 GuidePackage JSON，并准备一个可播放的 DeepLaunch 样板包。
```

验收：

```text
1. 有 GuidePackage JSON。
2. 有 SoftwareProfile。
3. 有 TaskJourney。
4. 有至少 5 个 GuideStep。
5. 每个 GuideStep 有 StepInstruction。
6. 每个 GuideStep 有 SceneVisual / FocusSketch。
7. 每个 GuideStep 有 RouteRule。
8. 至少 3 个步骤有 LostRecovery。
```

---

## 3. MVP-1：本地播放器

目标：

```text
不用编辑器，先让本地播放器加载 GuidePackage 并按步骤播放。
```

验收：

```text
1. 能选择一个本地 GuidePackage。
2. 能显示任务标题和当前步骤。
3. 能渲染 FocusSketch。
4. 能显示当前步骤提示语。
5. 点击“已完成”进入下一步。
6. 点击“我迷路了”进入 LostRecovery。
7. 能返回主路径。
8. 能记录 TraceEvent。
```

---

## 4. MVP-2：桌面悬浮播放器

目标：

```text
播放器能以桌面悬浮形式运行，并绑定目标窗口。
```

验收：

```text
1. 播放器可置顶。
2. 可绑定目标窗口。
3. 可显示紧凑步骤面板。
4. 可显示或展开 FocusSketch。
5. 支持已完成、我迷路了、找不到按钮。
6. 目标窗口变化时给出提示。
7. 不遮挡用户主要操作区域。
```

---

## 5. MVP-3：简笔 FocusSketch 编辑器

目标：

```text
先不接 AI，让用户能手动画矩形、设置颜色语义、绑定步骤。
```

验收：

```text
1. 能创建 SceneVisual。
2. 能画矩形 VisualAnchor。
3. 能设置 anchorType。
4. 能设置颜色语义。
5. 能绑定 StepInstruction。
6. 能保存为 GuidePackage JSON。
7. 播放器能渲染编辑结果。
```

---

## 6. MVP-4：DeepLaunch 样板善用包封版

目标：

```text
完成“善用指导 DeepLaunch 绑定第一个快速启动程序”的可播放样板包。
```

验收：

```text
1. 能从善用中选择 DeepLaunch 样板包。
2. 能选择“绑定第一个快速启动程序”任务。
3. 能引导用户进入 DeepLaunch 主界面。
4. 能引导用户选择一个空格子。
5. 能引导用户右键进入编辑。
6. 能引导用户填写路径并保存。
7. 能提示保存成功后的格子状态。
8. 能引导用户验证启动成功。
9. 每个关键卡点都有 LostRecovery。
```

---

## 7. MVP-5：受控问答与 AI 线框草稿

目标：

```text
在主流程稳定后，再接 AI 能力。
```

范围：

```text
1. AI 根据截图生成线框草稿。
2. AI 给出候选 VisualAnchor。
3. 人工确认后发布。
4. 受控问答只回答当前软件、任务、步骤和 LostRecovery 范围内的问题。
```

不做：

```text
开放式万能问答
自动控制目标软件
自动发布 AI 草稿
```

---

## 8. 第一阶段不做清单

```text
1. 不做自动点击。
2. 不做自动填写。
3. 不做复杂 UI Automation。
4. 不做完整 OCR。
5. 不做浏览器插件。
6. 不做多人协作。
7. 不做企业权限。
8. 不做完整云端市场。
9. 不让 AI 草稿直接发布。
```

---

## 9. 当前开发优先级

```text
P0：GuidePackage JSON
P0：本地播放器
P0：DeepLaunch 样板包数据
P1：桌面悬浮播放器
P1：LostRecovery 标准路由
P2：FocusSketch 编辑器
P3：AI 线框草稿生成器
P4：云端同步与模板市场
```

---

## 10. DB1-DB4 阶段边界

```text
MVP-0 到 MVP-4：只要求本地 JSON + DB1 + DB2。
MVP-5：AI 草稿和受控问答可以先做本地或半云端试验。
P4 云端同步与模板市场：正式接 DB3 业务 API。
商业化、登录、订阅、AI 额度、模板付费：正式集成 DeepBase Commerce/Auth 统一模块。
```

原则：

```text
桌面端不直连公网 PG。
桌面端不直连 DB4。
DB3 由 GuidedUse 后端封装成业务 API；DB4 由 DeepBase 框架统一封装，GuidedUse 不自建支付认证流程。
```
