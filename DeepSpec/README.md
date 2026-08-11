# DeepSpec

DeepSpec is an engineering project for building traceable, reviewable, and correctable specifications for AI coding agents.

It does not try to replace coding agents. It gives humans and agents a shared specification workspace so that requirements can be checked before they become code.

```text
Project materials / code / discussions
        -> DeepSpec CTF
        -> .deepspec/ structured facts
        -> human review decisions
        -> SpecSnapshot / ContractCandidate
        -> agent execution / ODD verification
```

## Positioning

DeepSpec is the project. CTF is the method inside it.

```text
DeepSpec: Traceable Specifications for AI Coding Agents
CTF: Constructive Traceable Fallibilist specification method
ODD: downstream output-driven development and verification
```

Use this distinction when writing public material:

- Public brand: DeepSpec
- Method core: CTF
- Protocol workspace: `.deepspec/`
- Downstream consumer: coding agents, ODD pipelines, orchestration systems such as Symphony-style issue workflows

## Core Idea

AI coding does not only need more tasks running. It needs specifications that can be traced, reviewed, invalidated, and repaired.

DeepSpec turns messy project material into four coordinated projections:

```text
function-tree  what the system should do
module-tree    where the behavior lives
view-tree      what users see and operate
data-tree      what data exists, persists, moves, and migrates
```

Each node can carry evidence, confidence, generation state, review state, related nodes, and human decisions.

## Repository Map

```text
README.md                         public entry
SPEC.md                           current DeepSpec specification overview
docs/CTF.md                       engineering explanation of CTF
docs/DeepSpec-CTF方法论-v1.md      source method note, Chinese
protocol/                         machine-readable protocol package
protocol/schemas/                 JSON Schema files
protocol/examples/                seed .deepspec projects
protocol/conformance/             reader conformance checks
src/                              Delphi/VCL desktop implementation
tasks.md                          implementation and protocol work queue
```

## Current Status

The Delphi desktop implementation exists, but the public protocol is being stabilized. Treat `SPEC.md`, `protocol/README.md`, and `protocol/schemas/` as the current engineering baseline.

The protocol is currently `v1.2-draft`:

- Four projections are the target model.
- `data-tree` is part of the default model.
- `gen_status` and `review_status` are the preferred node states.
- Legacy `status` remains readable for older examples and implementation code.

## Quick Start for Readers

Use the seed projects under `protocol/examples/` to inspect `.deepspec/` directories.

```bash
python protocol/conformance/run.py --reader "your-reader" --level 1
```

The current repository does not yet publish `npx deepspec-*` commands. CLI commands are tracked in `tasks.md` as future work.

## Desktop App (Delphi)

### Prerequisites

- Delphi 13.1 (BDS 37.0) — the self-hosted build scripts default to `d:\Program Files (x86)\Embarcadero\Studio\37.0` and `D:\_Progs\02Business\DeepBase` (override via `BDS` / `DEEPBASE_HOME` env vars).
- Microsoft Edge WebView2 Runtime (for the HTML review pages in the main view).
- `root.txt` next to the EXE with the DeepBase project root as its first line (DeepBase DB1/ConfigDB locator).

### Build

```bat
_build.bat               :: main program -> bin\DeepSpec.exe
cd tests && _build_tests.bat && DeepSpec.Tests.exe   :: 113 unit tests
cd cli && _build_cli.bat :: headless CLI -> cli\bin\DeepSpec.CLI.exe
```

### First Run

1. Launch `bin\DeepSpec.exe` — the UI follows the Windows display language (zh-CN/zh-TW/en-US).
2. Menu **Tools → Setup LLM (ModelScope)** — enter a ModelScope API key once (stored via DeepBase).
3. In the directory tree pick a project folder, click **Visualize** to scan.
4. The dashboard (index.html) opens in the main view; recent projects and window layout persist across restarts (DB1-backed MRU/layout).

### CLI

```bat
DeepSpec.CLI init <dir>      :: create .deepspec structure
DeepSpec.CLI scan <dir>      :: scan + build trees + render + prompts
DeepSpec.CLI generate <dir>  :: export the prompt pack (LLM call runs in the GUI)
DeepSpec.CLI validate <dir>  :: validate trees/issues YAML (exit 1 on errors)
DeepSpec.CLI render <dir>    :: re-render HTML from YAML on disk
```

## Why It Matters

Symphony-style orchestration can keep agents working. DeepSpec focuses on a different layer: making the specification an agent can work from trustworthy enough to review, repair, and hand off.

```text
Symphony increases agent throughput.
DeepSpec improves specification trust.
CTF supplies the review discipline.
ODD verifies accepted outputs.
```
