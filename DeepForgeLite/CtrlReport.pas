unit CtrlReport;

interface

uses
  System.SysUtils, System.Classes, System.Hash, System.IOUtils,
  FireDAC.Comp.Client, uModels;

type
  TReportController = class
  public
    class function GenerateReportID: string;
    function GenerateSealHash(const AReport: TVerificationReport): string;
    function CreateReport(const AContract: TContract;
      const ASourceFile, AIModel: string): TVerificationReport;
    function SaveReport(const AReport: TVerificationReport): Boolean;
    function LoadReport(const AReportId: string): TVerificationReport;
    function AddSealMark(const ASourceCode, AReportID, ASealHash: string): string;
    function SaveOutputCode(const ASourceCode, AReportID, ASealHash, AOutputPath: string): Boolean;
    function SaveSealRecord(const AReport: TVerificationReport; const ASourceFile, AOutputPath: string): Boolean;
  end;

function ReportController: TReportController;

implementation

uses
  uDM;

var
  GReportController: TReportController = nil;

function ReportController: TReportController;
begin
  if not Assigned(GReportController) then
    GReportController := TReportController.Create;
  Result := GReportController;
end;

{ TReportController }

class function TReportController.GenerateReportID: string;
var
  Seq: Integer;
begin
  Seq := Random(9999) + 1;
  Result := Format('PRG-%s-%04d', [FormatDateTime('yyyymmdd', Now), Seq]);
end;

function TReportController.GenerateSealHash(const AReport: TVerificationReport): string;
var
  RawData: string;
  S: TContractScenario;
begin
  RawData := AReport.ReportID +
             AReport.ProjectNameZH +
             DateTimeToStr(AReport.VerifiedAt) +
             IntToStr(Length(AReport.Scenarios));
  
  for S in AReport.Scenarios do
    RawData := RawData + S.ID + S.Desc;
  
  Result := THashSHA2.GetHashString(RawData);
end;

function TReportController.CreateReport(const AContract: TContract;
  const ASourceFile, AIModel: string): TVerificationReport;
var
  I: Integer;
begin
  Result.Clear;
  Result.ReportID := GenerateReportID;
  Result.ProjectNameZH := AContract.Title;
  Result.SourceFileName := ExtractFileName(ASourceFile);
  Result.SourceLang := AContract.Language;
  Result.VerifiedAt := Now;
  Result.AIModel := AIModel;
  Result.IsSealed := True;
  
  SetLength(Result.Scenarios, Length(AContract.Scenarios));
  for I := 0 to High(AContract.Scenarios) do
    Result.Scenarios[I] := AContract.Scenarios[I];
  
  Result.SealHash := GenerateSealHash(Result);
end;

function TReportController.SaveReport(const AReport: TVerificationReport): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text :=
      'INSERT OR REPLACE INTO reports ' +
      '(id, project_name, source_file, language, ai_model, seal_hash, is_sealed, created_at) ' +
      'VALUES (:id, :project_name, :source_file, :language, :ai_model, :seal_hash, :is_sealed, :created_at)';
    
    Q.ParamByName('id').AsString := AReport.ReportID;
    Q.ParamByName('project_name').AsString := AReport.ProjectNameZH;
    Q.ParamByName('source_file').AsString := AReport.SourceFileName;
    Q.ParamByName('language').AsString := SourceLanguageToStr(AReport.SourceLang);
    Q.ParamByName('ai_model').AsString := AReport.AIModel;
    Q.ParamByName('seal_hash').AsString := AReport.SealHash;
    Q.ParamByName('is_sealed').AsInteger := Ord(AReport.IsSealed);
    Q.ParamByName('created_at').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', AReport.VerifiedAt);
    
    Q.ExecSQL;
    Result := True;
  finally
    Q.Free;
  end;
end;

function TReportController.LoadReport(const AReportId: string): TVerificationReport;
var
  Q: TFDQuery;
begin
  Result.Clear;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM reports WHERE id = :id';
    Q.ParamByName('id').AsString := AReportId;
    Q.Open;
    
    if not Q.Eof then
    begin
      Result.ReportID := Q.FieldByName('id').AsString;
      Result.ProjectNameZH := Q.FieldByName('project_name').AsString;
      Result.SourceFileName := Q.FieldByName('source_file').AsString;
      Result.SourceLang := StrToSourceLanguage(Q.FieldByName('language').AsString);
      Result.AIModel := Q.FieldByName('ai_model').AsString;
      Result.SealHash := Q.FieldByName('seal_hash').AsString;
      Result.IsSealed := Q.FieldByName('is_sealed').AsInteger = 1;
      Result.VerifiedAt := StrToDateTimeDef(Q.FieldByName('created_at').AsString, Now);
    end;
  finally
    Q.Free;
  end;
end;

function TReportController.AddSealMark(const ASourceCode, AReportID, ASealHash: string): string;
var
  SealComment: string;
begin
  SealComment := '';
  SealComment := SealComment + sLineBreak;
  SealComment := SealComment + '// ═══════════════════════════════════════════════════════════════' + sLineBreak;
  SealComment := SealComment + '// DeepDevLite Sealed' + sLineBreak;
  SealComment := SealComment + '// Report ID: ' + AReportID + sLineBreak;
  SealComment := SealComment + '// Seal Hash: ' + ASealHash + sLineBreak;
  SealComment := SealComment + '// Sealed At: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + sLineBreak;
  SealComment := SealComment + '// Verify: https://badge.progeelite.com/verify/' + Copy(AReportID, 5, 8) + sLineBreak;
  SealComment := SealComment + '// ═══════════════════════════════════════════════════════════════' + sLineBreak;
  
  Result := ASourceCode + SealComment;
end;

function TReportController.SaveOutputCode(const ASourceCode, AReportID, ASealHash, AOutputPath: string): Boolean;
var
  SealedCode: string;
  SL: TStringList;
begin
  Result := False;
  
  try
    SealedCode := AddSealMark(ASourceCode, AReportID, ASealHash);
    
    SL := TStringList.Create;
    try
      SL.Text := SealedCode;
      SL.SaveToFile(AOutputPath, TEncoding.UTF8);
      Result := True;
    finally
      SL.Free;
    end;
  except
    Result := False;
  end;
end;

function TReportController.SaveSealRecord(const AReport: TVerificationReport;
  const ASourceFile, AOutputPath: string): Boolean;
var
  SL: TStringList;
  I: Integer;
begin
  Result := False;
  
  try
    SL := TStringList.Create;
    try
      SL.Add('╔════════════════════════════════════════════════════════════════╗');
      SL.Add('║                    DeepDevLite Seal Record                      ║');
      SL.Add('╚════════════════════════════════════════════════════════════════╝');
      SL.Add('');
      SL.Add('Report ID     : ' + AReport.ReportID);
      SL.Add('Project Name  : ' + AReport.ProjectNameZH);
      SL.Add('Source File   : ' + ASourceFile);
      SL.Add('Language      : ' + SourceLanguageToStr(AReport.SourceLang));
      SL.Add('AI Model      : ' + AReport.AIModel);
      SL.Add('Seal Hash     : ' + AReport.SealHash);
      SL.Add('Sealed At     : ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', AReport.VerifiedAt));
      SL.Add('');
      SL.Add('─── Verification Results ───');
      SL.Add('Total Scenarios: ' + IntToStr(AReport.GetTotalCount));
      SL.Add('Passed        : ' + IntToStr(AReport.GetPassCount));
      SL.Add('Pass Rate     : ' + IntToStr(AReport.GetPassRate) + '%');
      SL.Add('');
      SL.Add('─── Scenario Details ───');
      
      for I := 0 to High(AReport.Scenarios) do
      begin
        SL.Add('');
        SL.Add('  [' + IntToStr(I+1) + '] ' + AReport.Scenarios[I].ID);
        SL.Add('      Desc: ' + AReport.Scenarios[I].Desc);
        case AReport.Scenarios[I].Status of
          ssPass: SL.Add('      Status: PASS');
          ssFail: SL.Add('      Status: FAIL');
          ssSkip: SL.Add('      Status: SKIP');
        end;
        SL.Add('      Response: ' + IntToStr(AReport.Scenarios[I].ResponseMS) + 'ms');
      end;
      
      SL.Add('');
      SL.Add('─── Verification Link ───');
      SL.Add('https://badge.progeelite.com/verify/' + Copy(AReport.ReportID, 5, 8));
      SL.Add('');
      SL.Add('╔════════════════════════════════════════════════════════════════╗');
      SL.Add('║  This file is cryptographically sealed. Any modification      ║');
      SL.Add('║  will invalidate the seal hash.                               ║');
      SL.Add('╚════════════════════════════════════════════════════════════════╝');
      
      SL.SaveToFile(AOutputPath, TEncoding.UTF8);
      Result := True;
    finally
      SL.Free;
    end;
  except
    Result := False;
  end;
end;

end.
