# DeepSpec Conformance Test Suite

This directory contains a lightweight Python runner for checking reader behavior against the DeepSpec Reader Profile.

## Actual Layout

```text
conformance/
  README.md
  run.py
  fixtures/
    valid-minimal/
    valid-extension-kinds/
```

## Reader CLI Contract

The runner expects your reader command to support:

```bash
your-reader exists <path>       # -> {"exists": true|false}
your-reader project <path>      # -> {"name": "...", "type": "...", "total_nodes": 0}
your-reader tree <path> function
your-reader tree <path> module
your-reader tree <path> view
your-reader find <path> <id>
your-reader decisions <path>
```

## Run

```bash
python protocol/conformance/run.py --reader "your-reader" --level 1
```

## Current Coverage

The current runner checks Level 0, Level 1, and part of Level 2. It does not yet cover all v1.2-draft features such as `data-tree`, semantic bundles, or review-decision levels. Those should be added before claiming full v1.2 conformance.
