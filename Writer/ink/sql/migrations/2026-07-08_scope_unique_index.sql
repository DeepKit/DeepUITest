-- 迁移：为 writing_decision_sessions 增加 scope 级互斥 index
-- 日期：2026-07-08
-- 目的：保证同一 (project_id, scope_type, scope_id) 只能有一个活跃 session
--
-- 执行前请先确认无冲突数据（同 scope 多 active session）：
--   SELECT project_id, scope_type, COALESCE(scope_id,'') AS sid, count(*) AS n
--   FROM writing_decision_sessions
--   WHERE status IN ('collecting','ai_parsed','awaiting_confirm','needs_human','retryable_failed')
--   GROUP BY project_id, scope_type, sid
--   HAVING count(*) > 1;
-- 若上面返回非空，需先 cancel/confirm 多余的 active session，否则本迁移会失败。
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_decision_session_scope
ON writing_decision_sessions(project_id, scope_type, COALESCE(scope_id, ''))
WHERE status IN ('collecting','ai_parsed','awaiting_confirm','needs_human','retryable_failed');
