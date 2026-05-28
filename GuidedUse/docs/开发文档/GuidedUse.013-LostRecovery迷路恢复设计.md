# GuidedUse.013 - LostRecovery 迷路恢复设计

> 状态：开发文档初版
> 用途：定义善用第一版的迷路恢复对象和 DeepLaunch 样板恢复项

---

## 1. LostRecovery 定位

LostRecovery 不是普通反馈，而是用户偏离主路径后的恢复路由。

它要回答：

```text
用户卡在哪里？
可能原因是什么？
用户可以选择什么？
每个选择回到哪一道门？
是否进入风险分支？
```

---

## 2. 对象结构

```text
LostRecovery
  -> question
  -> possibleReasons[]
  -> options[]
     -> label
     -> nextRoute
     -> riskLevel
  -> recommendedOption
  -> returnStepId
```

---

## 3. 通用恢复入口

播放器固定提供：

```text
我迷路了
找不到按钮
页面不一样
我选错了
我想重来
退出任务
```

---

## 4. DeepLaunch 样板必须覆盖的迷路项

```text
1. 我没看到 DeepLaunch 主界面。
2. 我没看到格子区域。
3. 我找不到空格子。
4. 我不知道选哪个格子。
5. 我右键菜单没出来。
6. 我菜单里没有“编辑”。
7. 我找不到程序路径。
8. 我不知道参数填什么。
9. 保存按钮不能点。
10. 保存后格子没变化。
11. 双击后程序没启动。
12. 我选错格子了。
```

---

## 5. 示例：找不到空格子

```text
question:
  我找不到空格子。

possibleReasons:
  - 当前格子页已满
  - 用户没有识别空格子
  - 所有格子都有内容

options:
  1. 切换到下一页格子
  2. 使用已有格子并确认覆盖
  3. 退出任务，先整理格子

routes:
  1 -> GridAreaGate
  2 -> OverwriteConfirmGate
  3 -> TaskExitGate
```

---

## 6. 示例：右键菜单没出来

```text
question:
  我右键菜单没出来。

possibleReasons:
  - 没有在真实 DeepLaunch 界面右键
  - 右键位置不对应 SelectedTarget
  - DeepLaunch 窗口没有获得焦点

options:
  1. 回到选中格子的提示图，再试一次
  2. 重新选择一个格子
  3. 退出任务

routes:
  1 -> RightClickSelectedCell
  2 -> SelectEmptyCell
  3 -> TaskExitGate
```

---

## 7. 示例：保存按钮不能点

```text
question:
  保存按钮不能点。

possibleReasons:
  - 程序路径为空
  - 路径不是 exe
  - 路径不存在
  - 编辑窗体状态异常

options:
  1. 回到程序路径步骤
  2. 选择另一个 exe 文件
  3. 取消本次编辑

routes:
  1 -> FillProgramPath
  2 -> FillProgramPath
  3 -> SelectEmptyCell
```

---

## 8. 示例：双击后程序没启动

```text
question:
  双击后程序没启动。

possibleReasons:
  - 程序路径无效
  - 参数错误
  - 程序被移动或删除
  - DeepLaunch 配置没有保存成功

options:
  1. 回到编辑窗体检查路径
  2. 清空参数后再试
  3. 重新绑定这个格子
  4. 退出任务

routes:
  1 -> FillProgramPath
  2 -> FillProgramPath
  3 -> SelectEmptyCell
  4 -> TaskExitGate
```

---

## 9. 验收标准

```text
1. 每个关键步骤至少有一个 LostRecovery。
2. LostRecovery 不能只显示文字，必须给出选择。
3. 每个选择必须有 RouteRule。
4. 高风险分支必须标出 riskLevel。
5. 用户总能回到主路径、进入风险分支或退出任务。
```

