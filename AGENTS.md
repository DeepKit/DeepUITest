# Coding AI Instructions

<!-- BEGIN MANAGED: CODEBASE_QUERY -->
## Codebase-memory first

This workspace has a shared code graph named `business-all`, covering
`D:\_Progs\02Business`. For architecture, symbol discovery, callers/callees,
dependencies, cross-file tracing, dead-code candidates, or refactor impact,
use the controlled `codebase-query` interface before broad recursive search.

Entry point:

```powershell
python -X utf8 D:\_Progs\00Common\skills\codebase-query\scripts\cbq.py projects
python -X utf8 D:\_Progs\00Common\skills\codebase-query\scripts\cbq.py run index_status --project business-all
python -X utf8 D:\_Progs\00Common\skills\codebase-query\scripts\cbq.py run search_graph --project business-all --name-pattern <Symbol>
python -X utf8 D:\_Progs\00Common\skills\codebase-query\scripts\cbq.py run trace_path --project business-all --function-name <Function> --direction both
python -X utf8 D:\_Progs\00Common\skills\codebase-query\scripts\cbq.py run get_architecture --project business-all
```

Required behavior:

1. Run `tools\codebase-memory\status.ps1`. Matching
   `_cbq_meta.head_sha` and Git HEAD is necessary but not sufficient: an
   uncommitted working tree can still diverge from the graph.
2. Prefer graph queries over repository-wide `grep`/`rg` loops.
3. Treat graph results as a derived cache, not as source truth. Confirm the
   relevant source before editing.
4. If the index is stale, incomplete, unavailable, or misses dynamic behavior,
   say so and fall back to targeted read-only source search.
5. Absence from the graph is not proof of absence unless coverage and
   freshness have been checked.
6. Do not call raw `codebase-memory-mcp` write tools. Rebuild/update is
   operator-controlled through `tools\codebase-memory`.
7. Never use `manage_adr`, `ingest_traces`, or `delete_project` automatically.
8. After source edits, treat affected graph results as potentially stale until
   the operator runs `tools\codebase-memory\update.ps1`.

The shared graph is a code-intelligence layer only. It does not replace Git,
tests, source review, BCW/PG governance, or architecture decisions.
<!-- END MANAGED: CODEBASE_QUERY -->

## Web-to-md — 网页转 Markdown

把文章/回答/帖子 URL 转成 `.md` 或结构化源笔记。用常驻 headed patchright
Chromium(CDP 9233)+ 持久登录 profile,能抓需登录态访问的内容(知乎/微信等)。
首次对某站点需手动登录一次,之后 cookie 持久保留。

```powershell
python -X utf8 D:\_Progs\00Common\skills\codebase-query\..\web-to-md\scripts\web_to_md.py <url> --authorized
# 等价于:
python -X utf8 D:\_Progs\00Common\skills\web-to-md\scripts\web_to_md.py <url> --authorized
```

- `--authorized`:写入本地源笔记(抓登录态/版权内容时用,代表已获授权)
- 反爬安全:页面只导航一次,重试在 CDP `Runtime.evaluate` 层重发,服务器只看到一次访问
- 用法细节见 `D:\_Progs\00Common\skills\web-to-md\SKILL.md`

## Agent-reach — 全网调研

用户说"搜/查/调研/看看大家怎么评价 X"时,走 agent-reach 的调研流程,而非零散
WebFetch。流程与触发词见 `D:\_Progs\00Common\skills\agent-reach\SKILL.md`。

## 共享 skill 库位置

所有可复用 skill 在 `D:\_Progs\00Common\skills\`(经本地 junction 链接到本仓库
`./skills/`,仅本地用,已被 .gitignore)。各 skill 用法见其目录下 `SKILL.md`。
