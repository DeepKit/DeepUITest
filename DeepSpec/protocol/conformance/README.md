# DeepSpec Conformance Test Suite

Automated tests to verify a reader implementation meets the DeepSpec Reader Profile.

## Structure

```
conformance/
├── level-0/          Tests for Scanner Reader
├── level-1/          Tests for Tree Reader
├── level-2/          Tests for Full Reader
├── fixtures/         Test .deepspec directories
└── run.sh            Test runner (calls your reader)
```

## How to use

1. Implement a CLI wrapper for your reader that outputs JSON:

```bash
your-reader project-info <path>    → { "name": "...", "type": "..." }
your-reader tree <path> function   → { "nodes": [...] }
your-reader find-node <path> <id>  → { "id": "...", "title": "..." } | null
```

2. Run conformance tests:

```bash
./run.sh --reader "your-reader" --level 1
```

3. All tests pass → you can claim "DeepSpec Reader Level 1 compatible".

## Test Categories

### Level 0

- `t001_project_exists`: Can detect .deepspec presence
- `t002_project_info`: Can read project name, type, scan_time
- `t003_summary`: Can read summary counters
- `t004_missing_graceful`: Returns error (not crash) for missing project-spec

### Level 1

- `t101_function_tree`: Can load function tree nodes
- `t102_module_tree`: Can load module tree nodes
- `t103_view_tree`: Can load view tree (including empty)
- `t104_hierarchy`: Correctly reconstructs parent-child from parent_id
- `t105_defaults`: Applies defaults for missing optional fields
- `t106_extension_kind`: Handles x_ prefix kinds without error
- `t107_all_nodes`: Can aggregate nodes across trees
- `t108_find_by_id`: Can find specific node by ID

### Level 2

- `t201_relations`: Can load and traverse relations
- `t202_evidence`: Can load evidence and resolve ref_ids
- `t203_issues`: Can load issues
- `t204_decisions`: Can load decisions
- `t205_accepted_priority`: Accepted decisions override candidates
- `t206_ai_instructions`: Can extract ai_instruction strings
- `t207_stale_evidence`: Can detect is_stale=true evidence
