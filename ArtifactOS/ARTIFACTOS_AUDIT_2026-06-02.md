# ArtifactOS 优化审计报告

> 审计日期：2026-06-02
> 交叉参照：AiToEarn v2.4
> 技术路线：Delphi VCL 桌面原生，不做 Web

---

## 一、总体判断

ArtifactOS 的设计骨架——源体系装载、状态机管控、质量门禁分层、会议治理层级、前夜审阅协议、证据化认知骨架——在概念完整性上远超 AiToEarn。

两个项目本质不同：ArtifactOS 是 Delphi 桌面原生 + PG 直连的产出物操作系统，AiToEarn 是 Web-first Docker 全家桶的内容分发工具。以下只报告在 ArtifactOS 自身技术路线内成立的发现。

---

## 二、Bug

### B1 [中等] ConnectLocked 语义错误

**文件**：`src/core/ArtifactOS.Core.DB.Connection.pas:120-128`

```pascal
function TArtifactDB.ConnectLocked: Boolean;
begin
  FLock.Enter;
  try
    Connect;
    Result := IsConnected;
  finally
    FLock.Leave;  // 返回前就释放了锁
  end;
end;
```

方法名叫 `ConnectLocked`，语义应是"持锁连接"，但锁在返回前已释放。调用者拿到连接后没有任何保护。

实际影响取决于调用方——如果 `ConnectLocked` / `DisconnectLocked` 总是成对调用且单线程使用，问题不触发。但这方法给调用者制造了"我持锁了"的假象。

**修正**：删除此方法，直接用 `Connect`。FireDAC 连接池本身是线程安全的。

---

### B2 [低] root 目录有未清理的 ConfigDB 损坏文件

**文件**：`ArtifactOSConfig.db.corrupted_20260528_172521_378`

5 月 28 日发生过 DeepBase ConfigDB (SQLite) 损坏，手工保留了备份。DeepBase 应有自动恢复机制，这次手动兜底说明恢复流程未覆盖此场景。清理文件，排查损坏原因。

---

### B3 [信息] .env 含真实凭据

**文件**：`D:/_Progs/02Business/ArtifactOS/.env`

文件中记录了真实数据库密码。经确认 `.env` 已在 `.gitignore` 中，不会被提交。作为日常使用没有问题——这是用 `check_readiness.py` 的正常方式。仅提醒：此文件不在版本控制内，重装系统前需自行备份。

---

## 三、文档需要同步

### D1 docs/15 §二 "浏览器工作台裁决" 标注废弃

`docs/15` 写 "Amy Desk 1.0 使用浏览器工作台，不使用 Delphi 桌面 UI"，而 `docs/26` 写 Desk 走 Delphi VCL DeepShell。裁决结果已明确——**废除 Python/浏览器层，走 Delphi 原生桌面**。

应同步的三处：

| 文件 | 位置 | 动作 |
|------|------|------|
| `docs/15` | §二 整节 | 标注废弃，指向 `docs/26` §4.1 |
| `DEVELOPMENT.md` | §6 "Amy Desk / 工作台准备" | 移除 `backend/amy_desk.py` 和 `:8765` 引用 |
| `tasks.md` | P5 #35 | "ArtifactOS.Desk DeepShell 骨架" 从 pending 提到当前 |

废弃的代码等 Desk 上线后清理即可，不用提前删——诊断页在 Desk 完工前还有用。

---

## 四、优先级

| # | 项目 | 严重度 | 工作量 |
|---|------|--------|--------|
| B1 | ConnectLocked 语义错误 | 中 | 30min |
| D1 | 文档同步：标注废弃 Python/浏览器 | 高 | 1h |
| B2 | ConfigDB 损坏文件清理 | 低 | 30min |

---

## 五、一句话

ArtifactOS 目前只有一个真正的代码问题（ConnectLocked）和一份需要同步的文档（docs/15 的浏览器工作台裁决）。其余都不是 bug。最高优先级是把 Design Desk DeepShell 骨架做出来——设计已经完备，缺的是实现。