# GuidedUse.011 - DeepLaunch 样板善用包

> 状态：开发文档初版
> 用途：定义第一条可播放样板任务

---

## 1. 样板定位

第一条样板：

```text
善用指导 DeepLaunch 绑定第一个快速启动程序。
```

样板价值：

```text
1. 场景清楚。
2. 步骤可控。
3. 有真实桌面软件。
4. 能展示 FocusSketch。
5. 能展示 LostRecovery。
6. 能和 DeepUITest 后续测试链形成闭环。
```

---

## 2. 宝物 Output

```text
一个程序已经成功绑定到 DeepLaunch 的某个格子 / 单键，并可快速启动。
```

完成状态：

```text
用户能看到目标格子已经有名称或图标，并能通过双击格子或单键启动目标程序。
```

风险等级：

```text
L1：低风险配置，可撤回。
```

覆盖已有格子时升级为：

```text
L2：会改变已有配置，需要确认。
```

---

## 3. 第一版主路径

第一版采用右键编辑路线：

```text
启动 DeepLaunch
  -> 进入主界面
  -> 找到格子区域
  -> 选择空格子
  -> 右键打开菜单
  -> 点击编辑
  -> 填写程序路径
  -> 保存
  -> 看到格子名称或图标
  -> 验证启动成功
```

拖拽 exe 路线作为补充路径，第一版可先不实现。

---

## 4. GuideStep 草案

```text
1. OpenDeepLaunch
   提示用户打开 DeepLaunch。

2. FindMainWindow
   确认用户看到 DeepLaunch 主界面。

3. FindGridArea
   用浅蓝框标出格子区域。

4. SelectEmptyCell
   用粉红虚线标出候选空格子，用户在图上选择一个。

5. RightClickSelectedCell
   保持选中格子的提示，指导用户在真实界面对应位置右键。

6. ClickEditMenu
   用临时菜单线框图标出“编辑”。

7. FillProgramPath
   在编辑窗体中提示选择或填写程序路径。

8. SaveConfig
   路径有效后提示点击保存。

9. CheckGridReady
   提示用户确认格子出现名称或图标。

10. VerifyLaunch
   提示双击格子或按单键启动目标程序。
```

---

## 5. SelectedTarget 规则

多个空格子可用时：

```text
1. FocusSketch 用粉红虚线标出候选格子。
2. 用户在善用线框图里点选一个候选格子。
3. 系统记录 SelectedTarget。
4. 后续 ContextMenuGate 依附于 SelectedTarget。
```

第一版推荐：

```text
L1 图上选择。
```

不做：

```text
真实窗口坐标自动映射。
```

---

## 6. 每道门的视觉表达

```text
DeepLaunchAppGate：提示打开 DeepLaunch。
MainWindowGate：浅蓝框标出主界面。
GridAreaGate：浅蓝框标出格子区域。
EmptyGridCellTargetGate：粉红虚线标出候选空格子。
ContextMenuGate：临时菜单线框图，编辑项粉红实线。
EditFormGate：浅蓝框标出编辑窗体。
SaveCommandGate：保存按钮粉红实线。
GridReadyGate：格子名称或图标浅绿色。
LaunchVerifyGate：目标程序窗口浅绿色。
```

---

## 7. 第一版验收

```text
1. 样板包能被播放器加载。
2. 用户能从第一步走到最后一步。
3. 每一步都有 StepInstruction。
4. 每一步都有 FocusSketch。
5. 关键步骤有 LostRecovery。
6. 用户能理解当前要看哪里、点哪里、完成后看什么。
7. 不依赖自动点击。
8. 不依赖真实窗口坐标映射。
```

