unit UniFlow.Workflow.Context;
(*
  UniFlow Workflow Context
  ========================
  工作流执行上下文管理，包括：
  - 变量作用域管理（global/workflow/step/input/output�?
  - 变量引用解析（{{ vars.xxx }} 语法�?
  - 条件表达式求�?
  
  参�? 05.03.API-UniFlow-Workflow定义规范-v1.0.md �?�?
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.RegularExpressions, System.Variants,
  UniFlow.Workflow.Definition,
  DeepBase.Exceptions;

type
  // ============================================================================
  // 变量作用�?
  // ============================================================================
  
  TVariableScope = (
    vsGlobal,     // 全局变量（跨 Workflow�?
    vsWorkflow,   // Workflow 级变�?
    vsStep,       // 步骤级变�?
    vsInput,      // 输入变量
    vsOutput      // 输出变量
  );
  
  // ============================================================================
  // 变量值包�?
  // ============================================================================
  
  TVariableValue = class
  private
    FValueType: string;
    FStringValue: string;
    FIntValue: Int64;
    FFloatValue: Double;
    FBoolValue: Boolean;
    FJsonValue: TJSONValue;
    FIsNull: Boolean;
  public
    constructor Create; overload;
    constructor Create(const AValue: string); overload;
    constructor Create(AValue: Int64); overload;
    constructor Create(AValue: Double); overload;
    constructor Create(AValue: Boolean); overload;
    constructor Create(AValue: TJSONValue); overload;
    destructor Destroy; override;
    
    class function Null: TVariableValue;
    
    function AsString: string;
    function AsInteger: Int64;
    function AsFloat: Double;
    function AsBoolean: Boolean;
    function AsJSON: TJSONValue;
    function ToJSON: TJSONValue;
    
    function Clone: TVariableValue;
    function IsEmpty: Boolean;
    
    property ValueType: string read FValueType;
    property IsNull: Boolean read FIsNull;
  end;
  
  // ============================================================================
  // 作用域栈�?
  // ============================================================================
  
  TScopeFrame = class
  private
    FScope: TVariableScope;
    FName: string;
    FVariables: TObjectDictionary<string, TVariableValue>;
  public
    constructor Create(AScope: TVariableScope; const AName: string);
    destructor Destroy; override;
    
    procedure SetVariable(const AName: string; AValue: TVariableValue);
    function GetVariable(const AName: string): TVariableValue;
    function HasVariable(const AName: string): Boolean;
    procedure DeleteVariable(const AName: string);
    function GetAllVariables: TDictionary<string, TVariableValue>;
    
    property Scope: TVariableScope read FScope;
    property Name: string read FName;
  end;
  
  // ============================================================================
  // Workflow 上下�?
  // ============================================================================
  
  TWorkflowContext = class
  private
    FWorkflowId: string;
    FInstanceId: string;
    FCorrelationId: string;
    FUserId: string;
    
    FScopeStack: TObjectList<TScopeFrame>;
    FStepOutputs: TObjectDictionary<string, TJSONValue>;  // stepId -> output
    
    function GetCurrentScope: TScopeFrame;
    function FindVariableInStack(const APath: string; out AValue: TVariableValue): Boolean;
    function ParseVariablePath(const APath: string; out AScopeName, AVarName: string): Boolean;
  public
    constructor Create(const AWorkflowId, AInstanceId: string);
    destructor Destroy; override;
    
    // 作用域管�?
    procedure PushScope(AScope: TVariableScope; const AName: string);
    procedure PopScope;
    function GetScopeDepth: Integer;
    
    // 变量操作
    procedure SetVariable(const AName: string; AValue: TVariableValue); overload;
    procedure SetVariable(const AName: string; const AValue: string); overload;
    procedure SetVariable(const AName: string; AValue: Int64); overload;
    procedure SetVariable(const AName: string; AValue: Double); overload;
    procedure SetVariable(const AName: string; AValue: Boolean); overload;
    procedure SetVariable(const AName: string; AValue: TJSONValue); overload;
    
    function GetVariable(const APath: string): TVariableValue;
    function HasVariable(const APath: string): Boolean;
    
    // 步骤输出
    procedure SetStepOutput(const AStepId: string; AOutput: TJSONValue);
    function GetStepOutput(const AStepId: string): TJSONValue;
    
    // 表达式解�?
    /// <summary>解析字符串中的变量引�?{{ xxx }}</summary>
    function ResolveString(const ATemplate: string): string;
    
    /// <summary>解析并返�?JSON �?/summary>
    function ResolveJSON(const ATemplate: string): TJSONValue;
    
    /// <summary>解析变量路径（如 vars.user.name�?/summary>
    function ResolvePath(const APath: string): TVariableValue;
    
    // 上下文信�?
    property WorkflowId: string read FWorkflowId;
    property InstanceId: string read FInstanceId;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
    property UserId: string read FUserId write FUserId;
    
    // 导出/导入
    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);
    function Clone: TWorkflowContext;
  end;
  
  // ============================================================================
  // 表达式求值器
  // ============================================================================
  
  /// <summary>允许的表达式函数白名�?/summary>
  TExpressionWhitelist = class
  private
    class var FAllowedFunctions: TList<string>;
    class var FAllowedOperators: TList<string>;
    class var FDangerousPatterns: TArray<string>;
    class constructor Create;
    class destructor Destroy;
  public
    class function IsAllowedFunction(const AFuncName: string): Boolean;
    class function IsAllowedOperator(const AOp: string): Boolean;
    class function ContainsDangerousPattern(const AExpr: string): Boolean;
    class procedure AddAllowedFunction(const AFuncName: string);
    class procedure AddAllowedOperator(const AOp: string);
  end;

  TExpressionEvaluator = class
  private
    FContext: TWorkflowContext;
    FSafeMode: Boolean;  // SEC-001: 安全模式启用白名单验�?
    
    function CompareValues(ALeft, ARight: TVariableValue; AOp: TConditionOperator): Boolean;
    function EvaluateCondition(ACond: TConditionExpression): Boolean;
    function ValidateExpression(const AExpr: string): Boolean;  // SEC-001: 表达式白名单验证
  public
    constructor Create(AContext: TWorkflowContext);
    
    /// <summary>求值条件表达式</summary>
    function Evaluate(ACond: TConditionExpression): Boolean; overload;
    
    /// <summary>求值简单表达式字符�?/summary>
    function Evaluate(const AExpr: string): Boolean; overload;
    
    /// <summary>求值并返回�?/summary>
    function EvaluateValue(const AExpr: string): TVariableValue;
    
    /// <summary>检�?match 表达式（�?">= 0.9"�?/summary>
    function MatchExpression(AValue: TVariableValue; const AMatchExpr: string): Boolean;
    
    /// <summary>安全模式 - 启用表达式白名单验证</summary>
    property SafeMode: Boolean read FSafeMode write FSafeMode;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
  function VariableScopeToStr(AScope: TVariableScope): string;
  function StrToVariableScope(const S: string): TVariableScope;

implementation

uses
  System.StrUtils, System.Math;

// ============================================================================
// 辅助函数
// ============================================================================

function VariableScopeToStr(AScope: TVariableScope): string;
begin
  case AScope of
    vsGlobal:   Result := 'global';
    vsWorkflow: Result := 'workflow';
    vsStep:     Result := 'step';
    vsInput:    Result := 'input';
    vsOutput:   Result := 'output';
  else
    Result := 'unknown';
  end;
end;

function StrToVariableScope(const S: string): TVariableScope;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if LowerS = 'global' then Result := vsGlobal
  else if LowerS = 'workflow' then Result := vsWorkflow
  else if LowerS = 'step' then Result := vsStep
  else if LowerS = 'input' then Result := vsInput
  else if LowerS = 'output' then Result := vsOutput
  else
    Result := vsWorkflow;
end;

// ============================================================================
// TVariableValue
// ============================================================================

constructor TVariableValue.Create;
begin
  inherited Create;
  FValueType := 'null';
  FIsNull := True;
end;

constructor TVariableValue.Create(const AValue: string);
begin
  inherited Create;
  FValueType := 'string';
  FStringValue := AValue;
  FIsNull := False;
end;

constructor TVariableValue.Create(AValue: Int64);
begin
  inherited Create;
  FValueType := 'integer';
  FIntValue := AValue;
  FIsNull := False;
end;

constructor TVariableValue.Create(AValue: Double);
begin
  inherited Create;
  FValueType := 'float';
  FFloatValue := AValue;
  FIsNull := False;
end;

constructor TVariableValue.Create(AValue: Boolean);
begin
  inherited Create;
  FValueType := 'boolean';
  FBoolValue := AValue;
  FIsNull := False;
end;

constructor TVariableValue.Create(AValue: TJSONValue);
begin
  inherited Create;
  FValueType := 'json';
  if AValue <> nil then
    FJsonValue := AValue.Clone as TJSONValue
  else
    FJsonValue := nil;
  FIsNull := AValue = nil;
end;

destructor TVariableValue.Destroy;
begin
  FJsonValue.Free;
  inherited;
end;

class function TVariableValue.Null: TVariableValue;
begin
  Result := TVariableValue.Create;
end;

function TVariableValue.AsString: string;
begin
  if FIsNull then
    Exit('');
    
  case FValueType[1] of
    's': Result := FStringValue;
    'i': Result := IntToStr(FIntValue);
    'f': Result := FloatToStr(FFloatValue);
    'b': Result := BoolToStr(FBoolValue, True);
    'j': if FJsonValue <> nil then Result := FJsonValue.ToJSON else Result := '';
  else
    Result := '';
  end;
end;

function TVariableValue.AsInteger: Int64;
begin
  if FIsNull then
    Exit(0);
    
  case FValueType[1] of
    's': Result := StrToInt64Def(FStringValue, 0);
    'i': Result := FIntValue;
    'f': Result := Round(FFloatValue);
    'b': Result := Ord(FBoolValue);
    'j': 
      if FJsonValue is TJSONNumber then
        Result := TJSONNumber(FJsonValue).AsInt64
      else
        Result := 0;
  else
    Result := 0;
  end;
end;

function TVariableValue.AsFloat: Double;
begin
  if FIsNull then
    Exit(0);
    
  case FValueType[1] of
    's': Result := StrToFloatDef(FStringValue, 0);
    'i': Result := FIntValue;
    'f': Result := FFloatValue;
    'b': Result := Ord(FBoolValue);
    'j':
      if FJsonValue is TJSONNumber then
        Result := TJSONNumber(FJsonValue).AsDouble
      else
        Result := 0;
  else
    Result := 0;
  end;
end;

function TVariableValue.AsBoolean: Boolean;
begin
  if FIsNull then
    Exit(False);
    
  case FValueType[1] of
    's': Result := SameText(FStringValue, 'true') or (FStringValue = '1');
    'i': Result := FIntValue <> 0;
    'f': Result := FFloatValue <> 0;
    'b': Result := FBoolValue;
    'j':
      if FJsonValue is TJSONBool then
        Result := TJSONBool(FJsonValue).AsBoolean
      else if FJsonValue is TJSONNumber then
        Result := TJSONNumber(FJsonValue).AsDouble <> 0
      else
        Result := FJsonValue <> nil;
  else
    Result := False;
  end;
end;

function TVariableValue.AsJSON: TJSONValue;
begin
  if FIsNull then
    Exit(TJSONNull.Create);
    
  case FValueType[1] of
    's': Result := TJSONString.Create(FStringValue);
    'i': Result := TJSONNumber.Create(FIntValue);
    'f': Result := TJSONNumber.Create(FFloatValue);
    'b': Result := TJSONBool.Create(FBoolValue);
    'j': 
      if FJsonValue <> nil then
        Result := FJsonValue.Clone as TJSONValue
      else
        Result := TJSONNull.Create;
  else
    Result := TJSONNull.Create;
  end;
end;

function TVariableValue.ToJSON: TJSONValue;
begin
  Result := AsJSON;
end;

function TVariableValue.Clone: TVariableValue;
begin
  if FIsNull then
    Exit(TVariableValue.Null);
    
  case FValueType[1] of
    's': Result := TVariableValue.Create(FStringValue);
    'i': Result := TVariableValue.Create(FIntValue);
    'f': Result := TVariableValue.Create(FFloatValue);
    'b': Result := TVariableValue.Create(FBoolValue);
    'j': Result := TVariableValue.Create(FJsonValue);
  else
    Result := TVariableValue.Null;
  end;
end;

function TVariableValue.IsEmpty: Boolean;
begin
  if FIsNull then
    Exit(True);
    
  case FValueType[1] of
    's': Result := FStringValue = '';
    'j': Result := (FJsonValue = nil) or 
                   (FJsonValue is TJSONNull) or
                   ((FJsonValue is TJSONArray) and (TJSONArray(FJsonValue).Count = 0)) or
                   ((FJsonValue is TJSONObject) and (TJSONObject(FJsonValue).Count = 0));
  else
    Result := False;
  end;
end;

// ============================================================================
// TScopeFrame
// ============================================================================

constructor TScopeFrame.Create(AScope: TVariableScope; const AName: string);
begin
  inherited Create;
  FScope := AScope;
  FName := AName;
  FVariables := TObjectDictionary<string, TVariableValue>.Create([doOwnsValues]);
end;

destructor TScopeFrame.Destroy;
begin
  FVariables.Free;
  inherited;
end;

procedure TScopeFrame.SetVariable(const AName: string; AValue: TVariableValue);
begin
  if FVariables.ContainsKey(AName) then
    FVariables[AName] := AValue
  else
    FVariables.Add(AName, AValue);
end;

function TScopeFrame.GetVariable(const AName: string): TVariableValue;
begin
  if FVariables.TryGetValue(AName, Result) then
    // 返回克隆以避免外部修�?
    Result := Result.Clone
  else
    Result := nil;
end;

function TScopeFrame.HasVariable(const AName: string): Boolean;
begin
  Result := FVariables.ContainsKey(AName);
end;

procedure TScopeFrame.DeleteVariable(const AName: string);
begin
  FVariables.Remove(AName);
end;

function TScopeFrame.GetAllVariables: TDictionary<string, TVariableValue>;
begin
  Result := TDictionary<string, TVariableValue>.Create;
  for var Pair in FVariables do
    Result.Add(Pair.Key, Pair.Value.Clone);
end;

// ============================================================================
// TWorkflowContext
// ============================================================================

constructor TWorkflowContext.Create(const AWorkflowId, AInstanceId: string);
begin
  inherited Create;
  FWorkflowId := AWorkflowId;
  FInstanceId := AInstanceId;
  FCorrelationId := TGUID.NewGuid.ToString;
  
  FScopeStack := TObjectList<TScopeFrame>.Create(True);
  FStepOutputs := TObjectDictionary<string, TJSONValue>.Create([doOwnsValues]);
  
  // 初始化全局�?Workflow 作用�?
  PushScope(vsGlobal, 'global');
  PushScope(vsWorkflow, FWorkflowId);
  PushScope(vsInput, 'input');
end;

destructor TWorkflowContext.Destroy;
begin
  FScopeStack.Free;
  FStepOutputs.Free;
  inherited;
end;

function TWorkflowContext.GetCurrentScope: TScopeFrame;
begin
  if FScopeStack.Count > 0 then
    Result := FScopeStack[FScopeStack.Count - 1]
  else
    Result := nil;
end;

procedure TWorkflowContext.PushScope(AScope: TVariableScope; const AName: string);
begin
  FScopeStack.Add(TScopeFrame.Create(AScope, AName));
end;

procedure TWorkflowContext.PopScope;
begin
  if FScopeStack.Count > 3 then  // 保留 global, workflow, input
    FScopeStack.Delete(FScopeStack.Count - 1);
end;

function TWorkflowContext.GetScopeDepth: Integer;
begin
  Result := FScopeStack.Count;
end;

procedure TWorkflowContext.SetVariable(const AName: string; AValue: TVariableValue);
var
  CurrentScope: TScopeFrame;
begin
  CurrentScope := GetCurrentScope;
  if CurrentScope <> nil then
    CurrentScope.SetVariable(AName, AValue);
end;

procedure TWorkflowContext.SetVariable(const AName: string; const AValue: string);
begin
  SetVariable(AName, TVariableValue.Create(AValue));
end;

procedure TWorkflowContext.SetVariable(const AName: string; AValue: Int64);
begin
  SetVariable(AName, TVariableValue.Create(AValue));
end;

procedure TWorkflowContext.SetVariable(const AName: string; AValue: Double);
begin
  SetVariable(AName, TVariableValue.Create(AValue));
end;

procedure TWorkflowContext.SetVariable(const AName: string; AValue: Boolean);
begin
  SetVariable(AName, TVariableValue.Create(AValue));
end;

procedure TWorkflowContext.SetVariable(const AName: string; AValue: TJSONValue);
begin
  SetVariable(AName, TVariableValue.Create(AValue));
end;

function TWorkflowContext.ParseVariablePath(const APath: string; out AScopeName, AVarName: string): Boolean;
var
  DotPos: Integer;
begin
  DotPos := Pos('.', APath);
  if DotPos > 0 then
  begin
    AScopeName := Copy(APath, 1, DotPos - 1);
    AVarName := Copy(APath, DotPos + 1, Length(APath));
    Result := True;
  end
  else
  begin
    AScopeName := '';
    AVarName := APath;
    Result := False;
  end;
end;

function TWorkflowContext.FindVariableInStack(const APath: string; out AValue: TVariableValue): Boolean;
var
  ScopeName, VarPath, VarName, SubPath: string;
  I, DotPos: Integer;
  Frame: TScopeFrame;
  TempValue: TVariableValue;
  JsonVal: TJSONValue;
  JsonObj: TJSONObject;
begin
  Result := False;
  AValue := nil;
  
  // 解析路径
  ParseVariablePath(APath, ScopeName, VarPath);
  
  // 特殊作用域处�?
  if ScopeName = 'input' then
  begin
    // �?input 作用域查�?
    for I := FScopeStack.Count - 1 downto 0 do
    begin
      Frame := FScopeStack[I];
      if Frame.Scope = vsInput then
      begin
        // 解析嵌套路径
        DotPos := Pos('.', VarPath);
        if DotPos > 0 then
        begin
          VarName := Copy(VarPath, 1, DotPos - 1);
          SubPath := Copy(VarPath, DotPos + 1, Length(VarPath));
        end
        else
        begin
          VarName := VarPath;
          SubPath := '';
        end;
        
        TempValue := Frame.GetVariable(VarName);
        if TempValue <> nil then
        begin
          if SubPath = '' then
          begin
            AValue := TempValue;
            Exit(True);
          end
          else
          begin
            // 解析 JSON 路径
            JsonVal := TempValue.AsJSON;
            try
              if JsonVal is TJSONObject then
              begin
                JsonObj := TJSONObject(JsonVal);
                if JsonObj.TryGetValue(SubPath, JsonVal) then
                begin
                  AValue := TVariableValue.Create(JsonVal);
                  Exit(True);
                end;
              end;
            finally
              JsonVal.Free;
            end;
            TempValue.Free;
          end;
        end;
        Break;
      end;
    end;
  end
  else if ScopeName = 'vars' then
  begin
    // 从当前作用域向上查找
    for I := FScopeStack.Count - 1 downto 0 do
    begin
      Frame := FScopeStack[I];
      if Frame.Scope in [vsWorkflow, vsStep] then
      begin
        // 解析嵌套路径
        DotPos := Pos('.', VarPath);
        if DotPos > 0 then
        begin
          VarName := Copy(VarPath, 1, DotPos - 1);
          SubPath := Copy(VarPath, DotPos + 1, Length(VarPath));
        end
        else
        begin
          VarName := VarPath;
          SubPath := '';
        end;
        
        TempValue := Frame.GetVariable(VarName);
        if TempValue <> nil then
        begin
          if SubPath = '' then
          begin
            AValue := TempValue;
            Exit(True);
          end
          else
          begin
            // 解析 JSON 路径
            JsonVal := TempValue.AsJSON;
            try
              if JsonVal is TJSONObject then
              begin
                JsonObj := TJSONObject(JsonVal);
                // 递归解析路径
                while SubPath <> '' do
                begin
                  DotPos := Pos('.', SubPath);
                  if DotPos > 0 then
                  begin
                    VarName := Copy(SubPath, 1, DotPos - 1);
                    SubPath := Copy(SubPath, DotPos + 1, Length(SubPath));
                  end
                  else
                  begin
                    VarName := SubPath;
                    SubPath := '';
                  end;
                  
                  if not JsonObj.TryGetValue(VarName, JsonVal) then
                    Break;
                    
                  if SubPath <> '' then
                  begin
                    if JsonVal is TJSONObject then
                      JsonObj := TJSONObject(JsonVal)
                    else
                      Break;
                  end;
                end;
                
                if SubPath = '' then
                begin
                  AValue := TVariableValue.Create(JsonVal);
                  Exit(True);
                end;
              end;
            finally
              JsonVal.Free;
            end;
            TempValue.Free;
          end;
        end;
      end;
    end;
  end
  else if ScopeName = 'steps' then
  begin
    // 从步骤输出查�?
    DotPos := Pos('.', VarPath);
    if DotPos > 0 then
    begin
      VarName := Copy(VarPath, 1, DotPos - 1);  // stepId
      SubPath := Copy(VarPath, DotPos + 1, Length(VarPath));  // output path
    end
    else
    begin
      VarName := VarPath;
      SubPath := '';
    end;
    
    if FStepOutputs.TryGetValue(VarName, JsonVal) then
    begin
      if SubPath = '' then
      begin
        AValue := TVariableValue.Create(JsonVal);
        Exit(True);
      end
      else if JsonVal is TJSONObject then
      begin
        JsonObj := TJSONObject(JsonVal);
        if JsonObj.TryGetValue(SubPath, JsonVal) then
        begin
          AValue := TVariableValue.Create(JsonVal);
          Exit(True);
        end;
      end;
    end;
  end
  else if ScopeName = 'ctx' then
  begin
    // 上下文变�?
    if VarPath = 'workflowId' then
      AValue := TVariableValue.Create(FWorkflowId)
    else if VarPath = 'instanceId' then
      AValue := TVariableValue.Create(FInstanceId)
    else if VarPath = 'correlationId' then
      AValue := TVariableValue.Create(FCorrelationId)
    else if (VarPath = 'user.id') or (VarPath = 'userId') then
      AValue := TVariableValue.Create(FUserId);
    
    if AValue <> nil then
      Exit(True);
  end
  else
  begin
    // 直接变量名，从当前作用域向上查找
    for I := FScopeStack.Count - 1 downto 0 do
    begin
      Frame := FScopeStack[I];
      TempValue := Frame.GetVariable(APath);
      if TempValue <> nil then
      begin
        AValue := TempValue;
        Exit(True);
      end;
    end;
  end;
end;

function TWorkflowContext.GetVariable(const APath: string): TVariableValue;
begin
  if not FindVariableInStack(APath, Result) then
    Result := TVariableValue.Null;
end;

function TWorkflowContext.HasVariable(const APath: string): Boolean;
var
  Value: TVariableValue;
begin
  Result := FindVariableInStack(APath, Value);
  if Result then
    Value.Free;
end;

procedure TWorkflowContext.SetStepOutput(const AStepId: string; AOutput: TJSONValue);
begin
  if FStepOutputs.ContainsKey(AStepId) then
    FStepOutputs[AStepId] := AOutput.Clone as TJSONValue
  else
    FStepOutputs.Add(AStepId, AOutput.Clone as TJSONValue);
end;

function TWorkflowContext.GetStepOutput(const AStepId: string): TJSONValue;
begin
  if FStepOutputs.TryGetValue(AStepId, Result) then
    Result := Result.Clone as TJSONValue
  else
    Result := nil;
end;

function TWorkflowContext.ResolveString(const ATemplate: string): string;
var
  Regex: TRegEx;
  Matches: TMatchCollection;
  Match: TMatch;
  VarPath, ResolvedValue: string;
  Value: TVariableValue;
begin
  Result := ATemplate;
  
  // 匹配 {{ xxx }} 模式
  Regex := TRegEx.Create('\{\{\s*(.+?)\s*\}\}');
  Matches := Regex.Matches(ATemplate);
  
  // 从后往前替换，避免位置偏移
  for var I := Matches.Count - 1 downto 0 do
  begin
    Match := Matches[I];
    VarPath := Match.Groups[1].Value;
    
    // 处理过滤器（�?| default('xxx')�?
    var FilterPos := Pos('|', VarPath);
    if FilterPos > 0 then
    begin
      var ActualPath := Trim(Copy(VarPath, 1, FilterPos - 1));
      var FilterExpr := Trim(Copy(VarPath, FilterPos + 1, Length(VarPath)));
      
      Value := ResolvePath(ActualPath);
      try
        if Value.IsNull or Value.IsEmpty then
        begin
          // 处理 default 过滤�?
          if StartsText('default(', FilterExpr) then
          begin
            var DefaultVal := Copy(FilterExpr, 9, Length(FilterExpr) - 9);
            // 去除引号
            if (Length(DefaultVal) >= 2) and CharInSet(DefaultVal[1], ['''', '"']) then
              DefaultVal := Copy(DefaultVal, 2, Length(DefaultVal) - 2);
            ResolvedValue := DefaultVal;
          end
          else
            ResolvedValue := '';
        end
        else
        begin
          ResolvedValue := Value.AsString;
          
          // 应用其他过滤�?
          if FilterExpr = 'upper' then
            ResolvedValue := UpperCase(ResolvedValue)
          else if FilterExpr = 'lower' then
            ResolvedValue := LowerCase(ResolvedValue)
          else if FilterExpr = 'trim' then
            ResolvedValue := Trim(ResolvedValue)
          else if FilterExpr = 'json' then
          begin
            var JsonVal := Value.AsJSON;
            try
              ResolvedValue := JsonVal.ToJSON;
            finally
              JsonVal.Free;
            end;
          end
          else if StartsText('truncate(', FilterExpr) then
          begin
            var LenStr := Copy(FilterExpr, 10, Pos(')', FilterExpr) - 10);
            var MaxLen := StrToIntDef(LenStr, 100);
            if Length(ResolvedValue) > MaxLen then
              ResolvedValue := Copy(ResolvedValue, 1, MaxLen) + '...';
          end;
        end;
      finally
        Value.Free;
      end;
    end
    else
    begin
      Value := ResolvePath(VarPath);
      try
        ResolvedValue := Value.AsString;
      finally
        Value.Free;
      end;
    end;
    
    Result := Copy(Result, 1, Match.Index - 1) + ResolvedValue + 
              Copy(Result, Match.Index + Match.Length, Length(Result));
  end;
end;

function TWorkflowContext.ResolveJSON(const ATemplate: string): TJSONValue;
var
  ResolvedStr: string;
begin
  ResolvedStr := ResolveString(ATemplate);
  
  // 尝试解析�?JSON
  try
    Result := TJSONObject.ParseJSONValue(ResolvedStr);
    if Result = nil then
      Result := TJSONString.Create(ResolvedStr);
  except
    Result := TJSONString.Create(ResolvedStr);
  end;
end;

function TWorkflowContext.ResolvePath(const APath: string): TVariableValue;
begin
  Result := GetVariable(APath);
end;

function TWorkflowContext.ToJSON: TJSONObject;
var
  ScopesArr: TJSONArray;
  Frame: TScopeFrame;
  ScopeObj, VarsObj: TJSONObject;
  OutputsObj: TJSONObject;
  Pair: TPair<string, TVariableValue>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('workflowId', FWorkflowId);
  Result.AddPair('instanceId', FInstanceId);
  Result.AddPair('correlationId', FCorrelationId);
  Result.AddPair('userId', FUserId);
  
  // 作用域栈
  ScopesArr := TJSONArray.Create;
  for Frame in FScopeStack do
  begin
    ScopeObj := TJSONObject.Create;
    ScopeObj.AddPair('scope', VariableScopeToStr(Frame.Scope));
    ScopeObj.AddPair('name', Frame.Name);
    
    VarsObj := TJSONObject.Create;
    var AllVars := Frame.GetAllVariables;
    try
      for Pair in AllVars do
        VarsObj.AddPair(Pair.Key, Pair.Value.ToJSON);
    finally
      for Pair in AllVars do
        Pair.Value.Free;
      AllVars.Free;
    end;
    ScopeObj.AddPair('variables', VarsObj);
    
    ScopesArr.AddElement(ScopeObj);
  end;
  Result.AddPair('scopes', ScopesArr);
  
  // 步骤输出
  OutputsObj := TJSONObject.Create;
  for var StepPair in FStepOutputs do
    OutputsObj.AddPair(StepPair.Key, StepPair.Value.Clone as TJSONValue);
  Result.AddPair('stepOutputs', OutputsObj);
end;

procedure TWorkflowContext.LoadFromJSON(AJson: TJSONObject);
var
  ScopesArr: TJSONArray;
  I, J: Integer;
  ScopeObj, VarsObj: TJSONObject;
  OutputsObj: TJSONObject;
  ScopeName, VarName: string;
  Scope: TVariableScope;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('workflowId', FWorkflowId) then;
  if AJson.TryGetValue<string>('instanceId', FInstanceId) then;
  if AJson.TryGetValue<string>('correlationId', FCorrelationId) then;
  if AJson.TryGetValue<string>('userId', FUserId) then;
  
  // 重建作用域栈
  if AJson.TryGetValue<TJSONArray>('scopes', ScopesArr) then
  begin
    FScopeStack.Clear;
    for I := 0 to ScopesArr.Count - 1 do
    begin
      ScopeObj := ScopesArr.Items[I] as TJSONObject;
      if ScopeObj.TryGetValue<string>('scope', ScopeName) then
        Scope := StrToVariableScope(ScopeName)
      else
        Scope := vsWorkflow;
      
      ScopeObj.TryGetValue<string>('name', VarName);
      PushScope(Scope, VarName);
      
      if ScopeObj.TryGetValue<TJSONObject>('variables', VarsObj) then
      begin
        for J := 0 to VarsObj.Count - 1 do
        begin
          var Pair := VarsObj.Pairs[J];
          SetVariable(Pair.JsonString.Value, TVariableValue.Create(Pair.JsonValue));
        end;
      end;
    end;
  end;
  
  // 加载步骤输出
  if AJson.TryGetValue<TJSONObject>('stepOutputs', OutputsObj) then
  begin
    FStepOutputs.Clear;
    for I := 0 to OutputsObj.Count - 1 do
    begin
      var Pair := OutputsObj.Pairs[I];
      FStepOutputs.Add(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
    end;
  end;
end;

function TWorkflowContext.Clone: TWorkflowContext;
begin
  Result := TWorkflowContext.Create(FWorkflowId, FInstanceId);
  Result.FCorrelationId := FCorrelationId;
  Result.FUserId := FUserId;
  
  // 复制作用�?
  Result.FScopeStack.Clear;
  for var Frame in FScopeStack do
  begin
    Result.PushScope(Frame.Scope, Frame.Name);
    var AllVars := Frame.GetAllVariables;
    try
      for var Pair in AllVars do
        Result.SetVariable(Pair.Key, Pair.Value.Clone);
    finally
      for var Pair in AllVars do
        Pair.Value.Free;
      AllVars.Free;
    end;
  end;
  
  // 复制步骤输出
  for var Pair in FStepOutputs do
    Result.FStepOutputs.Add(Pair.Key, Pair.Value.Clone as TJSONValue);
end;

// ============================================================================
// TExpressionEvaluator
// ============================================================================

// ============================================================================
// TExpressionWhitelist - SEC-001: 表达式白名单
// ============================================================================

class constructor TExpressionWhitelist.Create;
begin
  FAllowedFunctions := TList<string>.Create;
  FAllowedOperators := TList<string>.Create;
  
  // 默认允许的函�?
  FAllowedFunctions.AddRange(['length', 'count', 'sum', 'avg', 'min', 'max',
    'trim', 'upper', 'lower', 'substr', 'concat', 'split', 'join',
    'now', 'today', 'formatdate', 'parsedate',
    'toint', 'tofloat', 'tostr', 'tobool',
    'isnull', 'isempty', 'default', 'coalesce',
    'abs', 'round', 'floor', 'ceil', 'trunc']);
  
  // 默认允许的操作符
  FAllowedOperators.AddRange(['=', '==', '!=', '<>', '<', '>', '<=', '>=',
    '+', '-', '*', '/', 'mod', 'div',
    'and', 'or', 'not', 'in', 'contains', 'startswith', 'endswith', 'matches']);
  
  // 危险模式 - 可能导致注入攻击
  FDangerousPatterns := ['exec(', 'eval(', 'system(', 'shell(', 'cmd(',
    'import ', 'require(', '__', '${', '`', 'script:', 'javascript:',
    'file:', 'http://', 'https://', 'ftp://', 'data:'];
end;

class destructor TExpressionWhitelist.Destroy;
begin
  FAllowedFunctions.Free;
  FAllowedOperators.Free;
end;

class function TExpressionWhitelist.IsAllowedFunction(const AFuncName: string): Boolean;
var
  LowerName: string;
begin
  LowerName := LowerCase(Trim(AFuncName));
  Result := FAllowedFunctions.Contains(LowerName);
end;

class function TExpressionWhitelist.IsAllowedOperator(const AOp: string): Boolean;
var
  LowerOp: string;
begin
  LowerOp := LowerCase(Trim(AOp));
  Result := FAllowedOperators.Contains(LowerOp);
end;

class function TExpressionWhitelist.ContainsDangerousPattern(const AExpr: string): Boolean;
var
  LowerExpr: string;
  Pattern: string;
begin
  Result := False;
  LowerExpr := LowerCase(AExpr);
  
  for Pattern in FDangerousPatterns do
  begin
    if Pos(Pattern, LowerExpr) > 0 then
      Exit(True);
  end;
end;

class procedure TExpressionWhitelist.AddAllowedFunction(const AFuncName: string);
begin
  if not FAllowedFunctions.Contains(LowerCase(AFuncName)) then
    FAllowedFunctions.Add(LowerCase(AFuncName));
end;

class procedure TExpressionWhitelist.AddAllowedOperator(const AOp: string);
begin
  if not FAllowedOperators.Contains(LowerCase(AOp)) then
    FAllowedOperators.Add(LowerCase(AOp));
end;

// ============================================================================
// TExpressionEvaluator
// ============================================================================

constructor TExpressionEvaluator.Create(AContext: TWorkflowContext);
begin
  inherited Create;
  FContext := AContext;
  FSafeMode := True;  // SEC-001: 默认启用安全模式
end;

function TExpressionEvaluator.ValidateExpression(const AExpr: string): Boolean;
begin
  // SEC-001: 白名单验�?
  Result := True;
  
  if not FSafeMode then
    Exit;
  
  // 检查危险模�?
  if TExpressionWhitelist.ContainsDangerousPattern(AExpr) then
    Result := False;
end;

function TExpressionEvaluator.CompareValues(ALeft, ARight: TVariableValue; AOp: TConditionOperator): Boolean;
var
  LeftStr, RightStr: string;
  LeftNum, RightNum: Double;
  LeftBool: Boolean;
begin
  Result := False;
  
  case AOp of
    coEq:
    begin
      if (ALeft.ValueType = 'boolean') or (ARight.ValueType = 'boolean') then
        Result := ALeft.AsBoolean = ARight.AsBoolean
      else if ((ALeft.ValueType = 'integer') or (ALeft.ValueType = 'float')) and 
              ((ARight.ValueType = 'integer') or (ARight.ValueType = 'float')) then
        Result := SameValue(ALeft.AsFloat, ARight.AsFloat)
      else
        Result := ALeft.AsString = ARight.AsString;
    end;
    
    coNe:
      Result := not CompareValues(ALeft, ARight, coEq);
    
    coGt:
    begin
      LeftNum := ALeft.AsFloat;
      RightNum := ARight.AsFloat;
      Result := LeftNum > RightNum;
    end;
    
    coLt:
    begin
      LeftNum := ALeft.AsFloat;
      RightNum := ARight.AsFloat;
      Result := LeftNum < RightNum;
    end;
    
    coGe:
    begin
      LeftNum := ALeft.AsFloat;
      RightNum := ARight.AsFloat;
      Result := LeftNum >= RightNum;
    end;
    
    coLe:
    begin
      LeftNum := ALeft.AsFloat;
      RightNum := ARight.AsFloat;
      Result := LeftNum <= RightNum;
    end;
    
    coContains:
    begin
      LeftStr := ALeft.AsString;
      RightStr := ARight.AsString;
      Result := Pos(RightStr, LeftStr) > 0;
    end;
    
    coStartsWith:
    begin
      LeftStr := ALeft.AsString;
      RightStr := ARight.AsString;
      Result := StartsStr(RightStr, LeftStr);
    end;
    
    coEndsWith:
    begin
      LeftStr := ALeft.AsString;
      RightStr := ARight.AsString;
      Result := EndsStr(RightStr, LeftStr);
    end;
    
    coMatches:
    begin
      LeftStr := ALeft.AsString;
      RightStr := ARight.AsString;
      try
        Result := TRegEx.IsMatch(LeftStr, RightStr);
      except
        Result := False;
      end;
    end;
    
    coIsEmpty:
      Result := ALeft.IsEmpty;
    
    coIsNotEmpty:
      Result := not ALeft.IsEmpty;
    
    coIn:
    begin
      LeftStr := ALeft.AsString;
      var RightJson := ARight.AsJSON;
      try
        if RightJson is TJSONArray then
        begin
          var Arr := TJSONArray(RightJson);
          for var I := 0 to Arr.Count - 1 do
          begin
            if Arr.Items[I].Value = LeftStr then
            begin
              Result := True;
              Break;
            end;
          end;
        end;
      finally
        RightJson.Free;
      end;
    end;
  end;
end;

function TExpressionEvaluator.EvaluateCondition(ACond: TConditionExpression): Boolean;
var
  LeftValue, RightValue: TVariableValue;
  SubCond: TConditionExpression;
begin
  Result := False;
  
  case ACond.Operator of
    coAnd:
    begin
      Result := True;
      for SubCond in ACond.SubConditions do
      begin
        if not EvaluateCondition(SubCond) then
        begin
          Result := False;
          Break;
        end;
      end;
    end;
    
    coOr:
    begin
      Result := False;
      for SubCond in ACond.SubConditions do
      begin
        if EvaluateCondition(SubCond) then
        begin
          Result := True;
          Break;
        end;
      end;
    end;
    
    coNot:
    begin
      if ACond.SubConditions.Count > 0 then
        Result := not EvaluateCondition(ACond.SubConditions[0])
      else
      begin
        LeftValue := EvaluateValue(ACond.LeftExpr);
        try
          Result := not LeftValue.AsBoolean;
        finally
          LeftValue.Free;
        end;
      end;
    end;
    
  else
    // 二元操作�?
    LeftValue := EvaluateValue(ACond.LeftExpr);
    try
      if ACond.Operator in [coIsEmpty, coIsNotEmpty] then
        Result := CompareValues(LeftValue, nil, ACond.Operator)
      else
      begin
        RightValue := EvaluateValue(ACond.RightExpr);
        try
          Result := CompareValues(LeftValue, RightValue, ACond.Operator);
        finally
          RightValue.Free;
        end;
      end;
    finally
      LeftValue.Free;
    end;
  end;
end;

function TExpressionEvaluator.Evaluate(ACond: TConditionExpression): Boolean;
begin
  Result := EvaluateCondition(ACond);
end;

function TExpressionEvaluator.Evaluate(const AExpr: string): Boolean;
var
  ResolvedExpr: string;
  Cond: TConditionExpression;
begin
  // SEC-001: 白名单验�?
  if not ValidateExpression(AExpr) then
    raise EOperationException.Create('Expression validation failed: potentially dangerous expression');
  
  // 先解析变量引�?
  ResolvedExpr := FContext.ResolveString(AExpr);
  
  // 尝试直接作为布尔值解�?
  if SameText(ResolvedExpr, 'true') then
    Exit(True);
  if SameText(ResolvedExpr, 'false') then
    Exit(False);
  
  // 解析为条件表达式
  Cond := TConditionExpression.ParseSimple(ResolvedExpr);
  try
    Result := EvaluateCondition(Cond);
  finally
    Cond.Free;
  end;
end;

function TExpressionEvaluator.EvaluateValue(const AExpr: string): TVariableValue;
var
  ResolvedStr: string;
  IntVal: Int64;
  FloatVal: Double;
begin
  // 检查是否是字面�?
  if (Length(AExpr) >= 2) and CharInSet(AExpr[1], ['''', '"']) and (AExpr[Length(AExpr)] = AExpr[1]) then
  begin
    // 字符串字面量
    Result := TVariableValue.Create(Copy(AExpr, 2, Length(AExpr) - 2));
  end
  else if SameText(AExpr, 'true') then
    Result := TVariableValue.Create(True)
  else if SameText(AExpr, 'false') then
    Result := TVariableValue.Create(False)
  else if SameText(AExpr, 'null') then
    Result := TVariableValue.Null
  else if TryStrToInt64(AExpr, IntVal) then
    Result := TVariableValue.Create(IntVal)
  else if TryStrToFloat(AExpr, FloatVal) then
    Result := TVariableValue.Create(FloatVal)
  else
  begin
    // 尝试作为变量路径解析
    ResolvedStr := FContext.ResolveString('{{ ' + AExpr + ' }}');
    
    // 尝试转换类型
    if TryStrToInt64(ResolvedStr, IntVal) then
      Result := TVariableValue.Create(IntVal)
    else if TryStrToFloat(ResolvedStr, FloatVal) then
      Result := TVariableValue.Create(FloatVal)
    else if SameText(ResolvedStr, 'true') then
      Result := TVariableValue.Create(True)
    else if SameText(ResolvedStr, 'false') then
      Result := TVariableValue.Create(False)
    else
      Result := TVariableValue.Create(ResolvedStr);
  end;
end;

function TExpressionEvaluator.MatchExpression(AValue: TVariableValue; const AMatchExpr: string): Boolean;
var
  ExprTrimmed: string;
  NumValue: Double;
  Threshold: Double;
begin
  Result := False;
  ExprTrimmed := Trim(AMatchExpr);
  NumValue := AValue.AsFloat;
  
  // 解析 match 表达�?
  if StartsStr('>=', ExprTrimmed) then
  begin
    Threshold := StrToFloatDef(Trim(Copy(ExprTrimmed, 3, Length(ExprTrimmed))), 0);
    Result := NumValue >= Threshold;
  end
  else if StartsStr('<=', ExprTrimmed) then
  begin
    Threshold := StrToFloatDef(Trim(Copy(ExprTrimmed, 3, Length(ExprTrimmed))), 0);
    Result := NumValue <= Threshold;
  end
  else if StartsStr('>', ExprTrimmed) then
  begin
    Threshold := StrToFloatDef(Trim(Copy(ExprTrimmed, 2, Length(ExprTrimmed))), 0);
    Result := NumValue > Threshold;
  end
  else if StartsStr('<', ExprTrimmed) then
  begin
    Threshold := StrToFloatDef(Trim(Copy(ExprTrimmed, 2, Length(ExprTrimmed))), 0);
    Result := NumValue < Threshold;
  end
  else if StartsStr('==', ExprTrimmed) or StartsStr('=', ExprTrimmed) then
  begin
    var StartPos := 2;
    if ExprTrimmed[1] = '=' then StartPos := 1;
    if ExprTrimmed[2] = '=' then StartPos := 3;
    var TargetStr := Trim(Copy(ExprTrimmed, StartPos, Length(ExprTrimmed)));
    
    // 尝试数值比�?
    if TryStrToFloat(TargetStr, Threshold) then
      Result := SameValue(NumValue, Threshold)
    else
      Result := AValue.AsString = TargetStr;
  end
  else if StartsStr('!=', ExprTrimmed) or StartsStr('<>', ExprTrimmed) then
  begin
    var TargetStr := Trim(Copy(ExprTrimmed, 3, Length(ExprTrimmed)));
    if TryStrToFloat(TargetStr, Threshold) then
      Result := not SameValue(NumValue, Threshold)
    else
      Result := AValue.AsString <> TargetStr;
  end
  else
  begin
    // 直接值比�?
    Result := AValue.AsString = ExprTrimmed;
  end;
end;

end.
