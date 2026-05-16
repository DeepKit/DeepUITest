{ ============================================================================
  DeepSpec.Validation

  Validates LLM-generated YAML against the DeepSpec Protocol v1.1 schema.
  Implements lenient and strict mode validation per protocol §11.
  ============================================================================ }

unit DeepSpec.Validation;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Yaml.Parser,
  DeepSpec.Models;

type
  TValidationSeverity = (vsError, vsWarning);

  TValidationMode = (vmLenient, vmStrict);

  TValidationError = record
    Rule: string;
    Severity: TValidationSeverity;
    Path: string;
    MessageText: string;
    FixHint: string;
  end;

  TValidationReport = class
  private
    FErrors: TList<TValidationError>;
    FMode: TValidationMode;
    FAutoFilled: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddError(const ARule: string; ASeverity: TValidationSeverity;
      const APath, AMessage, AFixHint: string);
    function HasErrors: Boolean;
    function ErrorCount: Integer;
    function WarningCount: Integer;
    procedure Clear;
    property Errors: TList<TValidationError> read FErrors;
    property Mode: TValidationMode read FMode write FMode;
    property AutoFilled: Integer read FAutoFilled write FAutoFilled;
  end;

  TYamlValidator = class
  private
    procedure ValidateNodeId(const AId, APath: string;
      AReport: TValidationReport);
    procedure ValidateKind(const AKind, ATree, APath: string;
      AReport: TValidationReport);
    procedure ValidateNodeStatus(const AStatus, APath: string;
      AReport: TValidationReport);
    procedure ValidateConfidence(const AConf, APath: string;
      AReport: TValidationReport);
    procedure ValidateSourceLayer(const ALayer, APath: string;
      AReport: TValidationReport);
    function IsValidFunctionKind(const AKind: string): Boolean;
    function IsValidModuleKind(const AKind: string): Boolean;
    function IsValidViewKind(const AKind: string): Boolean;
    function IsExtensionKind(const AKind: string): Boolean;
  public
    function ValidateTreeFile(const AYaml: string;
      AMode: TValidationMode = vmLenient): TValidationReport;
    function ValidateProjectSpec(const AYaml: string): TValidationReport;
    function ValidateLLMSecurityRules(const AYaml: string): TValidationReport;
  end;

implementation

uses
  System.RegularExpressions,
  System.StrUtils;

{ TValidationReport }

constructor TValidationReport.Create;
begin
  inherited Create;
  FErrors := TList<TValidationError>.Create;
  FMode := vmLenient;
end;

destructor TValidationReport.Destroy;
begin
  FErrors.Free;
  inherited;
end;

procedure TValidationReport.AddError(const ARule: string;
  ASeverity: TValidationSeverity; const APath, AMessage, AFixHint: string);
var
  LErr: TValidationError;
begin
  LErr.Rule := ARule;
  LErr.Severity := ASeverity;
  LErr.Path := APath;
  LErr.MessageText := AMessage;
  LErr.FixHint := AFixHint;
  FErrors.Add(LErr);
end;

function TValidationReport.HasErrors: Boolean;
begin
  for var LErr in FErrors do
    if LErr.Severity = vsError then
      Exit(True);
  Result := False;
end;

function TValidationReport.ErrorCount: Integer;
begin
  Result := 0;
  for var LErr in FErrors do
    if LErr.Severity = vsError then
      Inc(Result);
end;

function TValidationReport.WarningCount: Integer;
begin
  Result := 0;
  for var LErr in FErrors do
    if LErr.Severity = vsWarning then
      Inc(Result);
end;

procedure TValidationReport.Clear;
begin
  FErrors.Clear;
  FAutoFilled := 0;
end;

{ TYamlValidator }

function TYamlValidator.IsValidFunctionKind(const AKind: string): Boolean;
const
  KINDS: array[0..7] of string = (
    'feature', 'capability', 'user_story', 'use_case',
    'rule', 'constraint', 'non_functional', 'integration'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsValidModuleKind(const AKind: string): Boolean;
const
  KINDS: array[0..9] of string = (
    'package', 'unit', 'class', 'interface', 'service',
    'repository', 'controller', 'adapter', 'utility', 'config'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsValidViewKind(const AKind: string): Boolean;
const
  KINDS: array[0..10] of string = (
    'application', 'window', 'dialog', 'page', 'frame',
    'panel', 'control', 'menu', 'toolbar', 'statusbar', 'tray'
  );
begin
  for var K in KINDS do
    if K = AKind then Exit(True);
  Result := False;
end;

function TYamlValidator.IsExtensionKind(const AKind: string): Boolean;
begin
  Result := AKind.StartsWith('x_') and (AKind.Length >= 3);
end;

procedure TYamlValidator.ValidateNodeId(const AId, APath: string;
  AReport: TValidationReport);
var
  LRegex: TRegEx;
begin
  if AId = '' then
  begin
    AReport.AddError('missing_id', vsError, APath,
      'Node id is required', 'Add a unique id like "func-some-name"');
    Exit;
  end;

  LRegex := TRegEx.Create('^(func|mod|view)-[a-z0-9][a-z0-9\-]{0,39}$');
  if not LRegex.IsMatch(AId) then
    AReport.AddError('invalid_id_format', vsError, APath,
      'Node id "' + AId + '" does not match required pattern',
      'Use format {func|mod|view}-{slug}, lowercase letters/digits/hyphens only, max 40 chars after prefix');
end;

procedure TYamlValidator.ValidateKind(const AKind, ATree, APath: string;
  AReport: TValidationReport);
begin
  if AKind = '' then
  begin
    AReport.AddError('missing_kind', vsError, APath,
      'Node kind is required', 'Add a kind value like "feature" for functions');
    Exit;
  end;

  if IsExtensionKind(AKind) then Exit;

  var LValid := False;
  if ATree = 'function' then
    LValid := IsValidFunctionKind(AKind)
  else if ATree = 'module' then
    LValid := IsValidModuleKind(AKind)
  else if ATree = 'view' then
    LValid := IsValidViewKind(AKind);

  if not LValid then
    AReport.AddError('unknown_kind', vsWarning, APath,
      'Kind "' + AKind + '" is not a built-in value for tree "' + ATree + '"',
      'Use a built-in kind or prefix with "x_" for extensions');
end;

procedure TYamlValidator.ValidateNodeStatus(const AStatus, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..4] of string = ('candidate', 'confirmed', 'uncertain', 'rejected', 'superseded');
begin
  if AStatus = '' then Exit; // optional, default applies
  for var V in VALID do
    if V = AStatus then Exit;
  AReport.AddError('invalid_status', vsError, APath,
    'Status "' + AStatus + '" is not valid',
    'Use one of: candidate, confirmed, uncertain, rejected, superseded');
end;

procedure TYamlValidator.ValidateConfidence(const AConf, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..2] of string = ('low', 'medium', 'high');
begin
  if AConf = '' then Exit;
  for var V in VALID do
    if V = AConf then Exit;
  AReport.AddError('invalid_confidence', vsError, APath,
    'Confidence "' + AConf + '" is not valid',
    'Use one of: low, medium, high');
end;

procedure TYamlValidator.ValidateSourceLayer(const ALayer, APath: string;
  AReport: TValidationReport);
const
  VALID: array[0..3] of string = (
    'parsed_from_a', 'human_decision', 'ai_inferred', 'generated_summary'
  );
begin
  if ALayer = '' then Exit;
  for var V in VALID do
    if V = ALayer then Exit;
  AReport.AddError('invalid_source_layer', vsError, APath,
    'source_layer "' + ALayer + '" is not valid',
    'Use one of: parsed_from_a, human_decision, ai_inferred, generated_summary');
end;

function TYamlValidator.ValidateTreeFile(const AYaml: string;
  AMode: TValidationMode): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
  LSeenIds: TDictionary<string, Boolean>;
begin
  Result := TValidationReport.Create;
  Result.Mode := AMode;
  LParser := TYamlParser.Create;
  LSeenIds := TDictionary<string, Boolean>.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      on E: Exception do
      begin
        Result.AddError('parse_error', vsError, '',
          'YAML parse failed: ' + E.Message, 'Check syntax and indentation');
        Exit;
      end;
    end;

    try
      // Check version
      var LVer := LRoot.GetString('version', '');
      if LVer = '' then
        Result.AddError('missing_version', vsWarning, '/version',
          'version field missing', 'Add: version: "1.0"');

      // Check tree type
      var LTree := LRoot.GetString('tree', '');
      if (LTree <> 'function') and (LTree <> 'module') and (LTree <> 'view') then
        Result.AddError('invalid_tree', vsError, '/tree',
          'tree must be "function", "module", or "view"', '');

      // Validate nodes
      var LNodes := LRoot.GetSeq('nodes');
      if LNodes <> nil then
      begin
        for var I := 0 to LNodes.SeqCount - 1 do
        begin
          var LNode := LNodes.SeqItem(I);
          if LNode = nil then Continue;

          var LPath := '/nodes/' + I.ToString;
          var LId := LNode.GetString('id', '');
          var LNodeTree := LNode.GetString('tree', LTree);

          ValidateNodeId(LId, LPath + '/id', Result);

          if (LId <> '') and LSeenIds.ContainsKey(LId) then
            Result.AddError('duplicate_id', vsError, LPath + '/id',
              'Duplicate id: ' + LId, 'Each node id must be globally unique');
          if LId <> '' then
            LSeenIds.AddOrSetValue(LId, True);

          if LNode.GetString('title', '') = '' then
            Result.AddError('missing_title', vsError, LPath + '/title',
              'Node title is required', 'Add a human-readable title');

          ValidateKind(LNode.GetString('kind', ''), LNodeTree, LPath + '/kind', Result);
          ValidateNodeStatus(LNode.GetString('status', ''), LPath + '/status', Result);
          ValidateConfidence(LNode.GetString('confidence', ''), LPath + '/confidence', Result);
          ValidateSourceLayer(LNode.GetString('source_layer', ''), LPath + '/source_layer', Result);
        end;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
    LSeenIds.Free;
  end;
end;

function TYamlValidator.ValidateProjectSpec(const AYaml: string): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
begin
  Result := TValidationReport.Create;
  LParser := TYamlParser.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      on E: Exception do
      begin
        Result.AddError('parse_error', vsError, '',
          'YAML parse failed: ' + E.Message, '');
        Exit;
      end;
    end;

    try
      if LRoot.GetString('version', '') = '' then
        Result.AddError('missing_version', vsWarning, '/version',
          'version field missing', '');

      var LProject := LRoot.Get('project');
      if LProject = nil then
        Result.AddError('missing_project', vsError, '/project',
          'project section is required', '')
      else
      begin
        if LProject.GetString('name', '') = '' then
          Result.AddError('missing_project_name', vsError, '/project/name',
            'project.name is required', '');
        if LProject.GetString('type', '') = '' then
          Result.AddError('missing_project_type', vsError, '/project/type',
            'project.type is required', 'Use a value from §3.1 recommended types or "unknown"');
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

function TYamlValidator.ValidateLLMSecurityRules(const AYaml: string): TValidationReport;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
begin
  // Per protocol §12.1 rule 11: LLM output must not contain decided_by: human
  Result := TValidationReport.Create;
  LParser := TYamlParser.Create;
  try
    try
      LRoot := LParser.Parse(AYaml);
    except
      Exit;
    end;

    try
      var LDecisions := LRoot.GetSeq('decisions');
      if LDecisions <> nil then
      begin
        for var I := 0 to LDecisions.SeqCount - 1 do
        begin
          var LDec := LDecisions.SeqItem(I);
          if LDec = nil then Continue;
          if LDec.GetString('decided_by', '') = 'human' then
            Result.AddError('forbidden_human_decided_by', vsError,
              '/decisions/' + I.ToString + '/decided_by',
              'LLM output must not set decided_by: human (protocol §12.1 rule 11)',
              'Remove the decided_by field or set it to "system". Human decisions ' +
              'must be created via DeepSpec UI write paths only.');
        end;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

end.
