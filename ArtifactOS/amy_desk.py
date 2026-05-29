#!/usr/bin/env python
"""ArtifactOS Amy Desk 1.0 minimal browser workspace.

Server-rendered HTML; no frontend build step. Shows today's plan/publish cards,
verification status, and seven-day L3 real publish run board.
"""

from __future__ import annotations

import html
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import psycopg2

CONN = (
    f"host={os.environ.get('ARTIFACTOS_DB_HOST', '127.0.0.1')} "
    f"port={os.environ.get('ARTIFACTOS_DB_PORT', '5432')} "
    f"dbname={os.environ.get('ARTIFACTOS_DB_NAME', 'artifactos_test')} "
    f"user={os.environ.get('ARTIFACTOS_DB_USER', 'fuyi01')} "
    f"password={os.environ.get('ARTIFACTOS_DB_PASS', '')}"
)


def q(sql: str, params=()):
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
        return cur.fetchall()
    finally:
        cur.close()
        conn.close()


def page(title: str, body: str) -> bytes:
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<title>{html.escape(title)}</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background:#0f172a; color:#e2e8f0; margin:0; padding:24px; }}
a {{ color:#7dd3fc; }}
.nav a {{ margin-right:16px; }}
.card {{ background:#111827; border:1px solid #334155; border-radius:12px; padding:16px; margin:14px 0; }}
.grid {{ display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap:14px; }}
.ok {{ color:#86efac; }} .warn {{ color:#fde68a; }} .bad {{ color:#fca5a5; }}
.small {{ color:#94a3b8; font-size:13px; }}
table {{ width:100%; border-collapse:collapse; }} td, th {{ border-bottom:1px solid #334155; padding:8px; text-align:left; }}
button {{ background:#2563eb; color:white; border:0; border-radius:8px; padding:8px 12px; cursor:pointer; }}
</style>
</head>
<body>
<div class="nav">
<a href="/amy/today">Today</a>
<a href="/amy/week">Week</a>
<a href="/amy/verify">Verify</a>
<a href="/amy/accounts">Accounts</a>
<a href="/amy/run">7-Day Run</a>
</div>
<h1>{html.escape(title)}</h1>
{body}
</body></html>""".encode("utf-8")


def today():
    cases = q(
        """
        SELECT id, title, status, created_at
        FROM artifactos.case_record
        WHERE case_type='day_sub'
        ORDER BY created_at DESC
        LIMIT 8
        """
    )
    packages = q(
        """
        SELECT pp.id, a.title, pp.status, pp.publish_verification_status,
               coalesce(pp.publication_url, pp.metadata->>'result_url') as url,
               pp.created_at
        FROM artifactos.publication_package pp
        LEFT JOIN artifactos.artifact a ON a.id = pp.artifact_id
        ORDER BY pp.created_at DESC
        LIMIT 8
        """
    )
    body = '<div class="grid"><div class="card"><h2>今日 DayPlan / DaySubCase</h2><table><tr><th>Title</th><th>Status</th><th>Created</th></tr>'
    for _, title, status, created_at in cases:
        body += f"<tr><td>{html.escape(title or '')}</td><td>{html.escape(status or '')}</td><td>{created_at}</td></tr>"
    body += '</table></div><div class="card"><h2>发布卡片</h2><table><tr><th>Artifact</th><th>Status</th><th>Verify</th><th>URL</th></tr>'
    for pid, title, status, verify, url, _ in packages:
        cls = 'ok' if verify == 'published_confirmed' else ('warn' if verify == 'verify_unknown' else '')
        link = f'<a href="{html.escape(url)}" target="_blank">打开链接</a>' if url else ''
        body += f"<tr><td><a href='/amy/package?id={pid}'>{html.escape(title or str(pid))}</a></td><td>{status}</td><td class='{cls}'>{verify}</td><td>{link}</td></tr>"
    body += '</table></div></div>'
    return page("Amy Today Desk", body)


def package_detail(pid: str):
    rows = q(
        """
        SELECT pp.id, a.title, pp.status, pp.publish_verification_status,
               coalesce(pp.publication_url, pp.metadata->>'result_url') as url,
               pp.media_publish_task_id, pp.publish_verification_evidence, pp.metadata,
               qs.qualified_status, qs.sealed_at
        FROM artifactos.publication_package pp
        LEFT JOIN artifactos.artifact a ON a.id = pp.artifact_id
        LEFT JOIN artifactos.quality_snapshot qs ON qs.id = pp.quality_snapshot_id
        WHERE pp.id=%s
        """,
        (pid,),
    )
    if not rows:
        return page("Package not found", "<p class='bad'>Package not found</p>")
    pid, title, status, verify, url, task_id, evidence, metadata, qstatus, sealed_at = rows[0]
    body = f"""
<div class="card">
<h2>{html.escape(title or '')}</h2>
<p>Status: <b>{status}</b> / Verify: <b>{verify}</b></p>
<p>Quality: {qstatus} / sealed_at: {sealed_at}</p>
<p>media_publish_task_id: {task_id}</p>
<p>URL: {'<a target="_blank" href="'+html.escape(url)+'">打开发布链接</a> ' + html.escape(url) if url else 'none'}</p>
<div style="display:flex; gap:10px; flex-wrap:wrap; margin-top:12px;">
<form method="post" action="/amy/verify?id={pid}"><button>自动访问验证</button></form>
<form method="post" action="/amy/mark?id={pid}&status=published_confirmed"><button style="background:#16a34a">人工确认已发布</button></form>
<form method="post" action="/amy/mark?id={pid}&status=verify_unknown"><button style="background:#ca8a04">标记待确认</button></form>
<form method="post" action="/amy/mark?id={pid}&status=failed"><button style="background:#dc2626">标记失败</button></form>
</div>
</div>
<div class="card"><h3>Evidence</h3><pre>{html.escape(str(evidence))}</pre></div>
<div class="card"><h3>Metadata</h3><pre>{html.escape(str(metadata))}</pre></div>
"""
    return page("Publication Package", body)


def verify_queue():
    rows = q(
        """
        SELECT pp.id, a.title, pp.status, pp.publish_verification_status,
               coalesce(pp.publication_url, pp.metadata->>'result_url') as url
        FROM artifactos.publication_package pp
        LEFT JOIN artifactos.artifact a ON a.id = pp.artifact_id
        WHERE coalesce(pp.publication_url, pp.metadata->>'result_url') IS NOT NULL
          AND pp.publish_verification_status != 'published_confirmed'
        ORDER BY pp.created_at DESC
        LIMIT 20
        """
    )
    body = '<div class="card"><table><tr><th>Artifact</th><th>Status</th><th>Verify</th><th>Action</th></tr>'
    for pid, title, status, verify, url in rows:
        body += f"<tr><td><a href='/amy/package?id={pid}'>{html.escape(title or str(pid))}</a></td><td>{status}</td><td>{verify}</td><td><form method='post' action='/amy/verify?id={pid}'><button>Verify</button></form></td></tr>"
    body += '</table></div>'
    return page("Published Verification Queue", body)


def accounts():
    rows = q(
        """
        SELECT pp.platform,
               coalesce(pp.metadata->>'account_id', pp.account_id::text, 'unknown') as account_id,
               count(*) as packages,
               max(pp.created_at) as last_seen,
               count(*) filter (where pp.status in ('queued','submitting','submitted')) as active_tasks,
               count(*) filter (where pp.publish_verification_status='published_confirmed') as confirmed,
               count(*) filter (where pp.publish_verification_status in ('verify_unknown','failed')) as needs_attention
        FROM artifactos.publication_package pp
        GROUP BY 1, 2
        ORDER BY last_seen DESC
        """
    )
    body = """
<div class="card">
<p class="small">硬规则：一个浏览器 = 一个平台 + 一个账号。禁止同一 browser/profile 跨平台切换。</p>
<table><tr><th>Platform</th><th>Account</th><th>Session Key</th><th>Runtime State</th><th>Packages</th><th>Confirmed</th><th>Needs Attention</th><th>Last Seen</th></tr>
"""
    for platform, account_id, packages, last_seen, active, confirmed, needs_attention in rows:
        if active:
            state = '<span class="warn">busy</span>'
        elif needs_attention:
            state = '<span class="bad">needs_review</span>'
        else:
            state = '<span class="ok">ready_or_idle</span>'
        session_key = f"{platform}/{account_id}"
        body += f"<tr><td>{html.escape(platform or '')}</td><td>{html.escape(account_id or '')}</td><td>{html.escape(session_key)}</td><td>{state}</td><td>{packages}</td><td>{confirmed}</td><td>{needs_attention}</td><td>{last_seen}</td></tr>"
    body += "</table></div>"
    body += """
<div class="card">
<h2>Runtime actions planned</h2>
<ul>
<li>启动/显示某个 platform+account 浏览器</li>
<li>截图当前页面并写入证据</li>
<li>检查登录态 / 风控 / 验证码</li>
<li>只关闭指定 platform+account 浏览器，不影响同账号其他平台</li>
</ul>
</div>
"""
    return page("Platform Account Browser Sessions", body)


def week():
    rows = q(
        """
        SELECT id, case_code, case_type, title, status, planning_nature, created_at
        FROM artifactos.case_record
        WHERE case_type in ('year','week','day','day_sub') OR case_code like 'yearcase_%' OR case_code like 'daycase_%'
        ORDER BY created_at DESC
        LIMIT 30
        """
    )
    body = '<div class="card"><p class="small">1.0 path: YearCase -> Weekly Meeting / WeekCase -> DayPlan / DaySubCase -> PublishPackage.</p><table><tr><th>Code</th><th>Type</th><th>Title</th><th>Status</th><th>Nature</th></tr>'
    for _, code, typ, title, status, nature, _ in rows:
        body += f"<tr><td>{html.escape(code or '')}</td><td>{html.escape(typ or '')}</td><td>{html.escape(title or '')}</td><td>{status}</td><td>{nature}</td></tr>"
    body += '</table></div>'
    return page("Week Governance", body)


def mark_package(package_id: str, status: str):
    if status not in ('published_confirmed', 'verify_unknown', 'failed'):
        raise ValueError('invalid manual status')
    package_status = {
        'published_confirmed': 'published',
        'verify_unknown': 'verify_unknown',
        'failed': 'failed',
    }[status]
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT run_mode, simulation_only, status
            FROM artifactos.publication_package
            WHERE id=%s
            """,
            (package_id,),
        )
        row = cur.fetchone()
        if not row:
            raise ValueError('package not found')
        run_mode, simulation_only, current_status = row
        if run_mode != 'real' or simulation_only:
            package_status = current_status
        cur.execute(
            """
            UPDATE artifactos.publication_package
            SET status=%s,
                publish_verification_status=%s,
                publish_verified_at=now(),
                publish_verification_evidence = publish_verification_evidence || jsonb_build_object(
                  'manual_mark', %s,
                  'manual_marked_at', now()
                ),
                metadata = metadata || jsonb_build_object('verification_status', %s, 'manual_verified', true)
            WHERE id=%s
            """,
            (package_status, status, status, status, package_id),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close(); conn.close()


def run_board():
    rows = q(
        """
        SELECT date_trunc('day', pp.created_at)::date as day,
               count(*) as packages,
               count(*) filter (where pp.status='published' and pp.publish_verification_status='published_confirmed') as green,
               count(*) filter (where pp.status in ('failed','verify_unknown') or pp.publish_verification_status in ('failed','verify_unknown')) as red
        FROM artifactos.publication_package pp
        WHERE pp.created_at >= now() - interval '7 days'
        GROUP BY 1
        ORDER BY 1 DESC
        """
    )
    body = '<div class="card"><h2>7 天 L3 real_publish 全绿面板</h2><table><tr><th>Day</th><th>Packages</th><th>Green</th><th>Red/Unknown</th><th>Result</th></tr>'
    for day, packages, green, red in rows:
        result = '<span class="ok">GREEN</span>' if packages and packages == green and red == 0 else '<span class="bad">NOT GREEN</span>'
        body += f"<tr><td>{day}</td><td>{packages}</td><td>{green}</td><td>{red}</td><td>{result}</td></tr>"
    body += '</table></div>'
    return page("7-Day Run Board", body)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path)
        qs = parse_qs(path.query)
        if path.path in ('/', '/amy/today'):
            data = today()
        elif path.path == '/amy/week':
            data = week()
        elif path.path == '/amy/verify':
            data = verify_queue()
        elif path.path == '/amy/accounts':
            data = accounts()
        elif path.path == '/amy/run':
            data = run_board()
        elif path.path == '/amy/package':
            data = package_detail(qs.get('id', [''])[0])
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path = urlparse(self.path)
        qs = parse_qs(path.query)
        if path.path == '/amy/verify' and qs.get('id'):
            from tests.verify_published_url import verify
            verify(qs['id'][0])
            self.send_response(303)
            self.send_header('Location', f"/amy/package?id={qs['id'][0]}")
            self.end_headers()
            return
        if path.path == '/amy/mark' and qs.get('id') and qs.get('status'):
            mark_package(qs['id'][0], qs['status'][0])
            self.send_response(303)
            self.send_header('Location', f"/amy/package?id={qs['id'][0]}")
            self.end_headers()
            return
        self.send_response(404); self.end_headers()


if __name__ == '__main__':
    port = int(os.environ.get('ARTIFACTOS_AMY_PORT', '8765'))
    print(f"Amy Desk: http://127.0.0.1:{port}/amy/today")
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
