# DeepFrames Remotion Worker

## Overview

Secondary rendering backend for DeepFrames. Consumes Video IR JSON produced by the Delphi VideoCompiler, renders React compositions via Remotion, and outputs MP4 files.

## Architecture

```
Delphi DeepFrames (main program)
  → writes request.json to worker work_dir/
  → launches: npx ts-node src/index.ts <work_dir>
  → monitors progress.json
  → reads result.json
  → registers assets in DB2
```

Worker reads Video IR from `request.json`'s `input_manifest` path.
Worker does NOT access DB1/DB2 or read shot_document directly.

## File Contract

| File | Producer | Consumer | Contents |
|------|----------|----------|----------|
| `request.json` | Delphi host | Worker | Task params, input manifest path |
| `progress.json` | Worker | Delphi host | Heartbeat, progress %, current step |
| `result.json` | Worker | Delphi host | Output files, metrics, success/fail |
| `cancel` | Delphi host | Worker | Empty file = cancel signal |

## Requirements

- Node.js 18+
- Remotion license (commercial use requires Remotion License)
  - Deadline: Phase 5 end / Phase 7 start (per docs/10.dev-roadmap)
- npm install before first run

## Usage

```bash
npm install
npx ts-node src/index.ts /path/to/work_dir
```

## Composition

`src/Composition.tsx` — Renders VideoIRScene[] as Remotion <Sequence> elements:
- Scene background: gradient placeholder + prompt text
- Scene subtitle: centered text with fade in/out
- Transitions: fade, crossfade, cut