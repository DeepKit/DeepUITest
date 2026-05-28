#!/usr/bin/env python3
"""
Generate the complete 508-article mapping table with new prefix-cluster codes.

Reads the mapping table from the MD file, groups by bureau, assigns cluster numbers,
and outputs:
1. A CSV mapping file (legacy_id �?external_code)
2. A JSON mapping file for the import script
"""

import re
import json
import csv
from pathlib import Path
from collections import defaultdict

# Bureau prefix mapping
BUREAU_PREFIX = {
    '金局｜权责割裂局': ('J', 'metal'),
    '木局｜责任蔓生局': ('M', 'wood'),
    '水局｜责任下滑局': ('S', 'water'),
    '火局｜责任引爆局': ('H', 'fire'),
    '土局｜责任沉积局': ('T', 'earth'),
}

# Original 108 drug types from the 药性定义表
DRUG_TYPES_108 = {
    'S001': '识局�?, 'S002': '识局�?, 'S003': '破雾�?, 'S004': '去噪�?,
    'S005': '预警�?, 'S006': '破雾�?, 'S007': '识局�?, 'S008': '识局�?,
    'S009': '破雾�?, 'S010': '预警�?, 'S011': '去噪�?, 'S012': '破雾�?,
    'S013': '固界�?, 'S014': '预警�?, 'S015': '固界�?, 'S016': '去噪�?,
    'S017': '复燃�?, 'S018': '预警�?, 'S019': '固界�?, 'S020': '固界�?,
    'S021': '复燃�?, 'S022': '去噪�?, 'S023': '辨权�?, 'S024': '破雾�?,
    'S025': '识局�?, 'S026': '预警�?, 'S027': '识局�?, 'S028': '去噪�?,
    'S029': '破雾�?, 'S030': '预警�?, 'S031': '复燃�?, 'S032': '破局�?,
    'S033': '去噪�?, 'S034': '破雾�?, 'S035': '预警�?, 'S036': '复燃�?,
    'S037': '识局�?, 'S038': '固界�?, 'S039': '辨权�?, 'S040': '辨权�?,
    'S041': '预警�?, 'S042': '破雾�?, 'S043': '破局�?, 'S044': '去噪�?,
    'S045': '识局�?, 'S046': '辨权�?, 'S047': '固界�?, 'S048': '破局�?,
    'S049': '辨权�?, 'S050': '固界�?, 'S051': '辨权�?, 'S052': '固界�?,
    'S053': '固界�?, 'S054': '辨权�?, 'S055': '止损�?, 'S056': '止损�?,
    'S057': '破局�?, 'S058': '止损�?, 'S059': '辨权�?, 'S060': '止损�?,
    'S061': '破雾�?, 'S062': '固界�?, 'S063': '止损�?, 'S064': '辨权�?,
    'S065': '预警�?, 'S066': '预警�?, 'S067': '破雾�?, 'S068': '破局�?,
    'S069': '预警�?, 'S070': '预警�?, 'S071': '去噪�?, 'S072': '预警�?,
    'S073': '破雾�?, 'S074': '固界�?, 'S075': '识局�?, 'S076': '固界�?,
    'S077': '辨权�?, 'S078': '固界�?, 'S079': '固界�?, 'S080': '破局�?,
    'S081': '破局�?, 'S082': '破雾�?, 'S083': '固界�?, 'S084': '固界�?,
    'S085': '辨权�?, 'S086': '辨权�?, 'S087': '识局�?, 'S088': '止损�?,
    'S089': '破局�?, 'S090': '醒群�?, 'S091': '醒群�?, 'S092': '破局�?,
    'S093': '去噪�?, 'S094': '辨权�?, 'S095': '止损�?, 'S096': '破局�?,
    'S097': '复燃�?, 'S098': '止损�?, 'S099': '辨权�?, 'S100': '预警�?,
    'S101': '破雾�?, 'S102': '破雾�?, 'S103': '固界�?, 'S104': '辨权�?,
    'S105': '固界�?, 'S106': '辨权�?, 'S107': '复燃�?, 'S108': '复燃�?,
}

# Default drug type assignment for new 400 based on bureau
# (writers will refine these)
DEFAULT_DRUG_BY_BUREAU = {
    'metal': '辨权�?,   # 金局 �?权力/规则�?    'wood':  '固界�?,   # 木局 �?边界/身份�?    'water': '破雾�?,   # 水局 �?认知/判断�?    'fire':  '破局�?,   # 火局 �?博弈/冲突�?    'earth': '预警�?,   # 土局 �?风险/沉积�?}


def parse_mapping_table(md_path: str) -> list[dict]:
    """Parse the mapping table from the MD file."""
    entries = []
    with open(md_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find table rows: | 旧编�?| 题名 | 来源 | 主局 | 新编�?| 迁移说明 |
    pattern = r'\|\s*(N\d+|S\d+)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*\|'
    for match in re.finditer(pattern, content):
        legacy_id = match.group(1).strip()
        title = match.group(2).strip()
        source = match.group(3).strip()
        bureau_full = match.group(4).strip()
        old_thousand = int(match.group(5).strip())

        if bureau_full in BUREAU_PREFIX:
            prefix, rfi_type = BUREAU_PREFIX[bureau_full]
        else:
            print(f"WARNING: Unknown bureau '{bureau_full}' for {legacy_id}")
            continue

        entries.append({
            'legacy_id': legacy_id,
            'title': title,
            'source': source,
            'bureau_full': bureau_full,
            'prefix': prefix,
            'rfi_type': rfi_type,
            'old_thousand': old_thousand,
        })

    return entries


def assign_cluster_codes(entries: list[dict]) -> list[dict]:
    """
    Group articles by bureau, assign cluster numbers.
    Every 2 articles share one cluster. First gets B=1, second gets B=5.
    Original 108 (S-prefix) start at cluster 41+.
    """
    # Split into new400 and orig108 within each bureau
    bureau_new = defaultdict(list)
    bureau_orig = defaultdict(list)

    for entry in entries:
        if entry['legacy_id'].startswith('S'):
            bureau_orig[entry['prefix']].append(entry)
        else:
            bureau_new[entry['prefix']].append(entry)

    result = []

    for prefix in ['J', 'M', 'S', 'H', 'T']:
        # Process new 400 articles: clusters 01-40
        new_articles = bureau_new.get(prefix, [])
        # Sort by old_thousand to maintain original order
        new_articles.sort(key=lambda x: x['old_thousand'])

        cluster_num = 1
        for i, entry in enumerate(new_articles):
            if i > 0 and i % 2 == 0:
                cluster_num += 1
            # First in cluster gets B=1 (standard), second gets B=5 (crisis)
            b_val = 1 if i % 2 == 0 else 5
            aa = f"{cluster_num:02d}"
            external_code = f"{prefix}{aa}{b_val}0"
            entry['cluster_id'] = aa
            entry['position_type'] = b_val
            entry['variant'] = 0
            entry['external_code'] = external_code
            result.append(entry)

        # Process original 108 articles: clusters 41+
        orig_articles = bureau_orig.get(prefix, [])
        orig_articles.sort(key=lambda x: int(x['legacy_id'][1:]))

        orig_cluster_start = 41
        cluster_num = orig_cluster_start
        for i, entry in enumerate(orig_articles):
            if i > 0 and i % 2 == 0:
                cluster_num += 1
            b_val = 1 if i % 2 == 0 else 5
            aa = f"{cluster_num:02d}"
            external_code = f"{prefix}{aa}{b_val}0"
            entry['cluster_id'] = aa
            entry['position_type'] = b_val
            entry['variant'] = 0
            entry['external_code'] = external_code
            result.append(entry)

    return result


def assign_drug_types(entries: list[dict]) -> list[dict]:
    """Assign drug types. Original 108 use the defined table; new 400 get defaults."""
    for entry in entries:
        lid = entry['legacy_id']
        if lid in DRUG_TYPES_108:
            entry['drug_type'] = DRUG_TYPES_108[lid]
        else:
            entry['drug_type'] = DEFAULT_DRUG_BY_BUREAU.get(entry['rfi_type'], '识局�?)
    return entries


def main():
    # Paths
    mapping_md = r"D:\_Progs\.DeepStory\《思维越狱》\LMM优化\思维越狱-508旧新编号映射总表-初版.md"
    output_dir = Path(r"D:\_Progs\02Business\BetterCiv\goodmem.cn\backend")
    docs_dir = Path(r"D:\_Progs\02Business\BetterCiv\goodmem.cn\docs")

    # Parse
    print("Parsing mapping table...")
    entries = parse_mapping_table(mapping_md)
    print(f"  Found {len(entries)} entries")

    # Assign clusters
    print("Assigning cluster codes...")
    entries = assign_cluster_codes(entries)

    # Assign drug types
    print("Assigning drug types...")
    entries = assign_drug_types(entries)

    # Sort by external_code
    entries.sort(key=lambda x: x['external_code'])

    # Stats
    bureau_counts = defaultdict(int)
    bureau_clusters = defaultdict(set)
    for e in entries:
        bureau_counts[e['prefix']] += 1
        bureau_clusters[e['prefix']].add(e['cluster_id'])

    print("\n=== Distribution ===")
    for p in ['J', 'M', 'S', 'H', 'T']:
        print(f"  {p}: {bureau_counts[p]} articles in {len(bureau_clusters[p])} clusters")
    print(f"  Total: {sum(bureau_counts.values())} articles")

    # Output CSV
    csv_path = docs_dir / "508映射�?前缀簇位�?csv"
    with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'legacy_id', 'external_code', 'title', 'rfi_type', 'prefix',
            'cluster_id', 'position_type', 'variant', 'drug_type', 'old_thousand'
        ])
        writer.writeheader()
        for e in entries:
            writer.writerow({k: e.get(k, '') for k in writer.fieldnames})
    print(f"\nCSV written: {csv_path}")

    # Output JSON (for import script)
    json_path = output_dir / "article_mapping.json"
    json_data = []
    for e in entries:
        json_data.append({
            'legacy_id': e['legacy_id'],
            'external_code': e['external_code'],
            'title': e['title'],
            'rfi_type': e['rfi_type'],
            'prefix': e['prefix'],
            'cluster_id': e['cluster_id'],
            'position_type': e['position_type'],
            'variant': e['variant'],
            'drug_type': e['drug_type'],
        })
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(json_data, f, ensure_ascii=False, indent=2)
    print(f"JSON written: {json_path}")

    # Print sample
    print("\n=== Samples ===")
    samples = ['N109', 'N229', 'N349', 'N149', 'N389', 'S001', 'S045', 'S099']
    for sid in samples:
        match = next((e for e in entries if e['legacy_id'] == sid), None)
        if match:
            print(f"  {sid:6s} �?{match['external_code']:6s}  {match['title']:<12s}  {match['rfi_type']:<6s}  {match['drug_type']}")


if __name__ == '__main__':
    main()
