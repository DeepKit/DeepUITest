# DeepSpec Docs

> Current engineering entry: `../README.md`, `../SPEC.md`, and `CTF.md`.

## Authoritative Documents

| File | Role |
|---|---|
| `../README.md` | Public project entry |
| `../SPEC.md` | Current v1.2-draft protocol and workflow baseline |
| `CTF.md` | Engineering explanation of the CTF method |
| `DeepSpec-当前文档索引-v1.md` | Chinese document index and historical map |
| `DeepSpec-文档优化审查报告-2026-05-20.md` | Current cleanup and optimization report |

## Historical Documents

Many older documents mention "三棵树" because the early MVP model used function/module/view only. The current protocol target is four projections:

```text
function-tree / module-tree / view-tree / data-tree
```

When an old document conflicts with `../SPEC.md`, use `../SPEC.md` as the current engineering baseline. Do not delete old discussion files only because terminology changed; keep them as historical design context unless they leak secrets or are duplicated by a newer authoritative document.

## Editing Rule

New public docs should describe DeepSpec first, then CTF, then ODD or other theory background only when necessary.
