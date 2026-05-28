unit CtrlContracts;

interface

uses
  System.SysUtils, System.Classes, System.JSON, FireDAC.Comp.Client,
  uModels, HelperJson;

type
  TContractController = class
  public
    class function GenerateID: string;
    function CreateContract(const ATitle, APurpose: string;
      ALanguage: TSourceLanguage): TContract;
    function SaveContract(const AContract: TContract): Boolean;
    function LoadContract(const AId: string): TContract;
    function ParseYAMLContract(const YAMLText: string; out AContract: TContract): Boolean;
  end;

function ContractController: TContractController;

implementation

uses
  uDM, System.Hash, System.RegularExpressions;

var
  GContractController: TContractController = nil;

function ContractController: TContractController;
begin
  if not Assigned(GContractController) then
    GContractController := TContractController.Create;
  Result := GContractController;
end;

{ TContractController }

class function TContractController.GenerateID: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'CTR-' + FormatDateTime('yyyymmdd', Now) + '-' +
    Copy(GUIDToString(GUID), 2, 8);
end;

function TContractController.CreateContract(const ATitle, APurpose: string;
  ALanguage: TSourceLanguage): TContract;
begin
  Result.Clear;
  Result.ID := GenerateID;
  Result.Title := ATitle;
  Result.Purpose := APurpose;
  Result.Language := ALanguage;
  Result.CreatedAt := Now;
  Result.IsConfirmed := False;
end;

function TContractController.SaveContract(const AContract: TContract): Boolean;
var
  Q: TFDQuery;
  I: Integer;
  ScenariosJSON: string;
begin
  Result := False;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text :=
      'INSERT OR REPLACE INTO contracts ' +
      '(id, title, language, purpose, status, created_at, confirmed_at) ' +
      'VALUES (:id, :title, :language, :purpose, :status, :created_at, :confirmed_at)';
    
    Q.ParamByName('id').AsString := AContract.ID;
    Q.ParamByName('title').AsString := AContract.Title;
    Q.ParamByName('language').AsString := SourceLanguageToStr(AContract.Language);
    Q.ParamByName('purpose').AsString := AContract.Purpose;
    
    if AContract.IsConfirmed then
      Q.ParamByName('status').AsString := 'confirmed'
    else
      Q.ParamByName('status').AsString := 'draft';
    
    Q.ParamByName('created_at').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', AContract.CreatedAt);
    
    if AContract.ConfirmedAt > 0 then
      Q.ParamByName('confirmed_at').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', AContract.ConfirmedAt)
    else
      Q.ParamByName('confirmed_at').Clear;
    
    Q.ExecSQL;
    Result := True;
  finally
    Q.Free;
  end;
end;

function TContractController.LoadContract(const AId: string): TContract;
var
  Q: TFDQuery;
begin
  Result.Clear;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM contracts WHERE id = :id';
    Q.ParamByName('id').AsString := AId;
    Q.Open;
    
    if not Q.Eof then
    begin
      Result.ID := Q.FieldByName('id').AsString;
      Result.Title := Q.FieldByName('title').AsString;
      Result.Language := StrToSourceLanguage(Q.FieldByName('language').AsString);
      Result.Purpose := Q.FieldByName('purpose').AsString;
      Result.CreatedAt := StrToDateTimeDef(Q.FieldByName('created_at').AsString, Now);
      
      if not Q.FieldByName('confirmed_at').IsNull then
        Result.ConfirmedAt := StrToDateTimeDef(Q.FieldByName('confirmed_at').AsString, 0);
      
      Result.IsConfirmed := Q.FieldByName('status').AsString = 'confirmed';
    end;
  finally
    Q.Free;
  end;
end;

function TContractController.ParseYAMLContract(const YAMLText: string;
  out AContract: TContract): Boolean;
var
  Lines: TStringList;
  Line: string;
  InScenario: Boolean;
  CurScenario: TContractScenario;
  I: Integer;
  
  function ExtractValue(const L: string): string;
  var
    P: Integer;
  begin
    P := Pos(':', L);
    if P > 0 then
    begin
      Result := Trim(Copy(L, P + 1, MaxInt));
      if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
        Result := Copy(Result, 2, Length(Result) - 2);
    end
    else
      Result := '';
  end;
  
begin
  Result := False;
  AContract.Clear;
  
  Lines := TStringList.Create;
  try
    Lines.Text := YAMLText;
    InScenario := False;
    
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      
      if Line.StartsWith('title:') then
        AContract.Title := ExtractValue(Line)
      else if Line.StartsWith('purpose:') then
        AContract.Purpose := ExtractValue(Line)
      else if Line.StartsWith('language:') then
        AContract.Language := StrToSourceLanguage(ExtractValue(Line))
      else if Line.StartsWith('- id:') or Line.StartsWith('-id:') then
      begin
        if InScenario then
        begin
          SetLength(AContract.Scenarios, Length(AContract.Scenarios) + 1);
          AContract.Scenarios[High(AContract.Scenarios)] := CurScenario;
        end;
        
        CurScenario.Clear;
        CurScenario.ID := ExtractValue(Line);
        InScenario := True;
      end
      else if InScenario then
      begin
        if Line.StartsWith('desc:') then
          CurScenario.Desc := ExtractValue(Line)
        else if Line.StartsWith('type:') then
        begin
          var TypeStr := LowerCase(ExtractValue(Line));
          if TypeStr = 'normal' then CurScenario.ScenType := stNormal
          else if TypeStr = 'edge' then CurScenario.ScenType := stEdge
          else if TypeStr = 'error' then CurScenario.ScenType := stError;
        end
        else if Line.StartsWith('input:') then
          CurScenario.Input := ExtractValue(Line)
        else if Line.StartsWith('expected:') then
          CurScenario.Expected := ExtractValue(Line);
      end;
    end;
    
    if InScenario then
    begin
      SetLength(AContract.Scenarios, Length(AContract.Scenarios) + 1);
      AContract.Scenarios[High(AContract.Scenarios)] := CurScenario;
    end;
    
    AContract.CreatedAt := Now;
    AContract.ID := GenerateID;
    
    Result := (AContract.Title <> '') and (Length(AContract.Scenarios) > 0);
  finally
    Lines.Free;
  end;
end;

end.
