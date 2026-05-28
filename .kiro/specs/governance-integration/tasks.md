# Implementation Plan: Governance Integration

## Overview

Integrate OCGS Governance from DeepBase into Assayer and DeepShine via a ConfigDB-backed registration path. Implementation proceeds bottom-up: shared ConfigRegistrar first, then Assayer integration, then DeepShine with CB linkage.

## Tasks

- [ ] 1. Create TConfigRegistrar unit in DeepBase/Governance
  - [x] 1.1 Create `DeepBase.Governance.ConfigRegistrar.pas` with TConfigRegistrar class
    - Implement `EnsureTables` (DDL for governance_gates, governance_gate_conditions, governance_actions, governance_purposes, governance_config)
    - Implement `RegisterGate`, `RegisterAction`, `RegisterPurpose` with upsert logic
    - Implement `LoadFromDB` to populate a TKeyResolver from ConfigDB
    - Implement `GetMode`/`SetMode` for observe/enforce
    - Use parameterized SQL via FireDAC
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [ ]* 1.2 Write property tests for TConfigRegistrar
    - **Property 1: Registration Round-Trip**
    - **Property 2: Registration Idempotence**
    - **Validates: Requirements 1.1, 1.3, 1.4, 1.7**

- [ ] 2. Create TObserveGateResolver decorator
  - [x] 2.1 Create `DeepBase.Governance.ObserveGateResolver.pas`
    - Implement IGateResolver decorator that wraps inner resolver
    - In observe mode: log blocked evidence, override state to gsOpen
    - In enforce mode: pass through unchanged
    - _Requirements: 2.6, 2.7, 4.1, 4.2_

  - [ ]* 2.2 Write property tests for observe/enforce mode behavior
    - **Property 3: Observe Mode Never Blocks**
    - **Property 4: Observe Mode Records Evidence**
    - **Property 5: Enforce Mode Blocks on Failing Conditions**
    - **Validates: Requirements 2.6, 2.7, 4.1, 4.2**

- [x] 3. Modify DeepBase.Governance.Registration to support ConfigDB path
  - [x] 3.1 Add overloaded `RegisterGovernance(AEnabled: Boolean)` that uses TConfigRegistrar
    - Create TGovernanceLifecycle with TObserveGateResolver based on mode
    - Expose `GovernanceRegistrar` function for downstream access
    - Keep existing `RegisterGovernance(AConfigDir)` overload for backward compatibility
    - _Requirements: 1.1, 1.2_

- [x] 4. Checkpoint - Ensure DeepBase governance compiles and base tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Assayer Governance Integration
  - [x] 5.1 Add `..\..\DeepBase\Governance` to Assayer_FMX.dproj search paths
    - Edit the .dproj XML to add the path to DCC_UnitSearchPath
    - _Requirements: 2.1_

  - [x] 5.2 Create `Assayer.Governance.Registration.pas` in Assayer/src/
    - Register four gates: deepllm.switch_model (L2), deepllm.update_apikey (L3), deepllm.delete_history (L3), deepllm.generate_image (L2)
    - Register corresponding actions
    - Set initial mode to observe
    - Call SteeringExporter to generate .kiro/steering/governance-model.md
    - _Requirements: 2.2, 2.3, 2.6, 2.8_

  - [x] 5.3 Add `RegisterAssayerGovernance` call to Assayer_FMX.dpr
    - Place after DeepBase initialization, before Application.Run
    - Add `ShutdownGovernance` in finalization
    - _Requirements: 2.2_

  - [x] 5.4 Wrap API key and history deletion operations with TLegacyWrapBridge
    - Identify existing procedures for API key update and history deletion
    - Wrap with TLegacyWrapBridge.CreateSimple and route through EnterGate
    - _Requirements: 2.4, 2.5_

  - [ ]* 5.5 Write DUnitX tests in `Test.Assayer.Governance.pas`
    - Test observe mode records evidence without blocking
    - Test enforce mode blocks when conditions fail
    - Test SteeringExporter output contains all gate keys
    - **Property 6: Export Contains All Registered Entities**
    - **Validates: Requirements 2.6, 2.7, 2.8, 7.1, 7.2, 7.3**

- [x] 6. Checkpoint - Ensure Assayer compiles and governance tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. DeepShine Governance Integration with CircuitBreaker Linkage
  - [x] 7.1 Add DeepBase Governance search path to DeepShineStudio.dproj
    - _Requirements: 3.1_

  - [x] 7.2 Create `DeepShine.Governance.Registration.pas` in DeepShine/Common/
    - Register three gates: deepshine.llm_call (L2), deepshine.publish_content (L3), deepshine.delete_task (L2)
    - Register gckState condition evaluator that checks CircuitBreaker state
    - The evaluator checks `CircuitBreakers.TryGet('DeepDeepShine-PG')` and returns `State = csClosed`
    - _Requirements: 3.2, 3.3, 3.4, 3.5_

  - [x] 7.3 Add `RegisterDeepShineGovernance` call to DeepShineStudio.dpr
    - Place after DeepBase initialization
    - Add ShutdownGovernance in finalization
    - _Requirements: 3.2, 3.6_

  - [ ]* 7.4 Write DUnitX tests in `Test.DeepShine.Governance.pas`
    - Test CB Open → gate blocked
    - Test CB Closed → gate open
    - Test CB transition Open→Closed restores gate
    - **Property 7: CircuitBreaker State Determines Gate Resolution**
    - **Validates: Requirements 3.4, 3.5, 7.4, 7.5**

- [ ] 8. Evidence Sanitization Verification
  - [ ]* 8.1 Write property test for evidence sanitization
    - **Property 8: Evidence Sanitization**
    - Generate random contexts with whitelisted + non-whitelisted fields
    - Verify InputSummary only contains whitelisted field names
    - **Validates: Requirements 4.4**

- [ ] 9. Final Checkpoint - Full compilation and regression
  - Compile Assayer via `Assayer/compile_d13_fmx.bat`
  - Compile DeepShine via `DeepShine/build-all.cmd`
  - Run existing test suites to verify no regressions
  - Verify no JSON/INI/YAML config files created in either project
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- All governance config goes into ConfigDB — no JSON files in downstream projects
- The existing `TConfigLoader` (JSON-based) remains for backward compatibility but is not used by Assayer/DeepShine
- Property tests use `[RepeatTest(100)]` with randomized setup per iteration
- CircuitBreaker name `'DeepDeepShine-PG'` matches existing code (known naming artifact)
