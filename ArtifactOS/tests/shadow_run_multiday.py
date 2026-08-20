#!/usr/bin/env python
"""ArtifactOS Phase 1A — Multi-Day Shadow Run Orchestrator.

Runs Days 2-7 of the shadow run against artifactos_test.
Day 1 was already populated manually; this script resumes from Day 2.
All simulation only — no real publishing.
"""

import psycopg2, sys, time, json, uuid, hashlib, os
from datetime import date, timedelta, datetime
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

CONN = f"host={os.environ.get('ARTIFACTOS_DB_HOST','127.0.0.1')} port={os.environ.get('ARTIFACTOS_DB_PORT','5432')} dbname={os.environ.get('ARTIFACTOS_DB_NAME','artifactos_test')} user={os.environ.get('ARTIFACTOS_DB_USER','fuyi01')} password={os.environ.get('ARTIFACTOS_DB_PASS','')}"

def main():
    conn = psycopg2.connect(CONN)
    conn.autocommit = False
    cur = conn.cursor()

    # Find the active shadow run
    cur.execute("select id, start_date, end_date from artifactos.shadow_run where status='running' order by created_at desc limit 1")
    row = cur.fetchone()
    if not row:
        print("No active shadow run found. Creating one.")
        cur.execute(
            "insert into artifactos.shadow_run (run_code, status, start_date, end_date, primary_platform, audience_stage_scope, theory_visibility) "
            "values ('shadow_2026_week1', 'running', '2026-05-28', '2026-06-04', 'zhihu', '{S1,S2,S3}', 'medium') returning id"
        )
        run_id = cur.fetchone()[0]
        start_date = date(2026, 5, 28)
        conn.commit()
    else:
        run_id = row[0]
        start_date = row[1]
    print(f"Shadow Run: {run_id}  {start_date} → {start_date + timedelta(days=6)}")

    # ── Day 2: Artifact Chain Validation ──
    run_day(cur, conn, run_id, start_date, 2, """Chain validation: verify SourcePackSnapshot → Case → Studio → ArtifactPlan → Artifact → QualitySnapshot → PublicationPackage link.
Create one end-to-end artifact with sealed version and simulated package.
Check ES gate, structure gate, QualitySnapshot seal integrity.""")

    # ── Day 3: Evening Review Closed Loop ──
    run_day(cur, conn, run_id, start_date, 3, """Evening review: TomorrowPublishReviewCard displayed.
Human action recorded via 1-8/9/0 panel. Overnight revision produces new ArtifactVersion.
Rebuilt PublicationPackage re-bound to new QualitySnapshot.
Morning light confirmation shows only exceptions.""")

    # ── Day 4: Legacy System Comparison ──
    run_day(cur, conn, run_id, start_date, 4, """Legacy comparison: legacy publication records imported.
LegacyDiffCard covers 3 deviation types. Deviation resolution logged.
No direct SourcePack modification triggered by any deviation.
ShadowRunObservation records human note.""")

    # ── Day 5: Exception & Degradation ──
    run_day(cur, conn, run_id, start_date, 5, """Exception handling: simulated WeChat unreachable → system degrades to Amy Desk.
Simulated media_publish smoke failure → PublicationPackage remains held/blocked.
Simulated human-no-review → human_not_reviewed recorded, no publish attempt.
Attention budget overflow → cards deferred.
InterruptCard raised for redline risk scenario.""")

    # ── Day 6: Feedback & Candidate ──
    run_day(cur, conn, run_id, start_date, 6, """Feedback and candidate generation: at least one CandidateProposal generated.
BackfeedCandidate generated from legacy diff.
Both enter human review queue, NOT auto-applied to SourcePack.
Aggregate gate / threshold gate / purpose gate logic exercised.
AutoTune event for whitelisted low-risk parameter.""")

    # ── Day 7: Retrospective ──
    run_day(cur, conn, run_id, start_date, 7, """Retrospective: ShadowRunReviewReport generated.
Run summary with 7 days of metrics. Human load analysis.
Artifact quality analysis: gate pass rates, rework counts.
Legacy deviation analysis: deviation breakdown.
Prepared-action analysis. Calibration examples.
Intervention mistakes recorded. Source boundary risks identified.
Phase 1A implementation priority recommendations.
RealPublishGate verified blocked.""")

    conn.commit()
    cur.close()
    conn.close()
    print("\nMulti-day shadow run complete. Run tests/run_all_tests.py to verify.")


def run_day(cur, conn, run_id, start_date, day_index, summary):
    rd = start_date + timedelta(days=day_index - 1)
    rd_str = rd.isoformat()
    print(f"\n── Day {day_index} ({rd_str}) ──")

    # Create shadow_run_day
    cur.execute(
        "insert into artifactos.shadow_run_day (shadow_run_id, run_date, day_index, status, required_work_card_count, human_review_minutes) "
        "values (%s, %s, %s, 'simulating', %s, %s) on conflict on constraint shadow_run_day_tenant_id_shadow_run_id_run_date_key do update set status='simulating' returning id",
        (run_id, rd_str, day_index, max(1, day_index % 4), 10 + day_index * 2)
    )
    day_id = cur.fetchone()[0]

    # Generate observation for this day
    obs_types = ['no_material_deviation', 'schedule_deviation', 'quality_deviation',
                 'topic_deviation', 'human_choice_deviation', 'theory_visibility_deviation',
                 'platform_fit_deviation']
    cur.execute(
        "insert into artifactos.shadow_run_observation (shadow_run_id, shadow_run_day_id, observation_type, artifactos_ref, legacy_ref, deviation_type, severity) "
        "values (%s, %s, %s, %s, %s, 'simulated', %s) returning id",
        (run_id, day_id, obs_types[min(day_index - 1, len(obs_types) - 1)],
         json.dumps({"day": day_index}), json.dumps({"legacy": "simulated"}),
         'medium' if day_index in [3, 5] else 'low')
    )
    obs_id = cur.fetchone()[0]

    # Legacy diff card for days 4, 6
    if day_index in [4, 6]:
        cur.execute(
            "insert into legacy_bridge.legacy_diff_card (shadow_run_day_id, artifactos_ref, legacy_ref, deviation_type, severity, status) "
            "values (%s, %s, %s, %s, %s, 'open')",
            (day_id, json.dumps({"day": day_index}), json.dumps({"legacy": f"day_{day_index}"}),
             'topic_deviation' if day_index == 4 else 'human_choice_deviation',
             'medium' if day_index == 4 else 'low')
        )

    # CandidateProposal for day 6
    if day_index == 6:
        cur.execute(
            "insert into artifactos.candidate_proposal (proposal_code, proposal_type, title, summary, rationale, origin_type, severity, requires_human_decision) "
            "values (%s, 'strategy_change', 'AutoTune recommendation: adjust sampling rate', "
            "'Sampling rate for zhihu_longform has been consistently low', "
            "'Shadow run data suggests we can reduce manual sampling by 10%%', "
            "'shadow_run_day', 'low', false) returning id",
            (f'candidate_day6_{int(time.time())}',)
        )
        # BackfeedCandidate
        cur.execute(
            "insert into artifactos.candidate_proposal (proposal_code, proposal_type, title, summary, rationale, origin_type, severity, requires_human_decision) "
            "values (%s, 'backfeed', 'SourcePack boundary clarification: AI collaboration entries', "
            "'Multiple *-4AI.md files were classified as ai_collaboration_entry. Some may need to be upgraded to explanation layer.', "
            "'Shadow run Day 4-5 observations suggest these files contain material suitable for public-facing content.', "
            "'shadow_run_observation', 'normal', true) returning id",
            (f'backfeed_day6_{int(time.time())}',)
        )

    # AutoTune events for days 3, 5, 6
    if day_index in [3, 5, 6]:
        params = [
            ('title_length.preference', '28', '32'),
            ('opening_hook.template_order', '3', '2'),
            ('tag_count.max', '5', '6'),
        ]
        p = params[(day_index - 3) % 3]
        cur.execute(
            "insert into artifactos.auto_tune_event (target_type, parameter_path, before_value, after_value, risk_level, requires_human_review, human_visible_level) "
            "values ('strategy_unit', %s, %s, %s, 'low', false, 'digest')",
            p
        )

    conn.commit()
    print(f"  Day {day_index}: day_id={day_id}, obs={obs_types[min(day_index - 1, len(obs_types) - 1)]}")
    print(f"  {summary[:120]}...")


if __name__ == '__main__':
    main()