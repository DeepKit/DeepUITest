{ ============================================================================
  Test.DeepSpec.Validation

  DUnitX tests for DeepSpec.Validation.
  Covers protocol validation rules.
  Uses flow-sequence [] syntax to avoid block-sequence parsing issues.
  ============================================================================ }

unit Test.DeepSpec.Validation;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DeepSpec.Yaml.Parser,
  DeepSpec.Validation;

type
  [TestFixture]
  TValidationTreeFileTests = class
  public
    [Test]
    procedure MissingVersion_ReportedAsWarning;

    [Test]
    procedure MissingTree_ReportedAsError;

    [Test]
    procedure InvalidTreeType_ReportedAsError;

    [Test]
    procedure ValidTreeFile_NoErrors;

    [Test]
    procedure InvalidNodeStatus_ReportedAsError;

    [Test]
    procedure InvalidConfidence_ReportedAsError;

    [Test]
    procedure ValidFogState_NoErrors;

    [Test]
    procedure InvalidFogState_ReportedAsError;
  end;

  [TestFixture]
  TValidationProjectSpecTests = class
  public
    [Test]
    procedure MissingProject_ReportedAsError;

    [Test]
    procedure MissingProjectName_ReportedAsError;

    [Test]
    procedure MissingProjectType_ReportedAsError;

    [Test]
    procedure CompleteProjectSpec_NoErrors;
  end;

  [TestFixture]
  TValidationSecurityTests = class
  public
    [Test]
    procedure HumanDecidedBy_ForbiddenInLLMOutput;

    [Test]
    procedure SystemDecidedBy_Allowed;

    [Test]
    procedure EmptyDecisionsList_NoErrors;
  end;

  [TestFixture]
  TValidationReportTests = class
  public
    [Test]
    procedure NewReport_NoErrors;

    [Test]
    procedure AddError_HasErrorsTrue;

    [Test]
    procedure WarningOnly_HasErrorsFalse;

    [Test]
    procedure ClearRemovesAll;
  end;

  [TestFixture]
  TValidationParseErrorTests = class
  public
    [Test]
    procedure InvalidYAML_DoesNotCrash;
  end;

  [TestFixture]
  TValidationNodeIdTests = class
  public
    [Test]
    procedure ValidFuncId_NoError;

    [Test]
    procedure InvalidPrefix_ReportedAsError;

    [Test]
    procedure DuplicateId_ReportedAsError;
  end;

  [TestFixture]
  TValidationKindTests = class
  public
    [Test]
    procedure ExtensionKind_NoError;
  end;

  [TestFixture]
  TValidationParentRefTests = class
  public
    [Test]
    procedure ValidParent_NoError;

    [Test]
    procedure MissingParentRef_ReportedAsError;

    [Test]
    procedure CircularParent_ReportedAsError;
  end;

  [TestFixture]
  TValidationStatusTests = class
  public
    [Test]
    procedure ValidGenStatus_NoError;

    [Test]
    procedure InvalidGenStatus_ReportedAsError;

    [Test]
    procedure InvalidReviewStatus_ReportedAsError;
  end;

  /// <summary>Issues / exploration-ticket validation (BUG-11 step 1 remainder).
  /// Covers id prefix, enum legality, non-empty affected_nodes, and
  /// requires_human consistency with ticket types.</summary>
  [TestFixture]
  TValidationIssuesTests = class
  public
    [Test]
    procedure ValidIssue_NoErrors;

    [Test]
    procedure EmptyId_ReportedAsError;

    [Test]
    procedure InvalidIssueIdPrefix_ReportedAsError;

    [Test]
    procedure InvalidSeverity_ReportedAsError;

    [Test]
    procedure InvalidIssueType_ReportedAsError;

    [Test]
    procedure EmptyAffectedNodes_ReportedAsError;

    [Test]
    procedure ResearchTicketWithRequiresHuman_NoError;

    [Test]
    procedure NonTicketWithRequiresHuman_ReportedAsWarning;
  end;

implementation

{ TValidationTreeFileTests }

procedure TValidationTreeFileTests.MissingVersion_ReportedAsWarning;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile('tree: function' + #10 + 'nodes: []');
    try
      var LFound := False;
      for var E in R.Errors do
        if (E.Rule = 'missing_version') and (E.Severity = vsWarning) then LFound := True;
      Assert.IsTrue(LFound, 'Missing version should be a warning');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.MissingTree_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile('version: "1.0"' + #10 + 'nodes: []');
    try
      Assert.IsTrue(R.HasErrors, 'Missing tree should be an error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.InvalidTreeType_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile('version: "1.0"' + #10 + 'tree: unknown' + #10 + 'nodes: []');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_tree' then LFound := True;
      Assert.IsTrue(LFound, 'Invalid tree type should be reported');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.ValidTreeFile_NoErrors;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes: []');
    try
      Assert.IsFalse(R.HasErrors, 'Valid tree file with empty nodes should have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.InvalidNodeStatus_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-test' + #10 +
      '    title: Test' + #10 +
      '    kind: feature' + #10 +
      '    status: invalid_status');
    try
      // block sequence parsing is verified working (bugfix.md BUG-4),
      // so the validator must surface invalid_status for status: invalid_status.
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_status' then LFound := True;
      Assert.IsTrue(LFound, 'status: invalid_status must raise invalid_status error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.InvalidConfidence_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-test' + #10 +
      '    title: Test' + #10 +
      '    kind: feature' + #10 +
      '    confidence: super_high');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_confidence' then LFound := True;
      Assert.IsTrue(LFound, 'confidence: super_high must raise invalid_confidence error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.ValidFogState_NoErrors;
var
  V: TYamlValidator;
  R: TValidationReport;
  LFound: Boolean;
  LE: TValidationError;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-fog' + #10 +
      '    title: Foggy node' + #10 +
      '    kind: feature' + #10 +
      '    fog_state: foggy');
    try
      // foggy is a legal value — no invalid_fog_state error should appear
      LFound := False;
      for LE in R.Errors do
        if LE.Rule = 'invalid_fog_state' then LFound := True;
      Assert.IsFalse(LFound, 'fog_state: foggy must be valid, no invalid_fog_state error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationTreeFileTests.InvalidFogState_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
  LFound: Boolean;
  LE: TValidationError;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-fog' + #10 +
      '    title: Foggy node' + #10 +
      '    kind: feature' + #10 +
      '    fog_state: blurry');
    try
      LFound := False;
      for LE in R.Errors do
        if LE.Rule = 'invalid_fog_state' then LFound := True;
      Assert.IsTrue(LFound, 'fog_state: blurry must raise invalid_fog_state error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationProjectSpecTests }

procedure TValidationProjectSpecTests.MissingProject_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateProjectSpec('version: "1.0"');
    try
      Assert.IsTrue(R.HasErrors, 'Missing project section should be an error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationProjectSpecTests.MissingProjectName_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateProjectSpec(
      'version: "1.0"' + #10 +
      'project:' + #10 +
      '  type: desktop');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'missing_project_name' then LFound := True;
      Assert.IsTrue(LFound, 'Missing project name should be an error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationProjectSpecTests.MissingProjectType_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateProjectSpec(
      'version: "1.0"' + #10 +
      'project:' + #10 +
      '  name: TestApp');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'missing_project_type' then LFound := True;
      Assert.IsTrue(LFound, 'Missing project type should be an error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationProjectSpecTests.CompleteProjectSpec_NoErrors;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateProjectSpec(
      'version: "1.0"' + #10 +
      'project:' + #10 +
      '  name: TestApp' + #10 +
      '  type: desktop');
    try
      Assert.IsFalse(R.HasErrors, 'Complete project spec should have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationSecurityTests }

procedure TValidationSecurityTests.HumanDecidedBy_ForbiddenInLLMOutput;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateLLMSecurityRules(
      'decisions:' + #10 +
      '  - id: dec-1' + #10 +
      '    decided_by: human');
    try
      // decided_by: human in LLM output is a security violation.
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'forbidden_human_decided_by' then LFound := True;
      Assert.IsTrue(LFound, 'decided_by: human must raise forbidden_human_decided_by');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationSecurityTests.SystemDecidedBy_Allowed;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateLLMSecurityRules(
      'decisions:' + #10 +
      '  - id: dec-1' + #10 +
      '    decided_by: system');
    try
      Assert.IsFalse(R.HasErrors, 'decided_by: system should be allowed');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationSecurityTests.EmptyDecisionsList_NoErrors;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateLLMSecurityRules('decisions: []');
    try
      Assert.IsFalse(R.HasErrors, 'Empty decisions list should have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationReportTests }

procedure TValidationReportTests.NewReport_NoErrors;
var
  R: TValidationReport;
begin
  R := TValidationReport.Create;
  try
    Assert.IsFalse(R.HasErrors, 'New report should have no errors');
    Assert.AreEqual(0, R.ErrorCount);
    Assert.AreEqual(0, R.WarningCount);
  finally
    R.Free;
  end;
end;

procedure TValidationReportTests.AddError_HasErrorsTrue;
var
  R: TValidationReport;
begin
  R := TValidationReport.Create;
  try
    R.AddError('test_rule', vsError, '/path', 'message', 'hint');
    Assert.IsTrue(R.HasErrors);
    Assert.AreEqual(1, R.ErrorCount);
  finally
    R.Free;
  end;
end;

procedure TValidationReportTests.WarningOnly_HasErrorsFalse;
var
  R: TValidationReport;
begin
  R := TValidationReport.Create;
  try
    R.AddError('test_rule', vsWarning, '/path', 'message', 'hint');
    Assert.IsFalse(R.HasErrors, 'Warning-only should not set HasErrors');
    Assert.AreEqual(1, R.WarningCount);
  finally
    R.Free;
  end;
end;

procedure TValidationReportTests.ClearRemovesAll;
var
  R: TValidationReport;
begin
  R := TValidationReport.Create;
  try
    R.AddError('r1', vsError, '/a', 'm1', '');
    R.AddError('r2', vsWarning, '/b', 'm2', '');
    R.Clear;
    Assert.IsFalse(R.HasErrors);
    Assert.AreEqual(0, R.ErrorCount);
    Assert.AreEqual(0, R.WarningCount);
  finally
    R.Free;
  end;
end;

{ TValidationParseErrorTests }

procedure TValidationParseErrorTests.InvalidYAML_DoesNotCrash;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile('{{{{invali d yaml ::::');
    try
      // Must not crash. The validator either reports parse_error or treats
      // the malformed input as an empty map; both are acceptable as long as
      // no exception escapes. A returned report object proves survival.
      Assert.IsTrue(R <> nil, 'Validator must return a report, not crash, on malformed YAML');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationNodeIdTests }

procedure TValidationNodeIdTests.ValidFuncId_NoError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes: []');
    try
      for var E in R.Errors do
        if E.Rule = 'invalid_id_format' then
          Assert.Fail('Valid tree file should not have invalid_id_format');
      // The loop above may execute zero Asserts when there are no errors;
      // make the success explicit so FailsOnNoAsserts stays satisfied.
      Assert.IsFalse(R.HasErrors, 'Valid function tree file must have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationNodeIdTests.InvalidPrefix_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: xxx-bad' + #10 +
      '    title: Bad' + #10 +
      '    kind: feature');
    try
      // id prefix must match the tree type: function tree requires 'func-'.
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_id_format' then LFound := True;
      Assert.IsTrue(LFound, 'id: xxx-bad in function tree must raise invalid_id_format');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationNodeIdTests.DuplicateId_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-same' + #10 +
      '    title: First' + #10 +
      '    kind: feature' + #10 +
      '  - id: func-same' + #10 +
      '    title: Second' + #10 +
      '    kind: feature');
    try
      // Two nodes sharing the same id must be flagged.
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'duplicate_id' then LFound := True;
      Assert.IsTrue(LFound, 'duplicate id must raise duplicate_id error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationKindTests }

procedure TValidationKindTests.ExtensionKind_NoError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-ext' + #10 +
      '    title: Custom' + #10 +
      '    kind: x_custom_type');
    try
      // x_ prefixed kinds are legal extensions and must not raise unknown_kind.
      for var E in R.Errors do
        if E.Rule = 'unknown_kind' then
          Assert.Fail('kind: x_custom_type should be accepted as extension, not unknown_kind');
      Assert.IsFalse(R.HasErrors, 'x_-prefixed extension kind must produce no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationParentRefTests }

procedure TValidationParentRefTests.ValidParent_NoError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-parent' + #10 +
      '    title: Parent' + #10 +
      '    kind: feature' + #10 +
      '  - id: func-child' + #10 +
      '    title: Child' + #10 +
      '    kind: feature' + #10 +
      '    parent_id: func-parent');
    try
      for var E in R.Errors do
        if E.Rule = 'invalid_parent_ref' then
          Assert.Fail('Valid parent ref should not produce invalid_parent_ref');
      Assert.IsFalse(R.HasErrors, 'valid parent/child tree must have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationParentRefTests.MissingParentRef_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-child' + #10 +
      '    title: Child' + #10 +
      '    kind: feature' + #10 +
      '    parent_id: func-nonexistent');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_parent_ref' then LFound := True;
      Assert.IsTrue(LFound, 'parent_id referencing non-existent node must raise invalid_parent_ref');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationParentRefTests.CircularParent_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-a' + #10 +
      '    title: A' + #10 +
      '    kind: feature' + #10 +
      '    parent_id: func-b' + #10 +
      '  - id: func-b' + #10 +
      '    title: B' + #10 +
      '    kind: feature' + #10 +
      '    parent_id: func-a');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'circular_parent' then LFound := True;
      Assert.IsTrue(LFound, 'mutual parent_id (a->b->a) must raise circular_parent');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationStatusTests }

procedure TValidationStatusTests.ValidGenStatus_NoError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-test' + #10 +
      '    title: Test' + #10 +
      '    kind: feature' + #10 +
      '    gen_status: confirmed');
    try
      for var E in R.Errors do
        if E.Rule = 'invalid_gen_status' then
          Assert.Fail('Valid gen_status should not produce error');
      Assert.IsFalse(R.HasErrors, 'valid gen_status tree must have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationStatusTests.InvalidGenStatus_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-test' + #10 +
      '    title: Test' + #10 +
      '    kind: feature' + #10 +
      '    gen_status: published');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_gen_status' then LFound := True;
      Assert.IsTrue(LFound, 'gen_status: published must raise invalid_gen_status');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationStatusTests.InvalidReviewStatus_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateTreeFile(
      'version: "1.0"' + #10 +
      'tree: function' + #10 +
      'nodes:' + #10 +
      '  - id: func-test' + #10 +
      '    title: Test' + #10 +
      '    kind: feature' + #10 +
      '    review_status: maybe');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_review_status' then LFound := True;
      Assert.IsTrue(LFound, 'review_status: maybe must raise invalid_review_status');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

{ TValidationIssuesTests }

procedure TValidationIssuesTests.ValidIssue_NoErrors;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-fog-func-root"' + #10 +
      '    severity: high' + #10 +
      '    type: coverage_gap' + #10 +
      '    title: Missing coverage' + #10 +
      '    description: function root has no children' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-root' + #10 +
      '    status: open');
    try
      Assert.IsFalse(R.HasErrors, 'A complete valid issue must produce no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.EmptyId_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: ""' + #10 +
      '    severity: medium' + #10 +
      '    type: conflict' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-x' + #10 +
      '    status: open');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'missing_id' then LFound := True;
      Assert.IsTrue(LFound, 'empty issue id must raise missing_id');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.InvalidIssueIdPrefix_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "func-bad"' + #10 +
      '    severity: medium' + #10 +
      '    type: conflict' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-x' + #10 +
      '    status: open');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_issue_id' then LFound := True;
      Assert.IsTrue(LFound, 'id without issue- prefix must raise invalid_issue_id');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.InvalidSeverity_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-1"' + #10 +
      '    severity: urgent' + #10 +
      '    type: conflict' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-x' + #10 +
      '    status: open');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_issue_severity' then LFound := True;
      Assert.IsTrue(LFound, 'severity: urgent must raise invalid_issue_severity');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.InvalidIssueType_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-1"' + #10 +
      '    severity: medium' + #10 +
      '    type: bogus_ticket' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-x' + #10 +
      '    status: open');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'invalid_issue_type' then LFound := True;
      Assert.IsTrue(LFound, 'type: bogus_ticket must raise invalid_issue_type');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.EmptyAffectedNodes_ReportedAsError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-1"' + #10 +
      '    severity: medium' + #10 +
      '    type: conflict' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes: []' + #10 +
      '    status: open');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'empty_affected_nodes' then LFound := True;
      Assert.IsTrue(LFound, 'empty affected_nodes must raise empty_affected_nodes');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.ResearchTicketWithRequiresHuman_NoError;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    // research_ticket may be AFK (requires_human: false) — no mismatch error.
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-research-1"' + #10 +
      '    severity: medium' + #10 +
      '    type: research_ticket' + #10 +
      '    title: Probe fog' + #10 +
      '    description: investigate unknowns' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-root' + #10 +
      '    status: open' + #10 +
      '    requires_human: false');
    try
      for var E in R.Errors do
        if E.Rule = 'requires_human_mismatch' then
          Assert.Fail('research_ticket + requires_human must not raise mismatch');
      Assert.IsFalse(R.HasErrors, 'research_ticket with requires_human must have no errors');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

procedure TValidationIssuesTests.NonTicketWithRequiresHuman_ReportedAsWarning;
var
  V: TYamlValidator;
  R: TValidationReport;
begin
  V := TYamlValidator.Create;
  try
    // requires_human on a non-ticket issue (conflict) is meaningless -> warning,
    // and must NOT be an error (field stays optional).
    R := V.ValidateIssuesFile(
      'version: "1.0"' + #10 +
      'issues:' + #10 +
      '  - id: "issue-1"' + #10 +
      '    severity: medium' + #10 +
      '    type: conflict' + #10 +
      '    title: T' + #10 +
      '    description: d' + #10 +
      '    affected_nodes:' + #10 +
      '      - func-x' + #10 +
      '    status: open' + #10 +
      '    requires_human: true');
    try
      var LFound := False;
      for var E in R.Errors do
        if E.Rule = 'requires_human_mismatch' then LFound := True;
      Assert.IsTrue(LFound, 'non-ticket issue with requires_human must raise requires_human_mismatch');
      Assert.IsFalse(R.HasErrors, 'requires_human_mismatch is a warning, not an error');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TValidationTreeFileTests);
  TDUnitX.RegisterTestFixture(TValidationProjectSpecTests);
  TDUnitX.RegisterTestFixture(TValidationSecurityTests);
  TDUnitX.RegisterTestFixture(TValidationReportTests);
  TDUnitX.RegisterTestFixture(TValidationParseErrorTests);
  TDUnitX.RegisterTestFixture(TValidationNodeIdTests);
  TDUnitX.RegisterTestFixture(TValidationKindTests);
  TDUnitX.RegisterTestFixture(TValidationParentRefTests);
  TDUnitX.RegisterTestFixture(TValidationStatusTests);
  TDUnitX.RegisterTestFixture(TValidationIssuesTests);

end.
