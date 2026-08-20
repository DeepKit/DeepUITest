unit DeepFrames.Workflow.PromptVersion;

/// <summary>
/// Prompt version management for reproducible LLM call records.
///
/// P3.7: Same input + same prompt version + same model binding =
/// reproducible call record.
///
/// Computes deterministic version numbers from prompt content
/// (system_prompt + user_message + output_schema) using SHA256.
/// The version number is the first 4 bytes of the hash as uint32.
///
/// Also provides prompt content fingerprinting for deduplication
/// and caching of prompt run records.
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  /// <summary>Composite prompt identity for version tracking.</summary>
  TPromptIdentity = record
    SystemPrompt: string;
    UserMessage: string;
    OutputSchemaJson: string;
    AgentRole: string;
    Model: string;
    Temperature: Double;
    MaxTokens: Integer;
    /// <summary>Computed: 32-bit version number derived from content hash.</summary>
    VersionNo: Integer;
    /// <summary>Computed: full SHA256 hex digest of the prompt content.</summary>
    ContentHash: string;
    function IsIdentical(const AOther: TPromptIdentity): Boolean;
    function IsContentIdentical(const AOther: TPromptIdentity): Boolean;
  end;

  /// <summary>Result of a version check for reproducibility.</summary>
  TVersionCheckResult = record
    IsReproducible: Boolean;
    Reason: string;
    CurrentTemplate: TPromptTemplate;
    MatchedTemplate: TPromptTemplate;
    /// <summary>True if the same prompt content was previously run.</summary>
    HasPriorRun: Boolean;
    PriorRunId: string;
  end;

  /// <summary>Prompt version and identity manager.</summary>
  TPromptVersionManager = class
  public
    /// <summary>
    /// Compute a TPromptIdentity from a chat completion request.
    /// VersionNo = first 4 bytes of SHA256(system_prompt + user_message + schema) as uint32.
    /// </summary>
    class function ComputeIdentity(const ASystemPrompt, AUserMessage,
      AOutputSchemaJson, AAgentRole, AModel: string;
      ATemperature: Double; AMaxTokens: Integer): TPromptIdentity; static;

    /// <summary>
    /// Compute a version number from prompt content alone.
    /// </summary>
    class function ComputeVersion(const ASystemPrompt, AUserMessage,
      AOutputSchemaJson: string): Integer; static;

    /// <summary>
    /// Compute a content hash from all prompt fields.
    /// </summary>
    class function ComputeContentHash(const ASystemPrompt, AUserMessage,
      AOutputSchemaJson, AAgentRole, AModel: string;
      ATemperature: Double; AMaxTokens: Integer): string; static;

    /// <summary>
    /// Check if a prompt is reproducible: same content must map to same
    /// template version. Returns TVersionCheckResult.
    /// </summary>
    class function CheckReproducibility(const AIdentity: TPromptIdentity;
      const ATemplate: TPromptTemplate): TVersionCheckResult; static;

    /// <summary>
    /// Ensure a PromptTemplate record matches the computed identity.
    /// Updates version_no if content changed.
    /// </summary>
    class function SyncTemplateVersion(const ATemplate: TPromptTemplate;
      const AIdentity: TPromptIdentity): TPromptTemplate; static;
  end;

implementation

uses
  System.SysUtils,
  System.Hash,
  DeepFrames.Shared.Consts;

{ TPromptIdentity }

function TPromptIdentity.IsIdentical(const AOther: TPromptIdentity): Boolean;
begin
  Result := (VersionNo = AOther.VersionNo) and
    SameText(Model, AOther.Model) and
    (Abs(Temperature - AOther.Temperature) < 0.001) and
    (MaxTokens = AOther.MaxTokens);
end;

function TPromptIdentity.IsContentIdentical(const AOther: TPromptIdentity): Boolean;
begin
  Result := SameText(ContentHash, AOther.ContentHash);
end;

{ TPromptVersionManager }

class function TPromptVersionManager.ComputeIdentity(const ASystemPrompt,
  AUserMessage, AOutputSchemaJson, AAgentRole, AModel: string;
  ATemperature: Double; AMaxTokens: Integer): TPromptIdentity;
begin
  Result.SystemPrompt := ASystemPrompt;
  Result.UserMessage := AUserMessage;
  Result.OutputSchemaJson := AOutputSchemaJson;
  Result.AgentRole := AAgentRole;
  Result.Model := AModel;
  Result.Temperature := ATemperature;
  Result.MaxTokens := AMaxTokens;
  Result.VersionNo := ComputeVersion(ASystemPrompt, AUserMessage, AOutputSchemaJson);
  Result.ContentHash := ComputeContentHash(ASystemPrompt, AUserMessage,
    AOutputSchemaJson, AAgentRole, AModel, ATemperature, AMaxTokens);
end;

class function TPromptVersionManager.ComputeVersion(const ASystemPrompt,
  AUserMessage, AOutputSchemaJson: string): Integer;
var
  Combined: string;
  Hash: string;
begin
  Combined := ASystemPrompt + '||' + AUserMessage + '||' + AOutputSchemaJson;
  // Use SHA256 for deterministic version
  Hash := THashSHA2.GetHashString(Combined, THashSHA2.TSHA2Version.SHA256);
  // Take first 8 hex chars as 32-bit version number
  Result := StrToIntDef('$' + Copy(Hash, 1, 8), 0);
  if Result < 0 then
    Result := Abs(Result);
  if Result = 0 then
    Result := 1; // never version 0
end;

class function TPromptVersionManager.ComputeContentHash(const ASystemPrompt,
  AUserMessage, AOutputSchemaJson, AAgentRole, AModel: string;
  ATemperature: Double; AMaxTokens: Integer): string;
var
  Combined: string;
begin
  // Include all identity fields in the hash
  Combined := Format('%s||%s||%s||%s||%s||%.4f||%d',
    [ASystemPrompt, AUserMessage, AOutputSchemaJson, AAgentRole, AModel,
     ATemperature, AMaxTokens]);
  Result := THashSHA2.GetHashString(Combined, THashSHA2.TSHA2Version.SHA256).ToLower;
end;

class function TPromptVersionManager.CheckReproducibility(
  const AIdentity: TPromptIdentity;
  const ATemplate: TPromptTemplate): TVersionCheckResult;
begin
  Result.IsReproducible := True;
  Result.Reason := '';
  Result.CurrentTemplate := ATemplate;

  // Check version match
  if ATemplate.VersionNo <> AIdentity.VersionNo then
  begin
    Result.IsReproducible := False;
    Result.Reason := Format(
      'Template version %d does not match computed version %d — prompt content may have changed',
      [ATemplate.VersionNo, AIdentity.VersionNo]);
  end;

  // Check schema_version consistency
  if (Trim(AIdentity.OutputSchemaJson) <> '') and
     (AIdentity.OutputSchemaJson <> '{}') and
     (ATemplate.OutputSchemaJson <> '{}') then
  begin
    if not SameText(ATemplate.OutputSchemaJson, AIdentity.OutputSchemaJson) then
    begin
      if Result.IsReproducible then
      begin
        Result.IsReproducible := False;
        Result.Reason := 'Output schema has changed — output format may differ';
      end
      else
        Result.Reason := Result.Reason + '; output schema also changed';
    end;
  end;

  Result.HasPriorRun := False;
  Result.PriorRunId := '';
end;

class function TPromptVersionManager.SyncTemplateVersion(
  const ATemplate: TPromptTemplate;
  const AIdentity: TPromptIdentity): TPromptTemplate;
begin
  Result := ATemplate;
  if Result.VersionNo <> AIdentity.VersionNo then
  begin
    Result.VersionNo := AIdentity.VersionNo;
  end;
  if Result.Temperature <> AIdentity.Temperature then
    Result.Temperature := AIdentity.Temperature;
  if (Result.MaxTokens <> AIdentity.MaxTokens) and (AIdentity.MaxTokens > 0) then
    Result.MaxTokens := AIdentity.MaxTokens;
end;

end.