# Legacy media_publish Discovery

- root: `D:\_Progs\.BetterCiv\tools\media_publish`
- python_files: 54
- markdown_files: 60

## 关键入口

| path | role |
|---|---|
| `media_publish/cli.py` | CLI 与 Python API 入口：doctor/check-account/smoke/publish manual-review |
| `media_publish/storage.py` | 当前 SQLite task store，未来映射到 media_publish schema |
| `media_publish/domain.py` | TaskStatus / Checkpoint / PublishKind / task transition |
| `media_publish/zhihu.py` | 知乎结果验证分类 |
| `media_publish/publisher.py` | 发布任务执行器 |
| `media_publish/browser.py` | 浏览器会话封装 |

## Python 文件清单（前 120 条）

| path |
|---|
| `_xhs_pub23.py` |
| `archive/legacy-2026-05-20/__init__.py` |
| `archive/legacy-2026-05-20/__main__.py` |
| `archive/legacy-2026-05-20/adapters/__init__.py` |
| `archive/legacy-2026-05-20/adapters/base.py` |
| `archive/legacy-2026-05-20/adapters/wechat.py` |
| `archive/legacy-2026-05-20/adapters/x.py` |
| `archive/legacy-2026-05-20/adapters/xhs.py` |
| `archive/legacy-2026-05-20/adapters/zhihu.py` |
| `archive/legacy-2026-05-20/content/__init__.py` |
| `archive/legacy-2026-05-20/content/pipeline.py` |
| `archive/legacy-2026-05-20/core/__init__.py` |
| `archive/legacy-2026-05-20/core/action_pipeline.py` |
| `archive/legacy-2026-05-20/core/element_finder.py` |
| `archive/legacy-2026-05-20/core/selector_registry.py` |
| `archive/legacy-2026-05-20/core/session_pool.py` |
| `archive/legacy-2026-05-20/driver/__init__.py` |
| `archive/legacy-2026-05-20/driver/cloak_browser.py` |
| `archive/legacy-2026-05-20/publish_orchestrator.py` |
| `media_publish/__init__.py` |
| `media_publish/account.py` |
| `media_publish/browser.py` |
| `media_publish/cli.py` |
| `media_publish/cookies.py` |
| `media_publish/domain.py` |
| `media_publish/publisher.py` |
| `media_publish/runtime.py` |
| `media_publish/storage.py` |
| `media_publish/zhihu.py` |
| `tests/test_account_readiness.py` |
| `tests/test_browser_answer.py` |
| `tests/test_browser_article.py` |
| `tests/test_cli_account.py` |
| `tests/test_cli_answer.py` |
| `tests/test_cli_article.py` |
| `tests/test_cli_checklist.py` |
| `tests/test_cli_root.py` |
| `tests/test_cli_smoke.py` |
| `tests/test_cli_task_inspection.py` |
| `tests/test_content_validation.py` |
| `tests/test_cookies.py` |
| `tests/test_doctor.py` |
| `tests/test_manual_actions.py` |
| `tests/test_playwright_session.py` |
| `tests/test_publisher_failures.py` |
| `tests/test_runtime.py` |
| `tests/test_sqlite_events.py` |
| `tests/test_sqlite_store.py` |
| `tests/test_state_machine.py` |
| `tests/test_task_store.py` |
| `tests/test_zhihu_publishers.py` |
| `tests/test_zhihu_verification.py` |
| `xhs_pub.py` |
| `xhs_publish_today.py` |

## Phase 1A 接入结论

- 只允许 `manual-review`、`doctor`、`check-account`、`smoke-article`、`smoke-answer`。
- 不调用 `mode=publish`。
- 当前 SQLite 不迁移，只生成 PG 映射草案。
- ArtifactOS 负责 RealPublishGate；media_publish 只负责平台动作。
