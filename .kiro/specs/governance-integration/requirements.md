# Requirements Document

## Introduction

Integration of the OCGS (Ordered Capability Governance System) Governance module from DeepBase into the Assayer (FMX) and DeepShine (VCL) downstream projects. The integration provides gate-based enforcement for high-risk operations, evidence recording, and AI steering file export. All governance configuration is stored in ConfigDB (SQLite) — no JSON/INI/YAML config files are permitted in downstream projects.

## Glossary

- **OCGS_Runtime**: The central coordinator (`TOCGSRuntime`) that processes gate entry requests via `EnterGate`
- **Gate**: An access control point (`TAccessGate`) that governs a specific operation, identified by a key string
- **GateState**: The resolved state of a gate: Open, Closed, Disabled, Blocked, Locked, Frozen, or Conflict
- **RiskLevel**: Classification of operation risk: L0 (none), L1 (low), L2 (medium), L3 (high)
- **RunMode**: Execution mode for gate entry: Preview, DryRun, or Commit
- **Evidence**: A recorded audit entry (`TEvidenceEntry`) capturing who did what, when, and the outcome
- **ConfigDB**: The SQLite database used by DeepBase for all runtime configuration (governance_* tables)
- **SteeringExporter**: Component (`TSteeringExporter`) that generates `.kiro/steering/governance-model.md`
- **LegacyWrap**: Bridge (`TLegacyWrapBridge`) that wraps existing procedures into governance-aware actions
- **Observe_Mode**: Governance mode where gates record evidence but never block operations
- **Enforce_Mode**: Governance mode where gates actively block operations when conditions are not met
- **CircuitBreaker**: Existing resilience component in DeepShine (`TCircuitBreaker`) that tracks failure thresholds
- **Registration_Unit**: The `DeepBase.Governance.Registration` unit providing `RegisterGovernance` entry point
- **Governance_Lifecycle**: The `TGovernanceLifecycle` singleton managing Configure → Initialize → Start → Shutdown

## Requirements

### Requirement 1: ConfigDB-Based Governance Registration

**User Story:** As a downstream project developer, I want governance configuration loaded from ConfigDB instead of JSON files, so that the "no external config files" rule is maintained.

#### Acceptance Criteria

1. WHEN `RegisterGovernance` is called without a config directory parameter, THE Registration_Unit SHALL load all governance configuration (gates, actions, routes, purposes, fields) from ConfigDB governance_* tables
2. WHEN governance_* tables do not exist in ConfigDB, THE Registration_Unit SHALL create them via DDL statements during first registration
3. WHEN a gate definition is registered via code, THE Registration_Unit SHALL insert the gate record into the `governance_gates` table in ConfigDB
4. WHEN an action definition is registered via code, THE Registration_Unit SHALL insert the action record into the `governance_actions` table in ConfigDB
5. THE Registration_Unit SHALL provide a `RegisterGate` procedure accepting gate key, display name, gate type, risk level, and conditions
6. THE Registration_Unit SHALL provide a `RegisterAction` procedure accepting action key, display name, risk level, gate key, and purpose key
7. IF a gate or action with the same key already exists in ConfigDB, THEN THE Registration_Unit SHALL update the existing record rather than creating a duplicate

### Requirement 2: Assayer Governance Integration

**User Story:** As a Assayer developer, I want the Governance framework integrated so that high-risk operations are governed with proper evidence recording and gate enforcement.

#### Acceptance Criteria

1. WHEN the Assayer project is compiled, THE Compiler SHALL resolve all `DeepBase.Governance.*` units via the `..\..\DeepBase\Governance` search path entry in the .dproj
2. WHEN Assayer_FMX.dpr initializes, THE Application SHALL call `RegisterGovernance` after DeepBase.Manager initialization
3. THE Registration_Unit SHALL define four gates for Assayer via code registration:
   - `deepllm.switch_model` with risk level L2
   - `deepllm.update_apikey` with risk level L3
   - `deepllm.delete_history` with risk level L3
   - `deepllm.generate_image` with risk level L2
4. WHEN the `deepllm.update_apikey` operation is invoked, THE Application SHALL wrap it with `TLegacyWrapBridge` and route through `EnterGate`
5. WHEN the `deepllm.delete_history` operation is invoked, THE Application SHALL wrap it with `TLegacyWrapBridge` and route through `EnterGate`
6. WHEN governance mode is set to `observe` in ConfigDB, THE OCGS_Runtime SHALL record Evidence for all gate entries but return `arsSuccess` without blocking
7. WHEN governance mode is set to `enforce` in ConfigDB and gate conditions are not met, THE OCGS_Runtime SHALL return `arsBlocked` and prevent the operation from executing
8. WHEN Assayer starts, THE SteeringExporter SHALL generate `{ProjectRoot}/.kiro/steering/governance-model.md` containing all registered gates, actions, and purposes

### Requirement 3: DeepShine Governance Integration

**User Story:** As a DeepShine developer, I want Governance integrated with awareness of the existing CircuitBreaker layer, so that when CircuitBreaker is open, governance LLM-call gates also block requests.

#### Acceptance Criteria

1. WHEN the DeepShine project is compiled, THE Compiler SHALL resolve all `DeepBase.Governance.*` units via the DeepBase Governance search path entry in the .dproj
2. WHEN DeepShineStudio.dpr initializes, THE Application SHALL call `RegisterGovernance` after DeepBase initialization
3. THE Registration_Unit SHALL define three gates for DeepShine via code registration:
   - `deepshine.llm_call` with risk level L2
   - `deepshine.publish_content` with risk level L3
   - `deepshine.delete_task` with risk level L2
4. WHEN the CircuitBreaker state is Open, THE GateResolver SHALL resolve `deepshine.llm_call` gate as `gsBlocked` with reason indicating circuit breaker is open
5. WHEN the CircuitBreaker state transitions from Open to Closed, THE GateResolver SHALL resolve `deepshine.llm_call` gate normally based on its own conditions
6. WHEN DeepShine starts, THE SteeringExporter SHALL generate `{ProjectRoot}/.kiro/steering/governance-model.md` for DeepShine

### Requirement 4: Evidence Recording in Observe Mode

**User Story:** As a system operator, I want all governance gate entries recorded as evidence even in observe mode, so that I can audit operations before switching to enforce mode.

#### Acceptance Criteria

1. WHEN a gate is entered in observe mode, THE EvidenceRecorder SHALL create an evidence entry with the gate key, user context, timestamp, and result status `erSuccess`
2. WHEN a gate is entered in enforce mode and blocked, THE EvidenceRecorder SHALL create an evidence entry with result status `erBlocked` and the blocked reason
3. WHEN evidence is recorded, THE EvidenceRecorder SHALL persist the entry to the SQLite evidence store asynchronously
4. THE EvidenceRecorder SHALL sanitize context data using the whitelist before persisting, removing sensitive fields such as API keys and passwords

### Requirement 5: Steering File Export

**User Story:** As an AI-assisted developer, I want governance model information exported as a steering file, so that AI tools understand the governance constraints of the project.

#### Acceptance Criteria

1. WHEN governance initialization completes, THE SteeringExporter SHALL write `governance-model.md` to the `.kiro/steering/` directory relative to the project root
2. THE SteeringExporter SHALL include all registered gates with their keys, names, types, and associated actions in the exported file
3. THE SteeringExporter SHALL include all registered purposes with their keys, names, and parent relationships in the exported file
4. IF the `.kiro/steering/` directory does not exist, THEN THE SteeringExporter SHALL create it before writing the file

### Requirement 6: Non-Regression

**User Story:** As a developer, I want governance integration to not break existing functionality, so that both projects remain stable.

#### Acceptance Criteria

1. WHEN Assayer is compiled with governance search paths added, THE Compiler SHALL produce a successful build with no new errors
2. WHEN DeepShine is compiled with governance search paths added, THE Compiler SHALL produce a successful build with no new errors
3. WHEN existing DUnitX tests are executed after governance integration, THE Test_Runner SHALL report all previously passing tests still pass
4. THE Governance module SHALL have no dependencies on VCL or FMX frameworks, maintaining UI-framework independence

### Requirement 7: DUnitX Test Coverage

**User Story:** As a developer, I want automated tests verifying governance behavior, so that I can confidently modify governance configuration.

#### Acceptance Criteria

1. WHEN `Test.Assayer.Governance.pas` is executed, THE Test_Runner SHALL verify that `EnterGate` in observe mode records evidence without blocking
2. WHEN `Test.Assayer.Governance.pas` is executed, THE Test_Runner SHALL verify that `EnterGate` in enforce mode blocks when gate conditions are not met
3. WHEN `Test.Assayer.Governance.pas` is executed, THE Test_Runner SHALL verify that `SteeringExporter` generates a valid markdown file with correct gate and action tables
4. WHEN `Test.DeepShine.Governance.pas` is executed, THE Test_Runner SHALL verify that CircuitBreaker open state causes `deepshine.llm_call` gate to resolve as blocked
5. WHEN `Test.DeepShine.Governance.pas` is executed, THE Test_Runner SHALL verify that CircuitBreaker closed state allows `deepshine.llm_call` gate to resolve normally
