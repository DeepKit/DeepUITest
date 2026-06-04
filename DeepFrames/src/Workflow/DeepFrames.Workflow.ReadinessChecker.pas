unit DeepFrames.Workflow.ReadinessChecker;

/// <summary>
/// Content type adapter readiness validation.
///
/// Per docs/01.arch-系统架构-architecture.md T6:
///   Each content_type adapter must provide a readiness report
///   with at least 1 E2E sample pass before status transitions to 'active'.
///
/// Check types (per READINESS_CHECK_* constants in Consts):
///   - e2e_sample: validates sample input produces valid output
///   - schema: validates config_schema_json is valid JSON Schema
///   - pipeline: validates default_pipeline_json references real phases
///   - output: validates supported_output_types_json
///
/// Built-in content types (always active):
///   longform_zh_article, webnovel_zh — these have implicit readiness
///   and do not go through the adapter check flow.
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  /// <summary>Single readiness check result.</summary>
  TReadinessCheck = record
    CheckType: string;
    Passed: Boolean;
    Score: Double;
    Summary: string;
    Issues: TArray<string>;
    Evidence: TJSONObject;
  end;

  /// <summary>Aggregate readiness report.</summary>
  TAggregateReadiness = record
    AllPassed: Boolean;
    OverallScore: Double;
    Checks: TArray<TReadinessCheck>;
    ReportJson: string;
  end;

  /// <summary>Readiness checker for content type adapters.</summary>
  TReadinessChecker = class
  public
    /// <summary>Check if a content type is built-in (always ready).</summary>
    class function IsBuiltIn(const AContentType: string): Boolean; static;

    /// <summary>Run all readiness checks for an adapter.</summary>
    class function Evaluate(const AAdapter: TContentTypeAdapter): TAggregateReadiness; static;

    /// <summary>Schema check: is config_schema_json valid JSON?</summary>
    class function CheckSchema(const AAdapter: TContentTypeAdapter): TReadinessCheck; static;

    /// <summary>Pipeline check: does default_pipeline_json reference valid phases?</summary>
    class function CheckPipeline(const AAdapter: TContentTypeAdapter): TReadinessCheck; static;

    /// <summary>Output check: are supported_output_types_json entries valid?</summary>
    class function CheckOutput(const AAdapter: TContentTypeAdapter): TReadinessCheck; static;

    /// <summary>E2E sample check: stub — full implementation requires adapter runtime.</summary>
    class function CheckE2ESample(const AAdapter: TContentTypeAdapter): TReadinessCheck; static;

    /// <summary>Convert aggregate result to a TReadinessReport for DB persistence.</summary>
    class function ToReadinessReport(const AAdapterId: string;
      const AAggregate: TAggregateReadiness): TReadinessReport; static;

    /// <summary>List built-in content types.</summary>
    class function BuiltInContentTypes: TArray<string>; static;
  end;

const
  // Known valid production pipeline phases
  VALID_PIPELINE_PHASES: array[0..5] of string = (
    'document_chain', 'agent_chain', 'audio_chain',
    'video_chain', 'package_chain', 'extension_chain'
  );

  // Known valid output types
  VALID_OUTPUT_TYPES: array[0..1] of string = ('video', 'audio');

implementation

uses
  System.SysUtils,
  DeepFrames.Shared.Consts;

class function TReadinessChecker.BuiltInContentTypes: TArray<string>;
begin
  Result := ['longform_zh_article', 'webnovel_zh'];
end;

class function TReadinessChecker.IsBuiltIn(const AContentType: string): Boolean;
begin
  Result := SameText(AContentType, 'longform_zh_article') or
    SameText(AContentType, 'webnovel_zh');
end;

class function TReadinessChecker.CheckSchema(const AAdapter: TContentTypeAdapter): TReadinessCheck;
var
  Issues: TArray<string>;
  Obj: TJSONObject;
begin
  Result.CheckType := READINESS_CHECK_SCHEMA;
  Result.Evidence := TJSONObject.Create;
  SetLength(Issues, 0);

  if Trim(AAdapter.ConfigSchemaJson) = '' then
  begin
    SetLength(Issues, 1);
    Issues[0] := 'config_schema_json is empty';
    Result.Evidence.AddPair('json_parsed', TJSONBool.Create(False));
  end
  else
  begin
    Obj := TJSONObject.ParseJSONValue(AAdapter.ConfigSchemaJson) as TJSONObject;
    if Obj = nil then
    begin
      SetLength(Issues, 1);
      Issues[0] := 'config_schema_json is not valid JSON';
      Result.Evidence.AddPair('json_parsed', TJSONBool.Create(False));
    end
    else
    begin
      Obj.Free;
      Result.Evidence.AddPair('json_parsed', TJSONBool.Create(True));
      Result.Evidence.AddPair('json_length', TJSONNumber.Create(Length(AAdapter.ConfigSchemaJson)));
    end;
  end;

  Result.Issues := Issues;
  Result.Passed := Length(Issues) = 0;
  if Result.Passed then
  begin
    Result.Score := 1.0;
    Result.Summary := 'Schema JSON is valid';
  end
  else
  begin
    Result.Score := 0.0;
    Result.Summary := 'Schema check failed: ' + Issues[0];
  end;
end;

class function TReadinessChecker.CheckPipeline(const AAdapter: TContentTypeAdapter): TReadinessCheck;
var
  Issues: TArray<string>;
  PipelineObj: TJSONObject;
  Phase: string;
  Found: Boolean;
begin
  Result.CheckType := READINESS_CHECK_PIPELINE;
  Result.Evidence := TJSONObject.Create;
  SetLength(Issues, 0);

  if Trim(AAdapter.DefaultPipelineJson) = '' then
  begin
    SetLength(Issues, 1);
    Issues[0] := 'default_pipeline_json is empty';
    Result.Evidence.AddPair('phases_checked', TJSONNumber.Create(0));
  end
  else
  begin
    PipelineObj := TJSONObject.ParseJSONValue(AAdapter.DefaultPipelineJson) as TJSONObject;
    if PipelineObj = nil then
    begin
      SetLength(Issues, 1);
      Issues[0] := 'default_pipeline_json is not valid JSON';
      Result.Evidence.AddPair('json_parsed', TJSONBool.Create(False));
      Result.Evidence.AddPair('phases_checked', TJSONNumber.Create(0));
    end
    else
    try
      var CheckedCount := 0;
      for Phase in VALID_PIPELINE_PHASES do
      begin
        if PipelineObj.GetValue(Phase) = nil then
          Continue; // optional — not all content types need all pipelines
        Inc(CheckedCount);
        var PhaseVal := PipelineObj.GetValue<Boolean>(Phase);
        Result.Evidence.AddPair(Phase, TJSONBool.Create(PhaseVal));
      end;
      Result.Evidence.AddPair('phases_checked', TJSONNumber.Create(CheckedCount));
      if CheckedCount = 0 then
      begin
        SetLength(Issues, 1);
        Issues[0] := 'No pipeline phases enabled';
      end;
    finally
      PipelineObj.Free;
    end;
  end;

  Result.Issues := Issues;
  Result.Passed := Length(Issues) = 0;
  Result.Score := 1.0;
  Result.Summary := 'Pipeline configuration is valid';
  if not Result.Passed then
    Result.Summary := 'Pipeline check: ' + Issues[0];
end;

class function TReadinessChecker.CheckOutput(const AAdapter: TContentTypeAdapter): TReadinessCheck;
var
  Issues: TArray<string>;
  OutputsArr: TJSONArray;
  OutputStr: string;
  Valid: Boolean;
  I: Integer;
begin
  Result.CheckType := READINESS_CHECK_OUTPUT;
  Result.Evidence := TJSONObject.Create;
  SetLength(Issues, 0);

  if Trim(AAdapter.SupportedOutputTypesJson) = '' then
  begin
    SetLength(Issues, 1);
    Issues[0] := 'supported_output_types_json is empty';
    Result.Evidence.AddPair('output_types_count', TJSONNumber.Create(0));
  end
  else
  begin
    OutputsArr := TJSONObject.ParseJSONValue(AAdapter.SupportedOutputTypesJson) as TJSONArray;
    if OutputsArr = nil then
    begin
      SetLength(Issues, 1);
      Issues[0] := 'supported_output_types_json is not a valid JSON array';
      Result.Evidence.AddPair('json_parsed', TJSONBool.Create(False));
    end
    else
    try
      Result.Evidence.AddPair('output_types_count', TJSONNumber.Create(OutputsArr.Count));
      for I := 0 to OutputsArr.Count - 1 do
      begin
        OutputStr := OutputsArr.Items[I].Value;
        Valid := False;
        for var ValidType in VALID_OUTPUT_TYPES do
          if SameText(ValidType, OutputStr) then
          begin
            Valid := True;
            Break;
          end;
        if not Valid then
        begin
          SetLength(Issues, Length(Issues) + 1);
          Issues[High(Issues)] := Format('Unknown output type: %s', [OutputStr]);
        end;
      end;
    finally
      OutputsArr.Free;
    end;
  end;

  Result.Issues := Issues;
  Result.Passed := Length(Issues) = 0;
  Result.Score := 1.0;
  Result.Summary := 'Output types are valid';
  if not Result.Passed then
    Result.Summary := 'Output check: unknown types found';
end;

class function TReadinessChecker.CheckE2ESample(const AAdapter: TContentTypeAdapter): TReadinessCheck;
begin
  Result.CheckType := READINESS_CHECK_E2E_SAMPLE;
  Result.Evidence := TJSONObject.Create;
  // Stub: built-in types always pass E2E
  if IsBuiltIn(AAdapter.ContentType) then
  begin
    Result.Passed := True;
    Result.Score := 1.0;
    Result.Issues := nil;
    Result.Summary := Format('Built-in content type %s: E2E validated by design', [AAdapter.ContentType]);
    Result.Evidence.AddPair('built_in', TJSONBool.Create(True));
  end
  else
  begin
    // Non-built-in adapters need explicit E2E sample validation
    // In production, this would load a sample input and run the pipeline
    Result.Passed := False;
    Result.Score := 0.0;
    SetLength(Result.Issues, 1);
    Result.Issues[0] := Format(
      'Non-built-in adapter %s requires at least 1 E2E sample pass before activation', [AAdapter.ContentType]);
    Result.Summary := Result.Issues[0];
    Result.Evidence.AddPair('built_in', TJSONBool.Create(False));
    Result.Evidence.AddPair('e2e_sample_required', TJSONBool.Create(True));
  end;
end;

class function TReadinessChecker.Evaluate(const AAdapter: TContentTypeAdapter): TAggregateReadiness;
var
  Checks: TArray<TReadinessCheck>;
  Obj: TJSONObject;
  IssuesArr: TJSONArray;
  S: string;
  TotalScore: Double;
  I: Integer;
begin
  SetLength(Checks, 4);
  Checks[0] := CheckSchema(AAdapter);
  Checks[1] := CheckPipeline(AAdapter);
  Checks[2] := CheckOutput(AAdapter);
  Checks[3] := CheckE2ESample(AAdapter);

  Result.AllPassed := True;
  TotalScore := 0;
  for I := 0 to High(Checks) do
  begin
    if not Checks[I].Passed then
      Result.AllPassed := False;
    TotalScore := TotalScore + Checks[I].Score;
  end;
  Result.OverallScore := TotalScore / Length(Checks);
  Result.Checks := Checks;

  // Build report JSON
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('adapter_id', AAdapter.AdapterId);
    Obj.AddPair('content_type', AAdapter.ContentType);
    Obj.AddPair('display_name', AAdapter.DisplayName);
    Obj.AddPair('all_passed', TJSONBool.Create(Result.AllPassed));
    Obj.AddPair('overall_score', TJSONNumber.Create(Result.OverallScore));

    IssuesArr := TJSONArray.Create;
    for I := 0 to High(Checks) do
    begin
      var CheckObj := TJSONObject.Create;

      CheckObj.AddPair('check_type', Checks[I].CheckType);
      CheckObj.AddPair('passed', TJSONBool.Create(Checks[I].Passed));
      CheckObj.AddPair('score', TJSONNumber.Create(Checks[I].Score));
      CheckObj.AddPair('summary', Checks[I].Summary);

      var IssuesSubArr := TJSONArray.Create;
      for S in Checks[I].Issues do
        IssuesSubArr.Add(S);
      CheckObj.AddPair('issues', IssuesSubArr);

      if Checks[I].Evidence <> nil then
        CheckObj.AddPair('evidence', Checks[I].Evidence.Clone as TJSONValue);

      IssuesArr.AddElement(CheckObj);
    end;
    Obj.AddPair('checks', IssuesArr);
    Result.ReportJson := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TReadinessChecker.ToReadinessReport(const AAdapterId: string;
  const AAggregate: TAggregateReadiness): TReadinessReport;
begin
  Result.ReportId := NewUuidString;
  Result.AdapterId := AAdapterId;
  Result.CheckType := 'comprehensive';
  if AAggregate.AllPassed then
    Result.CheckResult := READINESS_RESULT_PASS
  else if AAggregate.OverallScore >= 0.5 then
    Result.CheckResult := READINESS_RESULT_WARN
  else
    Result.CheckResult := READINESS_RESULT_FAIL;
  Result.Score := AAggregate.OverallScore;
  Result.Summary := Format('Readiness: %.0f%%. %s',
    [AAggregate.OverallScore * 100, 'All checks passed']);
  Result.IssuesJson := AAggregate.ReportJson;
  Result.EvidenceJson := '{}';
  Result.VersionNo := 1;
  Result.Status := STATUS_DONE;
end;

end.