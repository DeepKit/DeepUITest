# GuidedUse.009 - FocusSketch 编辑器 PRD

> 状态：开发文档初版
> 用途：定义第一版简笔聚焦线框图编辑器

---

## 1. FocusSketch 定义

FocusSketch 是运行时给用户看的聚焦线框图。

它不是完整 UI 复刻，而是：

```text
为了让用户完成当前步骤，必须被看见的最小视觉元素集合。
```

核心原则：

```text
只画当前步骤需要通过的门，其它部分弱化。
```

---

## 2. 第一版目标

第一版编辑器先不接 AI。

目标：

```text
用户能手动画矩形，设置颜色语义，绑定步骤，保存为 GuidePackage JSON，播放器能渲染。
```

---

## 3. 画布

画布能力：

```text
1. 创建空白画布。
2. 设置画布宽高。
3. 可选导入背景截图。
4. 缩放查看。
5. 保存 SceneVisual。
```

第一版可先固定画布尺寸：

```text
1280 x 720
```

---

## 4. 绘制工具

第一版只需要：

```text
矩形工具
文本标签
选择 / 移动
删除
颜色语义选择
绑定当前步骤
```

不做：

```text
自由曲线
复杂箭头
自动识别控件
图层动画
组件库
```

---

## 5. Anchor 类型

```text
PrimaryFocus       当前唯一主操作目标
CandidateTarget    候选目标，可任选其一
ContextFrame       当前场域范围
ExpectedResult     成功后应看到的状态
RiskArea           注意 / 风险区
MutedArea          暂时不用管的区域
RecoveryTarget     迷路恢复目标
```

---

## 6. 颜色语义

```text
粉红实线：当前唯一主操作目标
粉红虚线：候选目标
浅蓝框：当前场域范围
浅黄色：注意 / 风险 / 不要乱点
浅绿色：成功状态
灰色：背景弱化 / 暂时不用管
紫色：可选路径
```

要求：

```text
颜色必须是语义，不只是装饰。
```

---

## 7. 能力检查规则

保存前检查：

```text
1. 每个 Step 必须有一个 PrimaryFocusAnchor。
2. FocusAnchor 不得超过 3 个。
3. 每个 FocusSketch 必须有 ContextFrame。
4. 每个 FocusSketch 必须有 ExpectedResult 或下一步提示。
5. MutedArea 不得覆盖 PrimaryFocus。
6. PrimaryFocus 必须绑定 StepInstruction。
7. 关键步骤必须配置 LostRecovery。
```

违反规则时：

```text
不阻止保存草稿，但不能封版。
```

---

## 8. 编辑器状态

```text
Draft       草稿
Checked     已通过基础检查
Published   已发布到善用包
Sealed      已封版
```

第一版只需要：

```text
Draft
Checked
```

---

## 9. 验收标准

```text
1. 能创建 SceneVisual。
2. 能画出至少 5 个 VisualAnchor。
3. 能设置 anchorType 和 colorRole。
4. 能绑定 GuideStep。
5. 能保存到 GuidePackage。
6. 播放器能渲染。
7. 能用于 DeepLaunch 样板包至少 5 个步骤。
```

