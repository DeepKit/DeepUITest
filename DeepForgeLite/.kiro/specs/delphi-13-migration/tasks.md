# DeepDevLite — Delphi 13.1 迁移任务包

> 所属分组：Group C（IDE 类 & 编辑器）— 组内优先级 3
> 项目定位：DeepDev 轻量版,小型项目
> 升级收益：跟随 DeepDev 主项目自然迁移
> 前置条件：DeepBase 阶段 1 已完成（已解除，commit 68356aa）
> 总纲参考：`02Business/docs/delphi-13-migration/README.md`

---

## 阶段 0：准备

- [x] 0.1 确认 DeepBase 已完成 13.1 迁移（upgrade/delphi-13 @ 68356aa）
- [x] 0.2 备份（`.dproj.12.bak`，本目录不在独立 git 仓库，无法打 tag）
- [x] 0.3 确认 12.3 下可编译,记录 Warning 基线
- [x] 0.4 （跳过）创建分支 — 无独立 git 仓库

## 阶段 1：环境切换

- [x] 1.1 更新编译脚本
- [x] 1.2 用 13.1 IDE 打开,升级 dproj（ProjectVersion 20.4, ProjectFileVersion 13）
- [x] 1.3 DeepBase BPL 引用（正确）
- [x] 1.4 与 DeepDev 共享组件（仅 DeepBase，无 Skia 直接依赖）
- [x] 1.5 检查 Search Path（无 Studio\23.0 硬编码）

## 阶段 2：编译修复

- [x] 2.1 Clean + Build（Win32 成功，18,406 行 / 1.70s，产出 `bin\DeepDevLite.exe` 40MB）
- [x] 2.2 修复编译错误（无错误）
- [x] 2.3 处理 Warning（评估结论：保持基线，不阻塞迁移）

## 阶段 3：语法现代化

- [x] 3.1 选 1 个核心文件做三元 + inline var 重构（HelperJson.pas）

## 阶段 4：DeepBase 13.1 集成收尾

- [x] 4.1 `DeepDevLite.dproj` Search Path 从无效 `..\DeepBase\Source` 改为 `..\DeepBase\TestResults\dcu32;dcp32;Core;FMX;Persistence;Features`
- [x] 4.2 验证无 DeepBase API / Package 断链
- [ ] 4.3 冒烟测试：启动 `DeepDevLite.exe` 验证基本功能
- [ ] 4.4 （父目录统一 commit 时顺带提交）

## 阶段 5：收尾

- [x] 5.1 更新 CHANGELOG
- [ ] 5.2 （无独立分支可合并，跳过 tag 步骤）

---

## DoD

- [x] Clean + Build 成功（Win32）
- [ ] 冒烟测试通过
- [x] Warning ≤ 基线
