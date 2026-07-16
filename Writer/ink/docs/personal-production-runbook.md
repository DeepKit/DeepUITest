# Ink v2 Scene-first 个人生产运行手册

> 当前Scene-first代码迁移未完成。本手册先规定安全边界；旧Shot生产命令只允许维护历史基线。

当前不存在可执行的schema authority marker、Scene-first生产CLI或既有数据库迁移工具。
因此下列Cutover步骤是目标运行契约，不是现在可以执行的操作手册。

## 生产前

1. 备份数据库；
2. 运行doctor；
3. 在schema authority marker实现后确认authority mode；当前此项应报告“未实现”；
4. 确认不存在未完成cutover；
5. 确认模型配置通过且无明文凭据；
6. 运行Scene-first P0测试。

## 迁移前

- 不对旧accepted章节做无记录修改；
- 不把新Scene影子表用于export；
- 所有新表仅dry-run/backfill；
- 旧导出结果保存hash。

## Cutover

必须：

- 停止写入；
- 完成最后回填；
- 检查FK、hash、active uniqueness；
- 切换accept/export/context；
- 旧Shot路径只读；
- 生成cutover事件；
- 恢复写入。

## Cutover后

- 修订目标为Scene；
- Accept创建Chapter Snapshot；
- Export只读Chapter Head；
- Internal Shot不在作者前台显示为正式版本；
- 任何异常先停止，不直接改数据库正文。

## 恢复

恢复依据数据库Generation Round、Branch Version、Snapshot和Runtime Event，不依赖聊天记录。
