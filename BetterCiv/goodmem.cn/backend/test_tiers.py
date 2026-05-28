import os
import asyncio
import asyncpg
import sys
import io
from dotenv import load_dotenv
from typing import List

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# Mock values from main.py
TIER_AMOUNTS = {
    "emergency": 29900,
    "system": 39900,
    "archive": 99900,
}

async def get_user_allowed_article_ids(conn: asyncpg.Connection, tier: str, rfi_type: str = "water") -> List[int]:
    """Replicated logic from main.py for verification"""
    novel_key = "mindbreak"
    
    if tier == "emergency":
        proof_codes = ["M0410", "H3110", "J4110"]
        proof_rows = await conn.fetch("SELECT id FROM articles WHERE external_code = ANY($1)", proof_codes)
        ids = [r["id"] for r in proof_rows]
        if rfi_type:
            main_rows = await conn.fetch(
                "SELECT id FROM articles WHERE rfi_type = $1 AND external_code NOT IN ('M0410', 'H3110', 'J4110') ORDER BY id ASC LIMIT 2",
                rfi_type
            )
            ids.extend([r["id"] for r in main_rows])
        return list(set(ids))

    elif tier == "system":
        rows = await conn.fetch(
            "SELECT id FROM articles WHERE novel_key = $1 ORDER BY (CASE WHEN rfi_type = $2 THEN 0 ELSE 1 END), id ASC LIMIT 108",
            novel_key, rfi_type
        )
        return [r["id"] for r in rows]

    elif tier == "archive":
        final_ids = []
        univ_rows = await conn.fetch(
            "SELECT id FROM articles WHERE novel_key = $1 AND (rfi_type IS NULL OR cluster_id IN ('00', '99')) ORDER BY id ASC LIMIT 36",
            novel_key
        )
        final_ids.extend([r["id"] for r in univ_rows])
        if rfi_type:
            main_rows = await conn.fetch(
                "SELECT id FROM articles WHERE novel_key = $1 AND rfi_type = $2 ORDER BY id ASC LIMIT 80",
                novel_key, rfi_type
            )
            final_ids.extend([r["id"] for r in main_rows])
        
        other_types = ["water", "wood", "fire", "earth", "metal"]
        if rfi_type in other_types: other_types.remove(rfi_type)
        for ot in other_types:
            ot_rows = await conn.fetch(
                "SELECT id FROM articles WHERE novel_key = $1 AND rfi_type = $2 ORDER BY id ASC LIMIT 30",
                novel_key, ot
            )
            final_ids.extend([r["id"] for r in ot_rows])
        return list(set(final_ids))
    return []

async def test_tiers():
    load_dotenv()
    conn = await asyncpg.connect(os.getenv("DATABASE_URL"))
    
    print("=== 三档权限 Mock 测试开�?===")
    
    # 1. Emergency (299)
    ids_299 = await get_user_allowed_article_ids(conn, "emergency", "water")
    print(f"[¥299 识局·急情] 目标 5 �?| 实际: {len(ids_299)} �?)
    
    # 2. System (399)
    ids_399 = await get_user_allowed_article_ids(conn, "system", "water")
    print(f"[¥399 识局·处方系统] 目标 108 �?| 实际: {len(ids_399)} �?)

    # 3. Archive (999)
    ids_999 = await get_user_allowed_article_ids(conn, "archive", "water")
    print(f"[¥999 识局·全档基站] 规格 236 �?| 当前库实�? {len(ids_999)} �?)

    await conn.close()
    print("=== 测试结束 ===")

if __name__ == "__main__":
    asyncio.run(test_tiers())
