unit ArtifactOS.Services.QualityGate;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection;

type
  TGateResult = record
    Passed: Boolean;
    GateType: string;
    GateStatus: string;  // PASS / FAIL / FREEZE / CONFLICT
    Score: Double;
    Evidence: string;
    Issues: TArray<string>;
  end;

  TQualityGateService = class
  public
    class function RunESGate(const AArtifactId, AContractJson: string): TGateResult;
    class function RunStructureGate(const AArtifactId: string): TGateResult;
    class function CreateQualityRun(const AArtifactId, AArtifactVersionId, ARunType, AEvidence: string): string;
    class function CreateQualitySnapshot(const AArtifactId, AArtifactVersionId: string; AQualified: Boolean): string;
    class function SealSnapshot(const ASnapshotId: string): string;
  end;

implementation

uses
  FireDAC.Comp.Client, System.JSON;

function InsertId(const DB: TArtifactDB; const SQL: string): string;
var
  Q: TFDQuery;
begin
  Q := DB.Query(SQL);
  try
    Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

class function TQualityGateService.RunESGate(const AArtifactId, AContractJson: string): TGateResult;
var
  DB: TArtifactDB;
  Title, Body: string;
  WordCount: Integer;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Fetch artifact content
    Title := DB.ExecuteScalar('SELECT title FROM artifactos.artifact WHERE id=''' + AArtifactId + '''');
    Body  := DB.ExecuteScalar(
      'SELECT av.assembled_payload->>''body'' FROM artifactos.artifact_version av ' +
      'WHERE av.artifact_id=''' + AArtifactId + ''' ORDER BY av.version_no DESC LIMIT 1');

    Result.GateType := 'es';
    Result.Passed := True;
    Result.Score := 100.0;
    SetLength(Result.Issues, 0);

    // ES-01: word count
    WordCount := Length(Body);
    if WordCount < 50 then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'ES-01: body too short (< 50 chars)';
    end;

    // ES-02: title non-empty
    if Title.Trim.IsEmpty then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'ES-02: title is empty';
    end;

    // ES-06: paragraph count >= 3
    if Body.Split(['\n\n']).Length < 3 then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'ES-06: less than 3 paragraphs';
    end;

    if Result.Passed then
      Result.GateStatus := 'PASS'
    else
      Result.Score := 0.0;

    Result.Evidence := '{"checked_at":"' + DateTimeToStr(Now) + '","rules":["ES-01","ES-02","ES-06"]}';
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.RunStructureGate(const AArtifactId: string): TGateResult;
var
  DB: TArtifactDB;
  SpecId, ReviewStatus, StaleStatus: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result.GateType := 'structure';
    Result.Passed := True;
    Result.GateStatus := 'PASS';
    Result.Score := 100.0;
    SetLength(Result.Issues, 0);

    // Check: artifact can trace to at least a valid case chain
    var CaseCount := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.case_record c ' +
      'JOIN artifactos.studio s ON s.case_id = c.id ' +
      'JOIN artifactos.artifact a ON a.sub_studio_id IN (SELECT id FROM artifactos.sub_studio WHERE studio_id = s.id) ' +
      'WHERE a.id=''' + AArtifactId + ''' AND c.status=''active''');

    if CaseCount = '0' then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FREEZE';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'Structure gate: no active case chain for artifact';
      Result.Evidence := '{"case_chain":"broken"}';
      Exit;
    end;

    // Check: artifact has a sealed version
    var SealedCount := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.artifact_version WHERE artifact_id=''' + AArtifactId + ''' AND seal_status=''sealed''');

    if SealedCount = '0' then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FREEZE';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'Structure gate: no sealed artifact_version';
    end;

    Result.Evidence := '{"case_chain":"valid","sealed_versions":' + SealedCount + '}';
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.CreateQualityRun(const AArtifactId, AArtifactVersionId, ARunType, AEvidence: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO artifactos.quality_run (artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ARunType + ''', ''' + AEvidence + ''', ''completed'', now()) ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.CreateQualitySnapshot(const AArtifactId, AArtifactVersionId: string; AQualified: Boolean): string;
var
  DB: TArtifactDB;
  QualStatus, Readiness: string;
begin
  if AQualified then
  begin
    QualStatus := 'qualified';
    Readiness := 'ready';
  end
  else
  begin
    QualStatus := 'not_qualified';
    Readiness := 'not_ready';
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, publish_readiness, ' +
      'purpose_fit_status, seal_candidate) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + QualStatus + ''', ''' + Readiness + ''', ''pass'', true) ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.SealSnapshot(const ASnapshotId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('UPDATE artifactos.quality_snapshot SET sealed_at=now(), sealed_by=''system:quality_gate'' WHERE id=''' + ASnapshotId + ''' AND sealed_at IS NULL');
    Result := ASnapshotId;
  finally
    DB.Disconnect;
  end;
end;

end.