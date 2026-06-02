#!/usr/bin/env python
"""ArtifactOS 1.0 published verifier.

Confirms publication by visiting result_url and checking page accessibility plus title/body evidence.
ArtifactOS does not retry publishing; media_publish owns retries. This verifier only records result and alerts humans via status.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

import psycopg2

CONN = (
    f"host={os.environ.get('ARTIFACTOS_DB_HOST', '127.0.0.1')} "
    f"port={os.environ.get('ARTIFACTOS_DB_PORT', '5432')} "
    f"dbname={os.environ.get('ARTIFACTOS_DB_NAME', 'artifactos_test')} "
    f"user={os.environ.get('ARTIFACTOS_DB_USER', 'fuyi01')} "
    f"password={os.environ.get('ARTIFACTOS_DB_PASS', '')}"
)


def fetch_url(url: str) -> tuple[int, str, str]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 ArtifactOS-PublishedVerifier/1.0",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read(512_000).decode("utf-8", errors="ignore")
        final_url = resp.geturl()
        return resp.status, final_url, body


def verify(package_id: str) -> dict:
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT pp.id, pp.publication_url, pp.metadata->>'result_url', a.title,
                   av.assembled_payload->>'body', pp.run_mode, pp.simulation_only, pp.status
            FROM artifactos.publication_package pp
            JOIN artifactos.artifact a ON a.id = pp.artifact_id
            JOIN artifactos.artifact_version av ON av.id = pp.artifact_version_id
            WHERE pp.id = %s
            """,
            (package_id,),
        )
        row = cur.fetchone()
        if not row:
            raise RuntimeError(f"package not found: {package_id}")

        _, publication_url, metadata_url, title, body, run_mode, simulation_only, current_status = row
        result_url = publication_url or metadata_url
        if not result_url:
            evidence = {"error": "missing_result_url", "checked_at": datetime.now(timezone.utc).isoformat()}
            status = "failed"
            package_status = "failed"
        else:
            try:
                http_status, final_url, html = fetch_url(result_url)
                title_hit = title in html
                first_sentence = (body or "").split(". ")[0].strip()
                body_hit = bool(first_sentence and first_sentence[:80] in html)
                login_like = "登录" in html or "signin" in final_url.lower()
                not_found = http_status == 404 or "404" in html[:2000]
                confirmed = http_status == 200 and not login_like and not not_found and (title_hit or body_hit)
                status = "published_confirmed" if confirmed else "verify_unknown"
                package_status = "published" if confirmed else "verify_unknown"
                evidence = {
                    "result_url": result_url,
                    "final_url": final_url,
                    "http_status": http_status,
                    "title_hit": title_hit,
                    "body_hit": body_hit,
                    "login_like": login_like,
                    "not_found": not_found,
                    "checked_at": datetime.now(timezone.utc).isoformat(),
                }
            except Exception as exc:
                status = "verify_unknown"
                package_status = "verify_unknown"
                evidence = {
                    "result_url": result_url,
                    "error": str(exc),
                    "checked_at": datetime.now(timezone.utc).isoformat(),
                }

        if run_mode != "real" or simulation_only:
            package_status = current_status

        cur.execute(
            """
            UPDATE artifactos.publication_package
            SET status = %s,
                publish_verification_status = %s,
                publish_verified_at = now(),
                publication_url = coalesce(publication_url, %s),
                publish_verification_evidence = %s::jsonb,
                metadata = metadata || %s::jsonb
            WHERE id = %s
            """,
            (
                package_status,
                status,
                evidence.get("result_url"),
                json.dumps(evidence),
                json.dumps({"verification_status": status}),
                package_id,
            ),
        )
        conn.commit()
        return {"package_id": package_id, "status": status, "package_status": package_status, "evidence": evidence}
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def latest_package_id() -> str:
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT id FROM artifactos.publication_package
            WHERE metadata ? 'result_url' OR publication_url IS NOT NULL
            ORDER BY created_at DESC
            LIMIT 1
            """
        )
        row = cur.fetchone()
        if not row:
            raise RuntimeError("no package with result_url found")
        return str(row[0])
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    pid = sys.argv[1] if len(sys.argv) > 1 else latest_package_id()
    result = verify(pid)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result["status"] == "published_confirmed" else 1)
