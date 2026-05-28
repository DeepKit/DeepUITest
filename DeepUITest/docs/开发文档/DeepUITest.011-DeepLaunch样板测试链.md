# DeepUITest.011 - DeepLaunch 样板测试链

> 状态：开发文档初版
> 用途：整理 DeepLaunch 作为第一被测对象的三条命脉链

---

## 1. 样板顺序

DeepUITest 第一阶段优先守住 DeepLaunch。

三条命脉链：

```text
1. 已配置启动链
   F1 + X -> 指定程序启动

2. 配置生效链
   绑定程序 -> 保存 -> F1 + X -> 指定程序启动

3. F2 候选执行链
   F2 -> 输入 / 转录 -> 1-9 候选 -> 执行 -> 0 返回 / 取消
```

推进顺序：

```text
先验证遥控启动能力；
再验证配置是否真正生效；
最后验证语义遥控候选机制。
```

---

## 2. 第一样板：已配置启动链

样板名称：

```text
DeepLaunch 遥控启动能力封版测试
```

宝物 Output：

```text
用户通过 F1 + X 成功启动指定目标程序。
```

推荐目标程序：

```text
DeepUITestProbe.exe
```

倒推门禁链：

```text
Output：目标程序成功启动

<- LaunchVerifyGate / 启动验证门
<- HotkeyActionGate / 热键动作门
<- GridReadyGate / Grid 就绪门
<- MainWindowGate / 主界面门
<- DeepLaunchReadyGate / 深启就绪门
```

正向执行链：

```text
DeepLaunchReadyGate
  -> MainWindowGate
  -> GridReadyGate
  -> HotkeyActionGate
  -> LaunchVerifyGate
  -> TargetIdentityGate
```

最小验收：

```text
Runner 能自动执行：
F1 -> X -> 检测 Probe 启动 -> 验证 signal.json -> 写入结果。
```

---

## 3. MVP-1 前置条件

```text
1. DeepLaunch 可运行。
2. X 键已有绑定。
3. X 键绑定目标为 DeepUITestProbe.exe。
4. Probe 路径有效。
5. Probe 可写 signal.json。
6. Runner 有权限发送按键和读取 signal 文件。
```

---

## 4. MVP-1 断言

强断言：

```text
1. Probe 进程存在。
2. Probe 窗口标题包含 run-id。
3. signal.json 存在。
4. signal.json.runId = 当前 run-id。
5. signal.json.caseId = 当前 TestCase。
```

辅助断言：

```text
1. DeepLaunch 进程存在。
2. DeepLaunch 主界面出现。
3. Grid 可见或处于可接收目标键状态。
```

---

## 5. 第二样板：配置生效链

样板名称：

```text
DeepLaunch 配置生效链封版测试
```

宝物 Output：

```text
用户把某个程序绑定到 DeepLaunch 的某个键以后，按 F1 + X 能启动这个新绑定的程序。
```

战略意义：

```text
它验证配置是否真正转化成用户可调用能力，是 DeepUITest 区别于普通 UI 测试的关键样板。
```

普通 UI 测试容易只看：

```text
保存提示是否出现。
```

DeepUITest 要看：

```text
1. 配置是否写入。
2. Grid 是否更新。
3. 运行时 KeyMap / 缓存是否刷新。
4. F1 + X 是否启动新目标。
5. 启动对象是否与配置对象一致。
```

典型 BugPattern：

```text
1. 保存成功但配置未写入。
2. 配置写入但 UI 未刷新。
3. UI 刷新但运行时缓存未刷新。
4. 快捷键映射仍指向旧对象。
5. 路径含空格导致启动失败。
6. 保存成功但启动参数丢失。
7. 配置表与内存态不一致。
```

推进方式：

```text
第二样板 A：最小配置生效链。
第二样板 B：完整用户配置链。
```

---

## 6. 第三样板：F2 候选执行链

样板名称：

```text
DeepLaunch F2 语义遥控候选执行封版测试
```

战略意义：

```text
证明 DeepLaunch 不只是快捷启动器，而是 Windows 遥控器。
```

第一版只测：

```text
1. F2 能唤出输入 / 转录小窗。
2. 固定文本输入后能出现候选。
3. 候选项使用 1-9。
4. 用户选择 1 后执行对应动作。
5. 用户选择 0 后取消 / 返回。
6. 执行后可由 Runner 验证结果。
```

第一版不测：

```text
1. 开放式自然语言理解准确率。
2. 真实语音环境鲁棒性。
3. 多轮复杂对话。
4. 习惯链路学习完整机制。
5. 所有 Provider / Executor。
6. 高风险动作自动执行。
```

分层：

```text
F2-A：文本候选链
F2-B：取消返回链
F2-C：语音转录链
F2-D：习惯链路学习链
```

---

## 7. 样板链状态

```text
MVP-1：进入开发。
MVP-2：待 MVP-1 稳定后细化。
MVP-3：后置，避免语义识别测试拖慢深测。
```

