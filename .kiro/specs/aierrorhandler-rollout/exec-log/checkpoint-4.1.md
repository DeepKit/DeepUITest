# Checkpoint 4.1：核心单元独立编译

> 时间：2026-05-16
> 验证内容：三个核心单元用 `dcc64.exe` 单独编译

## 结果

| 单元 | ExitCode | 编译规模 |
|------|----------|---------|
| `DeepBase/Core/DeepBase.AIErrorHandler.pas` | 0 | 1948 lines, 33113 bytes code |
| `DeepBase/Core/DeepBase.AIErrorHandler.LLMBridge.pas` | 0 | 18669 lines, 1262 bytes code |
| `DeepBase/Core/DeepBase.AIErrorHandler.Bootstrap.pas` | 0 | 18762 lines, 2054 bytes code |

## 命令

```pwsh
$DCC = 'd:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
& $DCC "-E$DB\Tests\_compile_check" `
       "-U$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "$DB\Core\<unit>.pas"
```

## 残留 hint / warning（均为加性修改前已存在）

- `AIErrorHandler.pas(136) W1000 Symbol 'EStackOverflow' is deprecated` —— 旧代码继承
- `AIErrorHandler.pas(254/278) H2443 Inline 'MessageDlg' not expanded` —— uses 缺 `System.UITypes`，加性修改原则下不动
- `AIErrorHandler.pas(82) H2219 Private symbol 'GetCacheKey' declared but never used` —— 旧代码遗留
- `Bootstrap.pas(113) H2077 Value assigned to 'InstallAIErrorHandler' never used` —— 防御式 `Result := False;` 初值，无害

## 任务 1/2 中顺手修的预先 bug

修了一处 `DeepBase/Features/DeepBase.LLM.Service.pas` 第 431-440 行的语法错误（4 处 Rust 风格 `if-then-else` 表达式赋值，在 Delphi 中非法），是把 LLMBridge 的 `uses DeepBase.LLM.Service` 链路打通的前提。
