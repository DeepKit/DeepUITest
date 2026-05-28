# DeepSpec Controlled Vocabulary

> Status: v1.2-draft

## Extension Rule

Use `x_` for extension kinds and fields. Do not use `x-`.

## Tree Kinds

| Tree | Built-in kinds |
|---|---|
| function | feature, capability, user_story, use_case, rule, constraint, non_functional, integration |
| module | package, unit, class, interface, service, repository, controller, adapter, utility, config |
| view | application, window, dialog, page, frame, panel, control, menu, toolbar, statusbar, tray |
| data | entity, field, relation, state, migration, constraint |

## Risk

Risk is not a tree kind. Use `risk_score` as a field on nodes, bundles, issues, or review summaries.
