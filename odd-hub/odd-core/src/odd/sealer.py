"""
封存管理�?- 计算哈希链并生成封存记录
"""

import uuid
import json
import hashlib
from datetime import datetime
from pathlib import Path


class SealManager:

    def _hash(self, content: str) -> str:
        return hashlib.sha256(content.encode("utf-8")).hexdigest()

    def seal(self, contract: dict, code: str, verification: dict, seal_dir: Path) -> dict:
        seal_dir.mkdir(parents=True, exist_ok=True)
        seal_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()

        contract_str = json.dumps(contract, ensure_ascii=False, sort_keys=True)
        verification_str = json.dumps(verification, ensure_ascii=False, sort_keys=True)

        hashes = {
            "contract": self._hash(contract_str),
            "code": self._hash(code),
            "verification": self._hash(verification_str),
        }
        integrity = self._hash(":".join(hashes.values()))

        record = {
            "seal_id": seal_id,
            "timestamp": timestamp,
            "odd_version": "0.1.0",
            "hashes": hashes,
            "integrity": integrity,
            "artifacts": {
                "contract": contract,
                "code": code,
                "verification": verification,
            },
        }

        seal_file = seal_dir / f"seal_{seal_id[:8]}.json"
        seal_file.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")

        return {"seal_id": seal_id, "file": str(seal_file), "integrity": integrity}
