# GuidedUse.015 - OCGS 对象映射

> 状态：开发文档初版
> 用途：定义善用内部如何使用 OCGS 概念，但不把 OCGS 作为对外第一表达

---

## 1. 对外与对内

对外表达：

```text
新软件不会用？善用一步步带你用。
```

对内表达：

```text
善用是 OCGS 在软件任务陪跑场景中的落地产品。
```

原则：

```text
用户不需要理解 OCGS；
开发文档和数据模型需要受 OCGS 指导。
```

---

## 2. 对象映射

```text
Output              用户最终要完成的真实任务结果
Gate                当前步骤要通过的门
FieldScene          用户当前所在的软件场域
TargetObject        当前要看的对象或要操作的位置
Action              用户要执行的动作
State               完成动作后应该显现的状态
RouteRule           从当前步骤进入下一步的规则
Feedback            用户被挡住或完成后的提示
LostRecovery        用户迷路后的恢复路线
Trace / Evidence    用户完成、卡住、选择的记录
Seal                善用包封版
```

---

## 3. GuidePackage 对应关系

```text
GuidePackage      -> 一组可封版的任务能力包
TaskJourney       -> 从入口到 Output 的行为链
GuideStep         -> 一道门或场域内的关键动作
SceneVisual       -> FieldScene 的视觉投射
VisualAnchor      -> TargetObject / Gate 的可视化表达
StepInstruction   -> Action + Feedback
RouteRule         -> 路由
LostRecovery      -> 迷路恢复
TraceEvent        -> Evidence / HumanDecisionLog 的轻量记录
```

---

## 4. DeepLaunch 样板映射

```text
Output:
  程序已经绑定到 DeepLaunch 的某个格子 / 单键，并可快速启动。

Gate:
  LaunchVerifyGate
  GridReadyGate
  SaveSuccessGate
  SaveCommandGate
  EditFormGate
  ContextMenuGate
  EmptyGridCellTargetGate
  GridAreaGate
  MainWindowGate
  DeepLaunchAppGate

FieldScene:
  DeepLaunch 主界面
  Grid 区域
  右键菜单浮层
  编辑窗体
  目标程序启动状态

TargetObject:
  候选空格子
  SelectedTarget
  编辑菜单项
  程序路径输入区
  保存按钮
  绑定后的格子
```

---

## 5. 门的粒度原则

```text
1. 一个界面通常是一道场域门。
2. 同一界面内的字段不要连续拆成主链门。
3. 动作门可以存在，但不要滥用。
4. 状态显现门用于确认用户是否真的看到结果。
5. 临时浮层可以作为独立场域门，例如 ContextMenuGate。
```

---

## 6. AI 主持式倒推流程在善用中的用法

设计新善用包时，遵守：

```text
1. 先确认 Output。
2. 再问拿到 Output 前的最后一道门。
3. 再追问该门所在 FieldScene。
4. 逐层倒推到第一道入口门。
5. 再整理成正向播放路径。
6. 每个关键选择记录 HumanDecisionLog。
```

注意：

```text
讨论时倒推，播放给用户时正向呈现。
```

---

## 7. 能力检查规则

善用包封版前应检查：

```text
1. 每条 TaskJourney 必须有 Output。
2. 每个 GuideStep 必须有 FieldScene。
3. 每个 GuideStep 必须有 StepInstruction。
4. 每个 GuideStep 必须有 PrimaryFocusAnchor。
5. 每个关键步骤必须有 ExpectedResult。
6. 每个关键步骤必须有 LostRecovery。
7. 每条 RouteRule 必须有目标步骤或退出策略。
8. 高风险分支必须有明确提示。
```

---

## 8. 后续与 DeepUITest 的关系

后续可以形成闭环：

```text
OCGS-d 设计任务
  -> GuidedUse 制作善用包
  -> 用户按善用完成任务
  -> DeepUITest 测试关键行为链
  -> Bug / 卡点反哺 OCGS-d 和 GuidedUse
```

第一版只保留术语兼容，不强行共享数据库。

