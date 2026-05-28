# Governance Integration — Bug Fixes

Issues found and resolved during the governance integration work. Each entry records the symptom, root cause, fix, and files touched.

---

## BF-001 — Duplicate `TGovernanceMode` type declaration

**Severity:** Medium — compile-warning risk, conceptual confusion.

**Symptom:** Two units (`DeepBase.Governance.Lifecycle` and `DeepBase.Governance.ObserveGateResolver`) both declared a public type named `TGovernanceMode`, with different ordinal sets:
- `Lifecycle`: `(gmObserve, gmEnforce, gmOff)` — 3 values
- `ObserveGateResolver`: `(gmObserve, gmEnforce)` — 2 values

Any unit that `uses` both would need full qualification, and they were not interchangeable across the boundary.

**Root cause:** Two independent refactors introduced the enum without awareness of each other.

**Fix:** Removed the duplicate enum from `ObserveGateResolver`. The decorator now takes a `TObserveModeProvider = reference to function: Boolean` callback (True = observe, False = enforce). Mode semantics remain owned by `Lifecycle` as the 3-value enum. The Lifecycle wires a closure that reads `FMode = gmObserve` and returns Boolean, decoupling the decorator from the enum entirely.

**Files:**
- `DeepBase/Governance/DeepBase.Governance.ObserveGateResolver.pas` — removed `TGovernanceMode`, added `TObserveModeProvider`.
- `DeepBase/Governance/DeepBase.Governance.Lifecycle.pas` — added the closure at Initialize.

---

## BF-002 — `TSteeringExporter.Create` parameter mismatch

**Severity:** Critical — build breakage.

**Symptom:**
```
DeepBase.Governance.Lifecycle.pas(248): error E2035: Not enough actual parameters
```

First Assayer build failed at the Lifecycle compile step.

**Root cause:** The existing `TSteeringExporter.Create` signature is:

```pascal
constructor Create(AKeyResolver: TKeyResolver; APurposeSet: TPurposeSet;
  const AOutputDir: string);
```

Earlier revision of `Lifecycle.Initialize` only passed `FKeyResolver`. Two required params were missing.

**Fix:** Pass all three required args:
```pascal
FSteeringExporter := TSteeringExporter.Create(
  FKeyResolver,
  FPurposeSet,
  TPath.Combine(ExtractFilePath(ParamStr(0)), '.kiro\steering'));
```

Also replaced the inline `ForceDirectories(ExtractFilePath(LSteeringPath))` + explicit path with `ForceDirectories(FSteeringExporter.OutputDir)` + `FSteeringExporter.ExportToFile('governance-model.md')` so the exporter-owned OutputDir stays the single source of truth.

**Files:** `DeepBase/Governance/DeepBase.Governance.Lifecycle.pas`.

---

## BF-003 — Missing uses in `Assayer.Governance.Registration`

**Severity:** Critical — build breakage.

**Symptom:**
```
Assayer.Governance.Registration.pas(58): error E2003: Undeclared identifier: 'TGateResolver'
Assayer.Governance.Registration.pas(59): error E2003: Undeclared identifier: 'TOCGSRuntime'
Assayer.Governance.Registration.pas(95): error E2250: There is no overloaded version of 'RegisterGovernance' that can be called with these arguments
```

**Root cause:** `TGovernanceConfigSetupProc` is declared in `DeepBase.Governance.Lifecycle`, but the anonymous method passed to `RegisterGovernance` uses `TGateResolver` and `TOCGSRuntime` as parameter types. Those types live in `DeepBase.Governance.GateResolver` and `DeepBase.Governance.Runtime` respectively, and must be in scope at the call site for overload resolution to work.

**Fix:** Added the two missing units to the `uses` clause of `Assayer.Governance.Registration.pas`:
```pascal
uses
  ...
  DeepBase.Governance.GateResolver,
  DeepBase.Governance.Runtime,
  DeepBase.Governance.ConfigRegistrar,
  DeepBase.Governance.Lifecycle,
  DeepBase.Governance.Registration;
```

**Files:** `Assayer/src/Assayer.Governance.Registration.pas`.

---

## BF-004 — Latent double-free risk for `TEvidenceRecorder` in Shutdown

**Severity:** Low — defensive; same-pattern existing code has the same shape, but my new additions pass `TEvidenceRecorder` (a `TInterfacedObject` descendant) into `TOCGSRuntime` as an `IEvidenceRecorder` parameter. That increments the ref count to 1. At Shutdown, `FreeAndNil(FRuntime)` releases the interface (ref → 0), triggering `Destroy`. A subsequent `FreeAndNil(FEvidenceRecorder)` on the now-dangling raw pointer would AV.

**Root cause:** TInterfacedObject-style ref counting combined with dual ownership patterns (raw object pointer + interface reference held by consumer).

**Fix:** Added a parallel interface field `FEvidenceRecorderIntf: IEvidenceRecorder`, pinned the object alive via that reference, and at Shutdown released the interface with `FEvidenceRecorderIntf := nil` and simply cleared the raw pointer with `FEvidenceRecorder := nil` (no Free).

This doesn't touch the pre-existing (same-shape) pattern around `FGateResolver` etc. — that pattern already works in practice because Assayer/DeepShine don't exercise a full Governance Shutdown during normal process exit. The defensive fix is scoped to the fields I introduced.

**Files:** `DeepBase/Governance/DeepBase.Governance.Lifecycle.pas`.

---

## Non-bugs worth recording

### Spec drift vs. task text

The spec tasks.md (written against an older design) referenced `RegisterGovernance(AConfigDir)` — a path-string overload that never shipped. The actually-implemented legacy overload is `RegisterGovernance(AMode, ASetupProc)` and the new overload is `RegisterGovernance(AMode, AConfigDB, ASetupProc)`. No code change needed, but future readers should treat `AConfigDir` as a historical reference, not a target signature.

### `DeepBaseGovernance.dpk` missing new units

Not strictly a bug (the package only matters if you consume the dpk at design-time), but I added the four new units to the `contains` clause for completeness:
- `DeepBase.Governance.ObserveGateResolver`
- `DeepBase.Governance.ConfigRegistrar`
- `DeepBase.Governance.Lifecycle`
- `DeepBase.Governance.Registration`

**File:** `DeepBase/DeepBaseGovernance.dpk`.


---

## BF-005 — `Lifecycle.Shutdown` double-free (EInvalidPointer at runtime)

**Severity:** High — crashes any host that actually calls `ShutdownGovernance`. The GUI apps don't exercise this path on normal exit so it stayed hidden until the CLI smoke test ran through Stage 7.

**Symptom:**
```
[smoke] UNHANDLED EXCEPTION: EInvalidPointer: Invalid pointer operation
[run] Exit code: 2
```
Raised inside `FreeAndNil(FExecutor)` (or the next `FreeAndNil` on a TInterfacedObject field) during Shutdown.

**Root cause:** `TOCGSRuntime.Create` takes interface parameters (`IActionGrid`, `IGateResolver`, `IActionExecutor`, `IDueChecker`, `IProjectionResolver`, `IFeedbackResolver`, `IEvidenceRecorder`, `IKeyResolver`). All the concrete classes are `TInterfacedObject` descendants, so assigning them to those parameters increments refcount 0 → 1. When `FreeAndNil(FRuntime)` runs, the Runtime destructor releases each interface field, refcount goes 1 → 0, and each concrete object is destroyed via the interface `_Release` path. The subsequent `FreeAndNil(FExecutor)` / `FreeAndNil(FDueChecker)` / etc. calls then tried to Free already-freed memory → AV.

**Fix:** After `FreeAndNil(FRuntime)`, clear the raw pointers with plain `nil` assignment (no Free). The objects are already gone; we just need to drop our stale references. Plain `TObject` fields (`FSteeringExporter`, `FConfigRegistrar`, `FPurposeSet`) continue to use `FreeAndNil` as usual.

**Files:** `DeepBase/Governance/DeepBase.Governance.Lifecycle.pas`.

---

## BF-006 — Steering file path lives next to exe

**Severity:** Low — documentation / test-harness issue, not a functional bug.

**Symptom:** First smoke-test run failed the "Steering file exists" check because the test looked for `governance-model.md` under the test's scratch dir, but Lifecycle writes to `ExtractFilePath(ParamStr(0)) + '.kiro\steering\'`.

**Root cause:** The Lifecycle export path is exe-relative by design (so each downstream app generates its own steering file for its AI tooling). The test had a wrong expectation.

**Fix:** Smoke test now reads `LSteeringPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '.kiro\steering\governance-model.md')`. For Assayer_FMX / DeepShineStudio this means `.kiro/steering/` sits next to each app's exe.

**Files:** `Assayer/tests/GovernanceSmoke.dpr`.

---

## BF-007 — `EnterGate` on a route-less / action-less gate never writes evidence

**Severity:** Medium — contract gap rather than a crash. Calling `EnterGate` on a gate that has *no conditions* and *no route rules* returns `arsFail` with "No action resolved" and writes no evidence. Callers might reasonably expect every EnterGate call to leave an audit trail.

**Symptom:** Smoke test Stage 5 saw evidence count stay at 0 after `EnterGate('deepllm.switch_model', ...)`.

**Root cause:** `TOCGSRuntime.EnterGate` flow:
1. If `Resolve` returns non-open → `LogBlocked` + return blocked.
2. Otherwise try route resolution; if that fails → `TActionResult.Fail(..., 'No action resolved...')`, no `LogAction` call.

The only evidence-writing paths are (a) a blocked resolution in enforce mode, (b) the observe-mode decorator turning a would-block into an open, or (c) `TActionExecutor.Execute` (which `LogAction`s the result). A gate with no conditions AND no routes / AND no default action never lands on any of those.

**Fix applied (in the test):** Smoke test now calls `GovernanceLifecycle.EvidenceRecorder.LogBlocked` directly to exercise the recorder→SQLite pipeline, and separately calls `EnterGate` to verify observe-mode doesn't block. This also let us validate **Property 8 (Evidence Sanitisation)** — the test passes a `api_key` field and asserts `input_summary` never contains its value (checked via `LIKE '%sk-should-not-appear%'`).

**Follow-up for the framework (filed in tasks.md):** Consider having `EnterGate` always `LogAction(arsFail, 'No action resolved')` for no-route gates so the contract is "every EnterGate leaves a trace". Not changing now because the existing behaviour is relied on by the EvidenceRecorder tests; downstream callers can `LogAction` directly if they need that.

**Files:** `Assayer/tests/GovernanceSmoke.dpr`.


---

## BF-008 — `SetMode` didn't update live runtime mode

**Severity:** Medium — silent contract gap. The mode provider closure read `FMode` only, so calls to `GovernanceRegistrar.SetMode('enforce')` persisted to DB but the active resolver kept behaving as observe until a full Shutdown/Register cycle.

**Symptom:** Smoke test Stage 4d initially could not toggle from observe to enforce at runtime; the mode was pinned at Initialize time.

**Fix:** Added `TGovernanceLifecycle.SwitchMode(ANewMode: TGovernanceMode)`. It updates `FMode` (what the ObserveGateResolver's mode-provider closure returns) and also writes through to `governance_config` so the change survives restart. Refuses `gmOff` — callers must go through Shutdown/Register to fully disable.

**Files:** `DeepBase/Governance/DeepBase.Governance.Lifecycle.pas`.
