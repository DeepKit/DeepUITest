unit UniFlow.Diagnostics.TraceExporter;
(*
  UniFlow Diagnostics Trace Exporter
  ==================================
  执行轨迹导出器，支持多种格式输出�?
*)

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.JSON, System.StrUtils,
  UniFlow.Diagnostics;

type
  // ============================================================================
  // 执行快照 - 用于复现问题
  // ============================================================================
  
  TExecutionSnapshot = record
    // 元数�?
    Id: string;
    CapturedAt: TDateTime;
    Version: string;
    
    // 工作流信�?
    WorkflowId: string;
    WorkflowName: string;
    WorkflowVersion: string;
    
    // 追踪信息
    CorrelationId: string;
    
    // 执行状�?
    CurrentStepId: string;
    CurrentStepIndex: Integer;
    ExecutedSteps: TStringArray;
    
    // 数据快照
    Variables: TJSONObject;
    InputData: TJSONObject;
    SessionData: TJSONObject;
    
    // 追踪条目
    TraceEntries: TTraceEntryArray;
    
    // 错误信息（如果有�?
    HasError: Boolean;
    ErrorMessage: string;
    ErrorClass: string;
    
    function ToJSON: TJSONObject;
    class function FromJSON(JSON: TJSONObject): TExecutionSnapshot; static;
    function ToString: string;
  end;

  // ============================================================================
  // 导出格式
  // ============================================================================
  
  TExportFormat = (
    efJSON,       // JSON 格式
    efText,       // 文本格式
    efMarkdown,   // Markdown 格式
    efHTML,       // HTML 报告
    efTimeline    // 时间线格�?
  );

  // ============================================================================
  // 轨迹导出�?
  // ============================================================================
  
  TTraceExporter = class
  private
    function FormatDuration(Ms: Int64): string;
    function GetActionIcon(const Action: string): string;
  public
    // 创建快照
    function CreateSnapshot(
      const WorkflowId, WorkflowName, CorrelationId, CurrentStepId: string;
      const ExecutedSteps: TStringArray;
      Variables, InputData: TJSONObject;
      const TraceEntries: TTraceEntryArray
    ): TExecutionSnapshot;
    
    // 导出快照
    function ExportSnapshot(const Snapshot: TExecutionSnapshot; Format: TExportFormat): string;
    
    // 导出追踪条目
    function ExportTraceEntries(const Entries: TTraceEntryArray; Format: TExportFormat): string;
    
    // 保存到文�?
    procedure SaveSnapshotToFile(const Snapshot: TExecutionSnapshot; const FileName: string);
    function LoadSnapshotFromFile(const FileName: string): TExecutionSnapshot;
    
    // 生成报告
    function GenerateExecutionReport(const Snapshot: TExecutionSnapshot): string;
    function GenerateTimelineReport(const Entries: TTraceEntryArray): string;
    function GeneratePerformanceReport(const Entries: TTraceEntryArray): string;
  end;

// ============================================================================
// 便捷函数
// ============================================================================

function CreateTraceExporter: TTraceExporter;

// 快速导出当前追�?
function QuickExportTrace(Format: TExportFormat = efJSON): string;
function QuickSaveSnapshot(const FileName: string): Boolean;

implementation

// ============================================================================
// TExecutionSnapshot
// ============================================================================

function TExecutionSnapshot.ToJSON: TJSONObject;
var
  StepsArr, TracesArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  
  // 元数�?
  Result.AddPair('id', Id);
  Result.AddPair('capturedAt', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', CapturedAt));
  Result.AddPair('version', Version);
  
  // 工作流信�?
  Result.AddPair('workflowId', WorkflowId);
  Result.AddPair('workflowName', WorkflowName);
  Result.AddPair('workflowVersion', WorkflowVersion);
  
  // 追踪信息
  Result.AddPair('correlationId', CorrelationId);
  
  // 执行状�?
  Result.AddPair('currentStepId', CurrentStepId);
  Result.AddPair('currentStepIndex', TJSONNumber.Create(CurrentStepIndex));
  
  StepsArr := TJSONArray.Create;
  for I := 0 to High(ExecutedSteps) do
    StepsArr.Add(ExecutedSteps[I]);
  Result.AddPair('executedSteps', StepsArr as TJSONValue);
  
  // 数据快照
  if Assigned(Variables) then
    Result.AddPair('variables', Variables.Clone as TJSONObject);
  if Assigned(InputData) then
    Result.AddPair('inputData', InputData.Clone as TJSONObject);
  if Assigned(SessionData) then
    Result.AddPair('sessionData', SessionData.Clone as TJSONObject);
  
  // 追踪条目
  TracesArr := TJSONArray.Create;
  for I := 0 to High(TraceEntries) do
    TracesArr.AddElement(TraceEntries[I].ToJSON);
  Result.AddPair('traceEntries', TracesArr as TJSONValue);
  
  // 错误信息
  Result.AddPair('hasError', TJSONBool.Create(HasError));
  if HasError then
  begin
    Result.AddPair('errorMessage', ErrorMessage);
    Result.AddPair('errorClass', ErrorClass);
  end;
end;

class function TExecutionSnapshot.FromJSON(JSON: TJSONObject): TExecutionSnapshot;

  function GetStr(const Name, Default: string): string;
  var
    V: TJSONValue;
  begin
    V := JSON.FindValue(Name);
    if Assigned(V) then
      Result := V.Value
    else
      Result := Default;
  end;
  
  function GetInt(const Name: string; Default: Integer): Integer;
  var
    V: TJSONValue;
  begin
    V := JSON.FindValue(Name);
    if Assigned(V) and (V is TJSONNumber) then
      Result := (V as TJSONNumber).AsInt
    else
      Result := Default;
  end;
  
  function GetBool(const Name: string; Default: Boolean): Boolean;
  var
    V: TJSONValue;
  begin
    V := JSON.FindValue(Name);
    if Assigned(V) and (V is TJSONBool) then
      Result := (V as TJSONBool).AsBoolean
    else
      Result := Default;
  end;

var
  StepsArr, TracesArr: TJSONArray;
  I: Integer;
  TraceJSON: TJSONObject;
  TraceV: TJSONValue;
begin
  Result.Id := GetStr('id', '');
  Result.CapturedAt := ISO8601ToDate(GetStr('capturedAt', ''));
  Result.Version := GetStr('version', '1.0');
  
  Result.WorkflowId := GetStr('workflowId', '');
  Result.WorkflowName := GetStr('workflowName', '');
  Result.WorkflowVersion := GetStr('workflowVersion', '');
  
  Result.CorrelationId := GetStr('correlationId', '');
  
  Result.CurrentStepId := GetStr('currentStepId', '');
  Result.CurrentStepIndex := GetInt('currentStepIndex', 0);
  
  // 执行步骤
  StepsArr := JSON.FindValue('executedSteps') as TJSONArray;
  if Assigned(StepsArr) then
  begin
    SetLength(Result.ExecutedSteps, StepsArr.Count);
    for I := 0 to StepsArr.Count - 1 do
      Result.ExecutedSteps[I] := StepsArr.Items[I].Value;
  end;
  
  // 数据
  if JSON.FindValue('variables') <> nil then
    Result.Variables := JSON.FindValue('variables').Clone as TJSONObject
  else
    Result.Variables := nil;
    
  if JSON.FindValue('inputData') <> nil then
    Result.InputData := JSON.FindValue('inputData').Clone as TJSONObject
  else
    Result.InputData := nil;
    
  if JSON.FindValue('sessionData') <> nil then
    Result.SessionData := JSON.FindValue('sessionData').Clone as TJSONObject
  else
    Result.SessionData := nil;
  
  // 追踪条目
  TracesArr := JSON.FindValue('traceEntries') as TJSONArray;
  if Assigned(TracesArr) then
  begin
    SetLength(Result.TraceEntries, TracesArr.Count);
    for I := 0 to TracesArr.Count - 1 do
    begin
      TraceJSON := TracesArr.Items[I] as TJSONObject;
      TraceV := TraceJSON.FindValue('timestamp');
      if Assigned(TraceV) then
        Result.TraceEntries[I].Timestamp := ISO8601ToDate(TraceV.Value)
      else
        Result.TraceEntries[I].Timestamp := 0;
      TraceV := TraceJSON.FindValue('correlationId');
      Result.TraceEntries[I].CorrelationId := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('workflowId');
      Result.TraceEntries[I].WorkflowId := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('stepId');
      Result.TraceEntries[I].StepId := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('stepType');
      Result.TraceEntries[I].StepType := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('action');
      Result.TraceEntries[I].Action := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('durationMs');
      if Assigned(TraceV) and (TraceV is TJSONNumber) then
        Result.TraceEntries[I].Duration := (TraceV as TJSONNumber).AsInt64
      else
        Result.TraceEntries[I].Duration := 0;
      TraceV := TraceJSON.FindValue('input');
      Result.TraceEntries[I].InputData := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('output');
      Result.TraceEntries[I].OutputData := IfThen(Assigned(TraceV), TraceV.Value, '');
      TraceV := TraceJSON.FindValue('error');
      Result.TraceEntries[I].ErrorMessage := IfThen(Assigned(TraceV), TraceV.Value, '');
    end;
  end;
  
  // 错误
  Result.HasError := GetBool('hasError', False);
  Result.ErrorMessage := GetStr('errorMessage', '');
  Result.ErrorClass := GetStr('errorClass', '');
end;

function TExecutionSnapshot.ToString: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('╔════════════════════════════════════════════════════════════════╗');
    SB.AppendLine('�?                   EXECUTION SNAPSHOT                          �?);
    SB.AppendLine('╠════════════════════════════════════════════════════════════════╣');
    SB.AppendFormat('�?ID:             %s', [Id]).AppendLine;
    SB.AppendFormat('�?Captured:       %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', CapturedAt)]).AppendLine;
    SB.AppendFormat('�?Correlation:    %s', [CorrelationId]).AppendLine;
    SB.AppendLine('╠════════════════════════════════════════════════════════════════╣');
    SB.AppendFormat('�?Workflow:       %s v%s', [WorkflowName, WorkflowVersion]).AppendLine;
    SB.AppendFormat('�?Current Step:   %s (#%d)', [CurrentStepId, CurrentStepIndex]).AppendLine;
    SB.AppendLine('╠════════════════════════════════════════════════════════════════╣');
    SB.AppendLine('�?Execution Path:');
    for I := 0 to High(ExecutedSteps) do
      SB.AppendFormat('�?  %d. %s', [I + 1, ExecutedSteps[I]]).AppendLine;
    
    if HasError then
    begin
      SB.AppendLine('╠════════════════════════════════════════════════════════════════╣');
      SB.AppendLine('�?�?ERROR:');
      SB.AppendFormat('�?  %s: %s', [ErrorClass, ErrorMessage]).AppendLine;
    end;
    
    SB.AppendLine('╚════════════════════════════════════════════════════════════════╝');
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ============================================================================
// TTraceExporter
// ============================================================================

function TTraceExporter.FormatDuration(Ms: Int64): string;
begin
  if Ms < 1000 then
    Result := Format('%dms', [Ms])
  else if Ms < 60000 then
    Result := Format('%.2fs', [Ms / 1000])
  else
    Result := Format('%dm %ds', [Ms div 60000, (Ms mod 60000) div 1000]);
end;

function TTraceExporter.GetActionIcon(const Action: string): string;
begin
  if Action = 'enter' then
    Result := '�?
  else if Action = 'exit' then
    Result := '�?
  else if Action = 'error' then
    Result := '�?
  else
    Result := '�?;
end;

function TTraceExporter.CreateSnapshot(
  const WorkflowId, WorkflowName, CorrelationId, CurrentStepId: string;
  const ExecutedSteps: TStringArray;
  Variables, InputData: TJSONObject;
  const TraceEntries: TTraceEntryArray
): TExecutionSnapshot;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result.Id := 'SNAP-' + Copy(GUIDToString(G), 2, 8);
  Result.CapturedAt := Now;
  Result.Version := '1.0';
  
  Result.WorkflowId := WorkflowId;
  Result.WorkflowName := WorkflowName;
  Result.WorkflowVersion := '1.0.0';
  
  Result.CorrelationId := CorrelationId;
  
  Result.CurrentStepId := CurrentStepId;
  Result.CurrentStepIndex := Length(ExecutedSteps);
  Result.ExecutedSteps := ExecutedSteps;
  
  if Assigned(Variables) then
    Result.Variables := Variables.Clone as TJSONObject
  else
    Result.Variables := nil;
    
  if Assigned(InputData) then
    Result.InputData := InputData.Clone as TJSONObject
  else
    Result.InputData := nil;
    
  Result.SessionData := nil;
  Result.TraceEntries := TraceEntries;
  Result.HasError := False;
  Result.ErrorMessage := '';
  Result.ErrorClass := '';
end;

function TTraceExporter.ExportSnapshot(const Snapshot: TExecutionSnapshot; 
  Format: TExportFormat): string;
begin
  case Format of
    efJSON:
      Result := Snapshot.ToJSON.Format;
    efText:
      Result := Snapshot.ToString;
    efMarkdown:
      Result := GenerateExecutionReport(Snapshot);
    efHTML:
      Result := GenerateExecutionReport(Snapshot); // TODO: HTML template
    efTimeline:
      Result := GenerateTimelineReport(Snapshot.TraceEntries);
  else
    Result := Snapshot.ToJSON.Format;
  end;
end;

function TTraceExporter.ExportTraceEntries(const Entries: TTraceEntryArray; 
  Format: TExportFormat): string;
var
  SB: TStringBuilder;
  Arr: TJSONArray;
  I: Integer;
begin
  case Format of
    efJSON:
      begin
        Arr := TJSONArray.Create;
        try
          for I := 0 to High(Entries) do
            Arr.AddElement(Entries[I].ToJSON);
          Result := Arr.Format;
        finally
          Arr.Free;
        end;
      end;
    efText:
      begin
        SB := TStringBuilder.Create;
        try
          SB.AppendLine('=== Execution Trace ===');
          SB.AppendLine;
          for I := 0 to High(Entries) do
          begin
            SB.AppendFormat('%s [%s] %s.%s %s',
              [GetActionIcon(Entries[I].Action),
               FormatDateTime('hh:nn:ss.zzz', Entries[I].Timestamp),
               Entries[I].WorkflowId,
               Entries[I].StepId,
               Entries[I].Action]);
            if Entries[I].Duration > 0 then
              SB.AppendFormat(' (%s)', [FormatDuration(Entries[I].Duration)]);
            if Entries[I].ErrorMessage <> '' then
              SB.AppendFormat(' ERROR: %s', [Entries[I].ErrorMessage]);
            SB.AppendLine;
          end;
          Result := SB.ToString;
        finally
          SB.Free;
        end;
      end;
    efTimeline:
      Result := GenerateTimelineReport(Entries);
  else
    Result := '';
  end;
end;

procedure TTraceExporter.SaveSnapshotToFile(const Snapshot: TExecutionSnapshot; 
  const FileName: string);
var
  JSON: TJSONObject;
  SL: TStringList;
begin
  JSON := Snapshot.ToJSON;
  try
    SL := TStringList.Create;
    try
      SL.Text := JSON.Format;
      SL.SaveToFile(FileName);
    finally
      SL.Free;
    end;
  finally
    JSON.Free;
  end;
end;

function TTraceExporter.LoadSnapshotFromFile(const FileName: string): TExecutionSnapshot;
var
  SL: TStringList;
  JSON: TJSONObject;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    JSON := TJSONObject.ParseJSONValue(SL.Text) as TJSONObject;
    try
      Result := TExecutionSnapshot.FromJSON(JSON);
    finally
      JSON.Free;
    end;
  finally
    SL.Free;
  end;
end;

function TTraceExporter.GenerateExecutionReport(const Snapshot: TExecutionSnapshot): string;
var
  SB: TStringBuilder;
  I: Integer;
  TotalDuration: Int64;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Execution Report');
    SB.AppendLine;
    SB.AppendFormat('**Snapshot ID:** `%s`  ', [Snapshot.Id]).AppendLine;
    SB.AppendFormat('**Captured:** %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Snapshot.CapturedAt)]).AppendLine;
    SB.AppendLine;
    
    SB.AppendLine('## Workflow');
    SB.AppendFormat('- **Name:** %s', [Snapshot.WorkflowName]).AppendLine;
    SB.AppendFormat('- **ID:** `%s`', [Snapshot.WorkflowId]).AppendLine;
    SB.AppendFormat('- **Correlation:** `%s`', [Snapshot.CorrelationId]).AppendLine;
    SB.AppendLine;
    
    SB.AppendLine('## Execution Path');
    for I := 0 to High(Snapshot.ExecutedSteps) do
      SB.AppendFormat('%d. `%s`', [I + 1, Snapshot.ExecutedSteps[I]]).AppendLine;
    SB.AppendLine;
    
    if Snapshot.HasError then
    begin
      SB.AppendLine('## ⚠️ Error');
      SB.AppendLine('```');
      SB.AppendFormat('%s: %s', [Snapshot.ErrorClass, Snapshot.ErrorMessage]).AppendLine;
      SB.AppendLine('```');
      SB.AppendLine;
    end;
    
    SB.AppendLine('## Trace Timeline');
    SB.AppendLine;
    TotalDuration := 0;
    for I := 0 to High(Snapshot.TraceEntries) do
    begin
      SB.AppendFormat('- `%s` %s **%s** `%s`',
        [FormatDateTime('hh:nn:ss.zzz', Snapshot.TraceEntries[I].Timestamp),
         GetActionIcon(Snapshot.TraceEntries[I].Action),
         Snapshot.TraceEntries[I].StepId,
         Snapshot.TraceEntries[I].Action]);
      if Snapshot.TraceEntries[I].Duration > 0 then
      begin
        SB.AppendFormat(' (%s)', [FormatDuration(Snapshot.TraceEntries[I].Duration)]);
        TotalDuration := TotalDuration + Snapshot.TraceEntries[I].Duration;
      end;
      SB.AppendLine;
    end;
    SB.AppendLine;
    SB.AppendFormat('**Total Duration:** %s', [FormatDuration(TotalDuration)]).AppendLine;
    
    if Assigned(Snapshot.Variables) then
    begin
      SB.AppendLine;
      SB.AppendLine('## Variables');
      SB.AppendLine('```json');
      SB.AppendLine(Snapshot.Variables.Format);
      SB.AppendLine('```');
    end;
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TTraceExporter.GenerateTimelineReport(const Entries: TTraceEntryArray): string;
var
  SB: TStringBuilder;
  I: Integer;
  PrevTime: TDateTime;
  Gap: Int64;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('┌──────────────────────────────────────────────────────────────�?);
    SB.AppendLine('�?                    EXECUTION TIMELINE                       �?);
    SB.AppendLine('├──────────────────────────────────────────────────────────────�?);
    
    PrevTime := 0;
    for I := 0 to High(Entries) do
    begin
      // 显示时间间隔
      if (PrevTime > 0) and (Entries[I].Timestamp > PrevTime) then
      begin
        Gap := MilliSecondsBetween(Entries[I].Timestamp, PrevTime);
        if Gap > 10 then
          SB.AppendFormat('�?    ... %s ...', [FormatDuration(Gap)]).AppendLine;
      end;
      
      SB.AppendFormat('�?%s %s %-20s %s',
        [FormatDateTime('hh:nn:ss.zzz', Entries[I].Timestamp),
         GetActionIcon(Entries[I].Action),
         Entries[I].StepId,
         Entries[I].Action]);
      
      if Entries[I].Duration > 0 then
        SB.AppendFormat(' [%s]', [FormatDuration(Entries[I].Duration)]);
      
      SB.AppendLine;
      
      if Entries[I].ErrorMessage <> '' then
        SB.AppendFormat('�?    └─ ERROR: %s', [Entries[I].ErrorMessage]).AppendLine;
      
      PrevTime := Entries[I].Timestamp;
    end;
    
    SB.AppendLine('└──────────────────────────────────────────────────────────────�?);
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TTraceExporter.GeneratePerformanceReport(const Entries: TTraceEntryArray): string;
var
  SB: TStringBuilder;
  StepDurations: TStringList;
  I: Integer;
  TotalDuration, MaxDuration: Int64;
  MaxStep: string;
begin
  SB := TStringBuilder.Create;
  StepDurations := TStringList.Create;
  try
    TotalDuration := 0;
    MaxDuration := 0;
    MaxStep := '';
    
    // 收集每个步骤的耗时
    for I := 0 to High(Entries) do
    begin
      if (Entries[I].Action = 'exit') and (Entries[I].Duration > 0) then
      begin
        StepDurations.Values[Entries[I].StepId] := IntToStr(Entries[I].Duration);
        TotalDuration := TotalDuration + Entries[I].Duration;
        
        if Entries[I].Duration > MaxDuration then
        begin
          MaxDuration := Entries[I].Duration;
          MaxStep := Entries[I].StepId;
        end;
      end;
    end;
    
    SB.AppendLine('# Performance Report');
    SB.AppendLine;
    SB.AppendFormat('**Total Duration:** %s', [FormatDuration(TotalDuration)]).AppendLine;
    SB.AppendFormat('**Steps Executed:** %d', [StepDurations.Count]).AppendLine;
    if MaxStep <> '' then
      SB.AppendFormat('**Slowest Step:** %s (%s)', [MaxStep, FormatDuration(MaxDuration)]).AppendLine;
    SB.AppendLine;
    
    SB.AppendLine('## Step Durations');
    SB.AppendLine;
    for I := 0 to StepDurations.Count - 1 do
    begin
      SB.AppendFormat('- `%s`: %s', 
        [StepDurations.Names[I], FormatDuration(StrToInt64(StepDurations.ValueFromIndex[I]))]).AppendLine;
    end;
    
    Result := SB.ToString;
  finally
    StepDurations.Free;
    SB.Free;
  end;
end;

// ============================================================================
// 便捷函数
// ============================================================================

function CreateTraceExporter: TTraceExporter;
begin
  Result := TTraceExporter.Create;
end;

function QuickExportTrace(Format: TExportFormat): string;
var
  Exporter: TTraceExporter;
begin
  Exporter := TTraceExporter.Create;
  try
    Result := Exporter.ExportTraceEntries(Diagnostics.TraceEntries, Format);
  finally
    Exporter.Free;
  end;
end;

function QuickSaveSnapshot(const FileName: string): Boolean;
var
  Exporter: TTraceExporter;
  Snapshot: TExecutionSnapshot;
begin
  Result := False;
  Exporter := TTraceExporter.Create;
  try
    Snapshot := Exporter.CreateSnapshot(
      '', '', Diagnostics.CorrelationId, '',
      nil, nil, nil, Diagnostics.TraceEntries
    );
    Exporter.SaveSnapshotToFile(Snapshot, FileName);
    Result := True;
  finally
    Exporter.Free;
  end;
end;

end.
