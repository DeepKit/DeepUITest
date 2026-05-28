unit CtrlTasks;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Comp.Client, uModels;

type
  TTaskController = class
  public
    class function GenerateID: string;
    function CreateTask(const AContractId, ATitle, ADesc: string): TContractScenario;
    function SaveTask(const ATask: TContractScenario; const AContractId: string): Boolean;
    function LoadTasksByContract(const AContractId: string): TArray<TContractScenario>;
    function UpdateTaskStatus(const ATaskId: string; AStatus: TScenarioStatus): Boolean;
  end;

function TaskController: TTaskController;

implementation

uses
  uDM;

var
  GTaskController: TTaskController = nil;

function TaskController: TTaskController;
begin
  if not Assigned(GTaskController) then
    GTaskController := TTaskController.Create;
  Result := GTaskController;
end;

{ TTaskController }

class function TTaskController.GenerateID: string;
begin
  Result := 'TSK-' + FormatDateTime('yyyymmddhhnnss', Now);
end;

function TTaskController.CreateTask(const AContractId, ATitle, ADesc: string): TContractScenario;
begin
  Result.Clear;
  Result.ID := GenerateID;
  Result.Desc := ATitle;
  Result.Detail := ADesc;
end;

function TTaskController.SaveTask(const ATask: TContractScenario; const AContractId: string): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text :=
      'INSERT OR REPLACE INTO tasks ' +
      '(id, contract_id, title, scenario_id, status, created_at) ' +
      'VALUES (:id, :contract_id, :title, :scenario_id, :status, :created_at)';
    
    Q.ParamByName('id').AsString := ATask.ID;
    Q.ParamByName('contract_id').AsString := AContractId;
    Q.ParamByName('title').AsString := ATask.Desc;
    Q.ParamByName('scenario_id').AsString := ATask.ID;
    Q.ParamByName('status').AsString := 'pending';
    Q.ParamByName('created_at').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    
    Q.ExecSQL;
    Result := True;
  finally
    Q.Free;
  end;
end;

function TTaskController.LoadTasksByContract(const AContractId: string): TArray<TContractScenario>;
var
  Q: TFDQuery;
  Task: TContractScenario;
begin
  SetLength(Result, 0);
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM tasks WHERE contract_id = :contract_id ORDER BY created_at';
    Q.ParamByName('contract_id').AsString := AContractId;
    Q.Open;
    
    while not Q.Eof do
    begin
      Task.Clear;
      Task.ID := Q.FieldByName('id').AsString;
      Task.Desc := Q.FieldByName('title').AsString;
      
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Task;
      
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TTaskController.UpdateTaskStatus(const ATaskId: string; AStatus: TScenarioStatus): Boolean;
var
  Q: TFDQuery;
  StatusStr: string;
begin
  Result := False;
  
  case AStatus of
    ssPass: StatusStr := 'pass';
    ssFail: StatusStr := 'fail';
  else
    StatusStr := 'skip';
  end;
  
  Q := DM.GetNewQuery;
  try
    Q.SQL.Text := 'UPDATE tasks SET status = :status, updated_at = :updated_at WHERE id = :id';
    Q.ParamByName('status').AsString := StatusStr;
    Q.ParamByName('updated_at').AsString := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    Q.ParamByName('id').AsString := ATaskId;
    Q.ExecSQL;
    Result := True;
  finally
    Q.Free;
  end;
end;

end.
