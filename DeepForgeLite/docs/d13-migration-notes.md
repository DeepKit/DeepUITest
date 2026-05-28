# DeepDevLite — Delphi 13.1 迁移记录

> 项目：DeepDevLite（DeepDev 轻量版, 小型 FMX）
> 分组：Group C — IDE 类 & 编辑器（优先级 3）
> 开始日期：2026-05-09

---

## 阻塞项

- [ ] 0.1 确认 DeepBase 已完成 13.1 迁移 — `[BLOCKED: DeepBase]`
- [ ] 全项目 Build（等 DeepBase BPL 就绪后重试）
- [ ] 冒烟测试（等 exe 可生成后执行）
- 阻塞原因：uses DeepBase.Manager / Config / Logging / i18n / DB.DoQry / Security
- 预计解除：DeepBase 迁移完成后

## 环境说明

- 本项目目录不在独立 git 仓库中，无法打 pre-d13 tag。使用 `.dproj.12.bak` 作为本地备份。
- 目标平台：Win32（单平台）
- 框架：FMX
- 依赖：DeepBase Core 6 个单元（Manager / Config / Logging / i18n / DB.DoQry / Security）

## 已完成项

- [x] 0.3 记录 Warning 基线（见下方，无 build log 可查，需 DeepBase 就绪后回溯）
- [x] 1.1 更新编译脚本调用 `delphi-13.1.bat`
- [x] 1.2 升级 dproj（ProjectVersion 20.4, ProjectFileVersion 13）
- [x] 1.3 DeepBase BPL 引用（路径正确，实际就绪依 DeepBase）
- [x] 1.4 与 DeepDev 共享组件（仅 DeepBase，无 Skia 直接依赖）
- [x] 1.5 Search Path 检查（无硬编码 23.0 路径）
- [x] 3.1 语法现代化（HelperJson.pas 三元 + inline var）

## 迁移要点

- 原 dproj ProjectVersion: 20.2 → 20.4
- ProjectFileVersion: 12 → 13
- build.bat 已切换到统一 env 脚本


---

## DeepBase 13.1 集成记录（2026-05-10）

### 集成状态

- **DeepBase 分支**：`upgrade/delphi-13`
- **DeepBase commit**：`68356aa` (HEAD)
- **Delphi 版本**：13.1 Florence / BDS 37.0
- **编译结果**：✅ 成功
- **输出 exe**：`bin\DeepDevLite.exe` (40MB)
- **编译行数**：18,406 行
- **编译耗时**：1.70 秒

### 修改过的文件

- `DeepDevLite/DeepDevLite.dproj` — Search Path 从 `..\DeepBase\Source`（无效路径）改为 `..\DeepBase\TestResults\dcu32;dcp32;Core;FMX;Persistence;Features`

### 无 DeepBase 断链

所有 DeepBase 单元正确解析。

### 仍需人工确认

- [ ] 冒烟测试：启动 DeepDevLite.exe 验证基本功能
