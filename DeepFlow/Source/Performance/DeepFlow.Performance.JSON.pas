unit UniFlow.Performance.JSON;
(*
  UniFlow Performance - JSON Optimization
  ========================================
  高性能 JSON 处理模块，提供：
  - 流式解析（大文件支持�?
  - 路径提取优化
  - 解析结果缓存
  - 高效 JSON 构建

  Author: UniFlow Team
  Date: 2025-12-05
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.SyncObjs, System.Hash;

type
  // ============================================================================
  // JSON 流式读取�?
  // ============================================================================

  /// <summary>JSON 解析事件</summary>
  TJSONTokenType = (
    jttNone,
    jttObjectStart,   // {
    jttObjectEnd,     // }
    jttArrayStart,    // [
    jttArrayEnd,      // ]
    jttPropertyName,  // "key":
    jttString,        // "value"
    jttNumber,        // 123, 1.5
    jttBoolean,       // true, false
    jttNull           // null
  );

  /// <summary>JSON Token</summary>
  TJSONToken = record
    TokenType: TJSONTokenType;
    Value: string;
    Path: string;
    Depth: Integer;
    Position: Int64;

    procedure Clear;
    function IsValue: Boolean;
  end;

  /// <summary>流式 JSON 解析回调</summary>
  TJSONTokenCallback = reference to procedure(const AToken: TJSONToken; var AContinue: Boolean);

  /// <summary>流式 JSON 读取�?/summary>
  TJSONStreamReader = class
  private
    FStream: TStream;
    FOwnsStream: Boolean;
    FBuffer: TBytes;
    FBufferSize: Integer;
    FBufferPos: Integer;
    FBufferLen: Integer;
    FPosition: Int64;
    FPathStack: TStack<string>;
    FDepth: Integer;
    FLastPropertyName: string;

    function ReadChar: Char;
    function PeekChar: Char;
    procedure SkipWhitespace;
    function ReadString: string;
    function ReadNumber: string;
    function ReadLiteral(const AExpected: string): Boolean;
    function GetCurrentPath: string;
    function RefillBuffer: Boolean;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean = False; ABufferSize: Integer = 65536);
    destructor Destroy; override;

    /// <summary>解析下一�?Token</summary>
    function ReadToken(out AToken: TJSONToken): Boolean;

    /// <summary>遍历所�?Token</summary>
    procedure ForEach(ACallback: TJSONTokenCallback);

    /// <summary>跳过当前值（对象或数组）</summary>
    procedure SkipValue;

    /// <summary>读取当前值为 JSON</summary>
    function ReadValue: TJSONValue;

    /// <summary>当前位置</summary>
    property Position: Int64 read FPosition;
    property Depth: Integer read FDepth;
  end;

  // ============================================================================
  // JSON Lines 读取�?
  // ============================================================================

  /// <summary>JSON Lines 格式读取�?/summary>
  TJSONLinesReader = class
  private
    FStream: TStream;
    FOwnsStream: Boolean;
    FReader: TStreamReader;
    FLineNumber: Integer;
    FEncoding: TEncoding;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean = False; AEncoding: TEncoding = nil);
    destructor Destroy; override;

    /// <summary>读取下一�?JSON</summary>
    function ReadNext(out AJson: TJSONValue): Boolean;

    /// <summary>读取下一行为对象</summary>
    function ReadNextObject(out AObj: TJSONObject): Boolean;

    /// <summary>遍历所有行</summary>
    procedure ForEach(ACallback: TProc<TJSONValue, Integer>);

    /// <summary>当前行号</summary>
    property LineNumber: Integer read FLineNumber;
  end;

  // ============================================================================
  // JSON 路径提取�?
  // ============================================================================

  /// <summary>JSON 路径段类�?/summary>
  TPathSegmentType = (
    pstProperty,  // .propertyName
    pstIndex,     // [0]
    pstWildcard,  // [*]
    pstRecursive  // ..
  );

  /// <summary>JSON 路径�?/summary>
  TPathSegment = record
    SegmentType: TPathSegmentType;
    Name: string;
    Index: Integer;
  end;

  /// <summary>JSON 路径提取�?/summary>
  TJSONPathExtractor = class
  private
    FPath: string;
    FSegments: TList<TPathSegment>;

    procedure ParsePath;
    function MatchSegment(AValue: TJSONValue; ASegmentIndex: Integer; AResults: TList<TJSONValue>): Boolean;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;

    /// <summary>�?JSON 值提�?/summary>
    function Extract(ARoot: TJSONValue): TJSONValue;

    /// <summary>提取所有匹配项</summary>
    function ExtractAll(ARoot: TJSONValue): TArray<TJSONValue>;

    /// <summary>提取字符串�?/summary>
    function ExtractString(ARoot: TJSONValue; const ADefault: string = ''): string;

    /// <summary>提取整数�?/summary>
    function ExtractInteger(ARoot: TJSONValue; ADefault: Integer = 0): Integer;

    /// <summary>提取布尔�?/summary>
    function ExtractBoolean(ARoot: TJSONValue; ADefault: Boolean = False): Boolean;

    /// <summary>检查路径是否存�?/summary>
    function Exists(ARoot: TJSONValue): Boolean;

    /// <summary>路径字符�?/summary>
    property Path: string read FPath;

    /// <summary>快速提取（静态方法）</summary>
    class function Get(ARoot: TJSONValue; const APath: string): TJSONValue; static;
    class function GetString(ARoot: TJSONValue; const APath: string; const ADefault: string = ''): string; static;
    class function GetInt(ARoot: TJSONValue; const APath: string; ADefault: Integer = 0): Integer; static;
    class function GetBool(ARoot: TJSONValue; const APath: string; ADefault: Boolean = False): Boolean; static;
  end;

  // ============================================================================
  // JSON 解析缓存
  // ============================================================================

  /// <summary>缓存�?/summary>
  TJSONCacheItem = class
  private
    FValue: TJSONValue;
    FHash: string;
    FCreatedAt: TDateTime;
    FLastAccess: TDateTime;
    FAccessCount: Integer;
    FSizeBytes: Integer;
  public
    constructor Create(AValue: TJSONValue; const AHash: string; ASizeBytes: Integer);
    destructor Destroy; override;

    procedure Touch;

    property Value: TJSONValue read FValue;
    property Hash: string read FHash;
    property CreatedAt: TDateTime read FCreatedAt;
    property LastAccess: TDateTime read FLastAccess;
    property AccessCount: Integer read FAccessCount;
    property SizeBytes: Integer read FSizeBytes;
  end;

  /// <summary>JSON 解析结果缓存</summary>
  TJSONCache = class
  private
    FCache: TObjectDictionary<string, TJSONCacheItem>;
    FLock: TCriticalSection;
    FMaxItems: Integer;
    FMaxSizeBytes: Int64;
    FCurrentSizeBytes: Int64;
    FTTLSeconds: Integer;
    FHits: Int64;
    FMisses: Int64;

    function ComputeHash(const AContent: string): string;
    procedure Evict;
    procedure CleanExpired;
  public
    constructor Create(AMaxItems: Integer = 1000; AMaxSizeBytes: Int64 = 100 * 1024 * 1024;
      ATTLSeconds: Integer = 300);
    destructor Destroy; override;

    /// <summary>获取缓存�?JSON（返回克隆）</summary>
    function Get(const AContent: string): TJSONValue;

    /// <summary>添加到缓�?/summary>
    procedure Put(const AContent: string; AValue: TJSONValue);

    /// <summary>解析并缓�?/summary>
    function ParseAndCache(const AContent: string): TJSONValue;

    /// <summary>清空缓存</summary>
    procedure Clear;

    /// <summary>获取统计信息</summary>
    function GetStats: TJSONObject;

    property MaxItems: Integer read FMaxItems write FMaxItems;
    property MaxSizeBytes: Int64 read FMaxSizeBytes write FMaxSizeBytes;
    property TTLSeconds: Integer read FTTLSeconds write FTTLSeconds;
    property HitRate: Double read FHits;
  end;

  // ============================================================================
  // 高效 JSON 构建�?
  // ============================================================================

  /// <summary>JSON 构建器状�?/summary>
  TJSONBuilderState = (
    jbsInitial,
    jbsObject,
    jbsArray,
    jbsValue
  );

  /// <summary>高效 JSON 构建�?/summary>
  TJSONBuilder = class
  private
    FBuffer: TStringBuilder;
    FStateStack: TStack<TJSONBuilderState>;
    FNeedComma: TStack<Boolean>;
    FIndent: Integer;
    FPrettyPrint: Boolean;

    procedure WriteIndent;
    procedure WriteCommaIfNeeded;
    procedure PushState(AState: TJSONBuilderState);
    procedure PopState;
    function GetCurrentState: TJSONBuilderState;
    procedure WriteValue(const AValue: string);
  public
    constructor Create(AInitialCapacity: Integer = 4096; APrettyPrint: Boolean = False);
    destructor Destroy; override;

    /// <summary>开始对�?/summary>
    function BeginObject: TJSONBuilder;

    /// <summary>结束对象</summary>
    function EndObject: TJSONBuilder;

    /// <summary>开始数�?/summary>
    function BeginArray: TJSONBuilder;

    /// <summary>结束数组</summary>
    function EndArray: TJSONBuilder;

    /// <summary>写入属性名</summary>
    function WriteProperty(const AName: string): TJSONBuilder;

    /// <summary>写入字符串�?/summary>
    function WriteString(const AValue: string): TJSONBuilder; overload;
    function WriteString(const AName, AValue: string): TJSONBuilder; overload;

    /// <summary>写入整数�?/summary>
    function WriteInteger(AValue: Int64): TJSONBuilder; overload;
    function WriteInteger(const AName: string; AValue: Int64): TJSONBuilder; overload;

    /// <summary>写入浮点�?/summary>
    function WriteFloat(AValue: Double): TJSONBuilder; overload;
    function WriteFloat(const AName: string; AValue: Double): TJSONBuilder; overload;

    /// <summary>写入布尔�?/summary>
    function WriteBoolean(AValue: Boolean): TJSONBuilder; overload;
    function WriteBoolean(const AName: string; AValue: Boolean): TJSONBuilder; overload;

    /// <summary>写入 null</summary>
    function WriteNull: TJSONBuilder; overload;
    function WriteNull(const AName: string): TJSONBuilder; overload;

    /// <summary>写入原始 JSON</summary>
    function WriteRaw(const AJson: string): TJSONBuilder;

    /// <summary>写入 TJSONValue</summary>
    function WriteJSON(AValue: TJSONValue): TJSONBuilder; overload;
    function WriteJSON(const AName: string; AValue: TJSONValue): TJSONBuilder; overload;

    /// <summary>重置构建�?/summary>
    procedure Reset;

    /// <summary>获取结果字符�?/summary>
    function ToString: string; override;

    /// <summary>获取结果�?TJSONValue</summary>
    function ToJSON: TJSONValue;

    /// <summary>当前长度</summary>
    property Length: Integer read FBuffer.Length;
  end;

  // ============================================================================
  // JSON 工具函数
  // ============================================================================

  /// <summary>快�?JSON 字符串转�?/summary>
  function EscapeJSONString(const S: string): string;

  /// <summary>快�?JSON 字符串反转义</summary>
  function UnescapeJSONString(const S: string): string;

  /// <summary>计算 JSON 值的近似大小（字节）</summary>
  function EstimateJSONSize(AValue: TJSONValue): Integer;

  /// <summary>深度克隆 JSON �?/summary>
  function CloneJSON(AValue: TJSONValue): TJSONValue;

  /// <summary>合并两个 JSON 对象</summary>
  function MergeJSON(ABase, AOverlay: TJSONObject): TJSONObject;

implementation

uses
  System.DateUtils, System.StrUtils, System.Math;

// ============================================================================
// TJSONToken
// ============================================================================

procedure TJSONToken.Clear;
begin
  TokenType := jttNone;
  Value := '';
  Path := '';
  Depth := 0;
  Position := 0;
end;

function TJSONToken.IsValue: Boolean;
begin
  Result := TokenType in [jttString, jttNumber, jttBoolean, jttNull];
end;

// ============================================================================
// TJSONStreamReader
// ============================================================================

constructor TJSONStreamReader.Create(AStream: TStream; AOwnsStream: Boolean; ABufferSize: Integer);
begin
  inherited Create;
  FStream := AStream;
  FOwnsStream := AOwnsStream;
  FBufferSize := ABufferSize;
  SetLength(FBuffer, FBufferSize);
  FBufferPos := 0;
  FBufferLen := 0;
  FPosition := 0;
  FPathStack := TStack<string>.Create;
  FDepth := 0;
  FLastPropertyName := '';
end;

destructor TJSONStreamReader.Destroy;
begin
  FPathStack.Free;
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

function TJSONStreamReader.RefillBuffer: Boolean;
begin
  FBufferLen := FStream.Read(FBuffer[0], FBufferSize);
  FBufferPos := 0;
  Result := FBufferLen > 0;
end;

function TJSONStreamReader.ReadChar: Char;
begin
  if FBufferPos >= FBufferLen then
  begin
    if not RefillBuffer then
    begin
      Result := #0;
      Exit;
    end;
  end;
  Result := Char(FBuffer[FBufferPos]);
  Inc(FBufferPos);
  Inc(FPosition);
end;

function TJSONStreamReader.PeekChar: Char;
begin
  if FBufferPos >= FBufferLen then
  begin
    if not RefillBuffer then
    begin
      Result := #0;
      Exit;
    end;
  end;
  Result := Char(FBuffer[FBufferPos]);
end;

procedure TJSONStreamReader.SkipWhitespace;
var
  C: Char;
begin
  while True do
  begin
    C := PeekChar;
    if C = #0 then
      Exit;
    if not CharInSet(C, [' ', #9, #10, #13]) then
      Exit;
    ReadChar;
  end;
end;

function TJSONStreamReader.ReadString: string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    ReadChar; // Skip opening quote
    while True do
    begin
      C := ReadChar;
      if C = #0 then
        Break;
      if C = '"' then
        Break;
      if C = '\' then
      begin
        C := ReadChar;
        case C of
          '"', '\', '/': SB.Append(C);
          'b': SB.Append(#8);
          'f': SB.Append(#12);
          'n': SB.Append(#10);
          'r': SB.Append(#13);
          't': SB.Append(#9);
          'u': begin
            // Unicode escape - parse 4 hex digits
            var HexStr := '';
            HexStr := HexStr + ReadChar;
            HexStr := HexStr + ReadChar;
            HexStr := HexStr + ReadChar;
            HexStr := HexStr + ReadChar;
            var CodePoint: Integer;
            if TryStrToInt('$' + HexStr, CodePoint) then
              SB.Append(Char(CodePoint))
            else
              SB.Append('\u' + HexStr); // Keep original if invalid
          end;
        end;
      end
      else
        SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TJSONStreamReader.ReadNumber: string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    while True do
    begin
      C := PeekChar;
      if C = #0 then
        Break;
      if not CharInSet(C, ['0'..'9', '-', '+', '.', 'e', 'E']) then
        Break;
      SB.Append(ReadChar);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TJSONStreamReader.ReadLiteral(const AExpected: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(AExpected) do
  begin
    if ReadChar <> AExpected[i] then
    begin
      Result := False;
      Exit;
    end;
  end;
  Result := True;
end;

function TJSONStreamReader.GetCurrentPath: string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  SetLength(Parts, FPathStack.Count);
  i := FPathStack.Count - 1;
  for var S in FPathStack do
  begin
    Parts[i] := S;
    Dec(i);
  end;
  Result := '$' + string.Join('', Parts);
end;

function TJSONStreamReader.ReadToken(out AToken: TJSONToken): Boolean;
var
  C: Char;
begin
  AToken.Clear;
  SkipWhitespace;

  C := PeekChar;
  if C = #0 then
  begin
    Result := False;
    Exit;
  end;

  AToken.Position := FPosition;
  AToken.Depth := FDepth;
  AToken.Path := GetCurrentPath;

  case C of
    '{':
      begin
        ReadChar;
        AToken.TokenType := jttObjectStart;
        Inc(FDepth);
        if FLastPropertyName <> '' then
        begin
          FPathStack.Push('.' + FLastPropertyName);
          FLastPropertyName := '';
        end;
      end;
    '}':
      begin
        ReadChar;
        AToken.TokenType := jttObjectEnd;
        Dec(FDepth);
        if FPathStack.Count > 0 then
          FPathStack.Pop;
      end;
    '[':
      begin
        ReadChar;
        AToken.TokenType := jttArrayStart;
        Inc(FDepth);
        if FLastPropertyName <> '' then
        begin
          FPathStack.Push('.' + FLastPropertyName);
          FLastPropertyName := '';
        end;
        FPathStack.Push('[0]');
      end;
    ']':
      begin
        ReadChar;
        AToken.TokenType := jttArrayEnd;
        Dec(FDepth);
        if FPathStack.Count > 0 then
          FPathStack.Pop; // Remove index
        if FPathStack.Count > 0 then
          FPathStack.Pop; // Remove array name
      end;
    '"':
      begin
        AToken.Value := ReadString;
        SkipWhitespace;
        if PeekChar = ':' then
        begin
          ReadChar;
          AToken.TokenType := jttPropertyName;
          FLastPropertyName := AToken.Value;
        end
        else
          AToken.TokenType := jttString;
      end;
    ',':
      begin
        ReadChar;
        // Check if we're in an array to update index
        if (FPathStack.Count > 0) and FPathStack.Peek.StartsWith('[') then
        begin
          var IdxStr := FPathStack.Pop;
          var Idx := StrToIntDef(Copy(IdxStr, 2, Length(IdxStr) - 2), 0);
          FPathStack.Push('[' + IntToStr(Idx + 1) + ']');
        end;
        Result := ReadToken(AToken); // Read next token
        Exit;
      end;
    '-', '0'..'9':
      begin
        AToken.Value := ReadNumber;
        AToken.TokenType := jttNumber;
      end;
    't':
      begin
        if ReadLiteral('true') then
        begin
          AToken.Value := 'true';
          AToken.TokenType := jttBoolean;
        end;
      end;
    'f':
      begin
        if ReadLiteral('false') then
        begin
          AToken.Value := 'false';
          AToken.TokenType := jttBoolean;
        end;
      end;
    'n':
      begin
        if ReadLiteral('null') then
        begin
          AToken.Value := 'null';
          AToken.TokenType := jttNull;
        end;
      end;
  end;

  Result := AToken.TokenType <> jttNone;
end;

procedure TJSONStreamReader.ForEach(ACallback: TJSONTokenCallback);
var
  Token: TJSONToken;
  Continue: Boolean;
begin
  Continue := True;
  while Continue and ReadToken(Token) do
    ACallback(Token, Continue);
end;

procedure TJSONStreamReader.SkipValue;
var
  Token: TJSONToken;
  StartDepth: Integer;
begin
  StartDepth := FDepth;
  while ReadToken(Token) do
  begin
    if FDepth < StartDepth then
      Break;
    if (FDepth = StartDepth) and Token.IsValue then
      Break;
  end;
end;

function TJSONStreamReader.ReadValue: TJSONValue;
var
  SB: TStringBuilder;
  Token: TJSONToken;
  StartDepth: Integer;
begin
  SB := TStringBuilder.Create;
  try
    StartDepth := FDepth;
    while ReadToken(Token) do
    begin
      case Token.TokenType of
        jttObjectStart: SB.Append('{');
        jttObjectEnd: SB.Append('}');
        jttArrayStart: SB.Append('[');
        jttArrayEnd: SB.Append(']');
        jttPropertyName: SB.Append('"').Append(Token.Value).Append('":');
        jttString: SB.Append('"').Append(EscapeJSONString(Token.Value)).Append('"');
        jttNumber, jttBoolean, jttNull: SB.Append(Token.Value);
      end;

      if FDepth < StartDepth then
        Break;
      if (FDepth = StartDepth) and Token.IsValue then
        Break;
    end;

    Result := TJSONObject.ParseJSONValue(SB.ToString);
  finally
    SB.Free;
  end;
end;

// ============================================================================
// TJSONLinesReader
// ============================================================================

constructor TJSONLinesReader.Create(AStream: TStream; AOwnsStream: Boolean; AEncoding: TEncoding);
begin
  inherited Create;
  FStream := AStream;
  FOwnsStream := AOwnsStream;
  FEncoding := AEncoding;
  if FEncoding = nil then
    FEncoding := TEncoding.UTF8;
  FReader := TStreamReader.Create(FStream, FEncoding);
  FLineNumber := 0;
end;

destructor TJSONLinesReader.Destroy;
begin
  FReader.Free;
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

function TJSONLinesReader.ReadNext(out AJson: TJSONValue): Boolean;
var
  Line: string;
begin
  AJson := nil;
  while not FReader.EndOfStream do
  begin
    Line := FReader.ReadLine.Trim;
    Inc(FLineNumber);
    if Line = '' then
      Continue;
    AJson := TJSONObject.ParseJSONValue(Line);
    Result := AJson <> nil;
    Exit;
  end;
  Result := False;
end;

function TJSONLinesReader.ReadNextObject(out AObj: TJSONObject): Boolean;
var
  Json: TJSONValue;
begin
  AObj := nil;
  if ReadNext(Json) then
  begin
    if Json is TJSONObject then
    begin
      AObj := TJSONObject(Json);
      Result := True;
    end
    else
    begin
      Json.Free;
      Result := False;
    end;
  end
  else
    Result := False;
end;

procedure TJSONLinesReader.ForEach(ACallback: TProc<TJSONValue, Integer>);
var
  Json: TJSONValue;
begin
  while ReadNext(Json) do
  try
    ACallback(Json, FLineNumber);
  finally
    Json.Free;
  end;
end;

// ============================================================================
// TJSONPathExtractor
// ============================================================================

constructor TJSONPathExtractor.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  FSegments := TList<TPathSegment>.Create;
  ParsePath;
end;

destructor TJSONPathExtractor.Destroy;
begin
  FSegments.Free;
  inherited;
end;

procedure TJSONPathExtractor.ParsePath;
var
  i: Integer;
  S: string;
  Seg: TPathSegment;
  InBracket: Boolean;
  Current: string;
begin
  S := FPath;
  if S.StartsWith('$') then
    Delete(S, 1, 1);

  i := 1;
  InBracket := False;
  Current := '';

  while i <= Length(S) do
  begin
    case S[i] of
      '.':
        begin
          if not InBracket then
          begin
            if Current <> '' then
            begin
              Seg.SegmentType := pstProperty;
              Seg.Name := Current;
              Seg.Index := -1;
              FSegments.Add(Seg);
              Current := '';
            end;
            // Check for recursive descent
            if (i < Length(S)) and (S[i + 1] = '.') then
            begin
              Seg.SegmentType := pstRecursive;
              Seg.Name := '';
              Seg.Index := -1;
              FSegments.Add(Seg);
              Inc(i);
            end;
          end
          else
            Current := Current + S[i];
        end;
      '[':
        begin
          if Current <> '' then
          begin
            Seg.SegmentType := pstProperty;
            Seg.Name := Current;
            Seg.Index := -1;
            FSegments.Add(Seg);
            Current := '';
          end;
          InBracket := True;
        end;
      ']':
        begin
          if InBracket then
          begin
            if Current = '*' then
            begin
              Seg.SegmentType := pstWildcard;
              Seg.Name := '';
              Seg.Index := -1;
            end
            else
            begin
              Seg.SegmentType := pstIndex;
              Seg.Name := '';
              Seg.Index := StrToIntDef(Current, 0);
            end;
            FSegments.Add(Seg);
            Current := '';
            InBracket := False;
          end;
        end;
      else
        Current := Current + S[i];
    end;
    Inc(i);
  end;

  if Current <> '' then
  begin
    Seg.SegmentType := pstProperty;
    Seg.Name := Current;
    Seg.Index := -1;
    FSegments.Add(Seg);
  end;
end;

function TJSONPathExtractor.MatchSegment(AValue: TJSONValue; ASegmentIndex: Integer;
  AResults: TList<TJSONValue>): Boolean;
var
  Seg: TPathSegment;
  Obj: TJSONObject;
  Arr: TJSONArray;
  i: Integer;
  Pair: TJSONPair;
  ChildValue: TJSONValue;
begin
  Result := False;
  if AValue = nil then
    Exit;

  if ASegmentIndex >= FSegments.Count then
  begin
    AResults.Add(AValue);
    Result := True;
    Exit;
  end;

  Seg := FSegments[ASegmentIndex];

  case Seg.SegmentType of
    pstProperty:
      begin
        if AValue is TJSONObject then
        begin
          Obj := TJSONObject(AValue);
          ChildValue := Obj.GetValue(Seg.Name);
          if ChildValue <> nil then
            Result := MatchSegment(ChildValue, ASegmentIndex + 1, AResults);
        end;
      end;
    pstIndex:
      begin
        if AValue is TJSONArray then
        begin
          Arr := TJSONArray(AValue);
          if (Seg.Index >= 0) and (Seg.Index < Arr.Count) then
            Result := MatchSegment(Arr.Items[Seg.Index], ASegmentIndex + 1, AResults);
        end;
      end;
    pstWildcard:
      begin
        if AValue is TJSONArray then
        begin
          Arr := TJSONArray(AValue);
          for i := 0 to Arr.Count - 1 do
            if MatchSegment(Arr.Items[i], ASegmentIndex + 1, AResults) then
              Result := True;
        end
        else if AValue is TJSONObject then
        begin
          Obj := TJSONObject(AValue);
          for i := 0 to Obj.Count - 1 do
            if MatchSegment(Obj.Pairs[i].JsonValue, ASegmentIndex + 1, AResults) then
              Result := True;
        end;
      end;
    pstRecursive:
      begin
        // Match at current level
        if MatchSegment(AValue, ASegmentIndex + 1, AResults) then
          Result := True;

        // Recurse into children
        if AValue is TJSONObject then
        begin
          Obj := TJSONObject(AValue);
          for i := 0 to Obj.Count - 1 do
            if MatchSegment(Obj.Pairs[i].JsonValue, ASegmentIndex, AResults) then
              Result := True;
        end
        else if AValue is TJSONArray then
        begin
          Arr := TJSONArray(AValue);
          for i := 0 to Arr.Count - 1 do
            if MatchSegment(Arr.Items[i], ASegmentIndex, AResults) then
              Result := True;
        end;
      end;
  end;
end;

function TJSONPathExtractor.Extract(ARoot: TJSONValue): TJSONValue;
var
  Results: TList<TJSONValue>;
begin
  Result := nil;
  Results := TList<TJSONValue>.Create;
  try
    if MatchSegment(ARoot, 0, Results) and (Results.Count > 0) then
      Result := Results[0];
  finally
    Results.Free;
  end;
end;

function TJSONPathExtractor.ExtractAll(ARoot: TJSONValue): TArray<TJSONValue>;
var
  Results: TList<TJSONValue>;
begin
  Results := TList<TJSONValue>.Create;
  try
    MatchSegment(ARoot, 0, Results);
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TJSONPathExtractor.ExtractString(ARoot: TJSONValue; const ADefault: string): string;
var
  V: TJSONValue;
begin
  V := Extract(ARoot);
  if V <> nil then
  begin
    if V is TJSONString then
      Result := TJSONString(V).Value
    else
      Result := V.ToString;
  end
  else
    Result := ADefault;
end;

function TJSONPathExtractor.ExtractInteger(ARoot: TJSONValue; ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  V := Extract(ARoot);
  if V <> nil then
  begin
    if V is TJSONNumber then
      Result := TJSONNumber(V).AsInt
    else
      Result := StrToIntDef(V.ToString, ADefault);
  end
  else
    Result := ADefault;
end;

function TJSONPathExtractor.ExtractBoolean(ARoot: TJSONValue; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := Extract(ARoot);
  if V <> nil then
  begin
    if V is TJSONBool then
      Result := TJSONBool(V).AsBoolean
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSONPathExtractor.Exists(ARoot: TJSONValue): Boolean;
begin
  Result := Extract(ARoot) <> nil;
end;

class function TJSONPathExtractor.Get(ARoot: TJSONValue; const APath: string): TJSONValue;
var
  Extractor: TJSONPathExtractor;
begin
  Extractor := TJSONPathExtractor.Create(APath);
  try
    Result := Extractor.Extract(ARoot);
  finally
    Extractor.Free;
  end;
end;

class function TJSONPathExtractor.GetString(ARoot: TJSONValue; const APath: string;
  const ADefault: string): string;
var
  Extractor: TJSONPathExtractor;
begin
  Extractor := TJSONPathExtractor.Create(APath);
  try
    Result := Extractor.ExtractString(ARoot, ADefault);
  finally
    Extractor.Free;
  end;
end;

class function TJSONPathExtractor.GetInt(ARoot: TJSONValue; const APath: string;
  ADefault: Integer): Integer;
var
  Extractor: TJSONPathExtractor;
begin
  Extractor := TJSONPathExtractor.Create(APath);
  try
    Result := Extractor.ExtractInteger(ARoot, ADefault);
  finally
    Extractor.Free;
  end;
end;

class function TJSONPathExtractor.GetBool(ARoot: TJSONValue; const APath: string;
  ADefault: Boolean): Boolean;
var
  Extractor: TJSONPathExtractor;
begin
  Extractor := TJSONPathExtractor.Create(APath);
  try
    Result := Extractor.ExtractBoolean(ARoot, ADefault);
  finally
    Extractor.Free;
  end;
end;

// ============================================================================
// TJSONCacheItem
// ============================================================================

constructor TJSONCacheItem.Create(AValue: TJSONValue; const AHash: string; ASizeBytes: Integer);
begin
  inherited Create;
  FValue := AValue;
  FHash := AHash;
  FCreatedAt := Now;
  FLastAccess := Now;
  FAccessCount := 0;
  FSizeBytes := ASizeBytes;
end;

destructor TJSONCacheItem.Destroy;
begin
  FValue.Free;
  inherited;
end;

procedure TJSONCacheItem.Touch;
begin
  FLastAccess := Now;
  Inc(FAccessCount);
end;

// ============================================================================
// TJSONCache
// ============================================================================

constructor TJSONCache.Create(AMaxItems: Integer; AMaxSizeBytes: Int64; ATTLSeconds: Integer);
begin
  inherited Create;
  FCache := TObjectDictionary<string, TJSONCacheItem>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FMaxItems := AMaxItems;
  FMaxSizeBytes := AMaxSizeBytes;
  FCurrentSizeBytes := 0;
  FTTLSeconds := ATTLSeconds;
  FHits := 0;
  FMisses := 0;
end;

destructor TJSONCache.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

function TJSONCache.ComputeHash(const AContent: string): string;
begin
  Result := THashMD5.GetHashString(AContent);
end;

procedure TJSONCache.Evict;
var
  OldestKey: string;
  OldestTime: TDateTime;
  Pair: TPair<string, TJSONCacheItem>;
begin
  // Simple LRU: remove oldest item
  OldestKey := '';
  OldestTime := Now;

  for Pair in FCache do
  begin
    if Pair.Value.LastAccess < OldestTime then
    begin
      OldestTime := Pair.Value.LastAccess;
      OldestKey := Pair.Key;
    end;
  end;

  if OldestKey <> '' then
  begin
    FCurrentSizeBytes := FCurrentSizeBytes - FCache[OldestKey].SizeBytes;
    FCache.Remove(OldestKey);
  end;
end;

procedure TJSONCache.CleanExpired;
var
  ToRemove: TList<string>;
  Pair: TPair<string, TJSONCacheItem>;
  ExpireTime: TDateTime;
begin
  if FTTLSeconds <= 0 then
    Exit;

  ToRemove := TList<string>.Create;
  try
    ExpireTime := IncSecond(Now, -FTTLSeconds);
    for Pair in FCache do
    begin
      if Pair.Value.CreatedAt < ExpireTime then
        ToRemove.Add(Pair.Key);
    end;

    for var Key in ToRemove do
    begin
      FCurrentSizeBytes := FCurrentSizeBytes - FCache[Key].SizeBytes;
      FCache.Remove(Key);
    end;
  finally
    ToRemove.Free;
  end;
end;

function TJSONCache.Get(const AContent: string): TJSONValue;
var
  Hash: string;
  Item: TJSONCacheItem;
begin
  Result := nil;
  Hash := ComputeHash(AContent);

  FLock.Enter;
  try
    CleanExpired;

    if FCache.TryGetValue(Hash, Item) then
    begin
      Item.Touch;
      Inc(FHits);
      Result := CloneJSON(Item.Value);
    end
    else
      Inc(FMisses);
  finally
    FLock.Leave;
  end;
end;

procedure TJSONCache.Put(const AContent: string; AValue: TJSONValue);
var
  Hash: string;
  Size: Integer;
  ClonedValue: TJSONValue;
begin
  if AValue = nil then
    Exit;

  Hash := ComputeHash(AContent);
  Size := EstimateJSONSize(AValue);

  FLock.Enter;
  try
    // Check if already cached
    if FCache.ContainsKey(Hash) then
      Exit;

    // Evict if necessary
    while (FCache.Count >= FMaxItems) or
          ((FMaxSizeBytes > 0) and (FCurrentSizeBytes + Size > FMaxSizeBytes)) do
    begin
      if FCache.Count = 0 then
        Break;
      Evict;
    end;

    ClonedValue := CloneJSON(AValue);
    FCache.Add(Hash, TJSONCacheItem.Create(ClonedValue, Hash, Size));
    FCurrentSizeBytes := FCurrentSizeBytes + Size;
  finally
    FLock.Leave;
  end;
end;

function TJSONCache.ParseAndCache(const AContent: string): TJSONValue;
var
  Cached: TJSONValue;
begin
  // Try cache first
  Cached := Get(AContent);
  if Cached <> nil then
  begin
    Result := Cached;
    Exit;
  end;

  // Parse
  Result := TJSONObject.ParseJSONValue(AContent);
  if Result <> nil then
    Put(AContent, Result);
end;

procedure TJSONCache.Clear;
begin
  FLock.Enter;
  try
    FCache.Clear;
    FCurrentSizeBytes := 0;
  finally
    FLock.Leave;
  end;
end;

function TJSONCache.GetStats: TJSONObject;
var
  Total: Int64;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('items', TJSONNumber.Create(FCache.Count));
    Result.AddPair('sizeBytes', TJSONNumber.Create(FCurrentSizeBytes));
    Result.AddPair('maxItems', TJSONNumber.Create(FMaxItems));
    Result.AddPair('maxSizeBytes', TJSONNumber.Create(FMaxSizeBytes));
    Result.AddPair('hits', TJSONNumber.Create(FHits));
    Result.AddPair('misses', TJSONNumber.Create(FMisses));

    Total := FHits + FMisses;
    if Total > 0 then
      Result.AddPair('hitRate', TJSONNumber.Create(FHits / Total))
    else
      Result.AddPair('hitRate', TJSONNumber.Create(0));
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TJSONBuilder
// ============================================================================

constructor TJSONBuilder.Create(AInitialCapacity: Integer; APrettyPrint: Boolean);
begin
  inherited Create;
  FBuffer := TStringBuilder.Create(AInitialCapacity);
  FStateStack := TStack<TJSONBuilderState>.Create;
  FNeedComma := TStack<Boolean>.Create;
  FIndent := 0;
  FPrettyPrint := APrettyPrint;
  FStateStack.Push(jbsInitial);
  FNeedComma.Push(False);
end;

destructor TJSONBuilder.Destroy;
begin
  FBuffer.Free;
  FStateStack.Free;
  FNeedComma.Free;
  inherited;
end;

procedure TJSONBuilder.WriteIndent;
var
  i: Integer;
begin
  if FPrettyPrint then
  begin
    FBuffer.AppendLine;
    for i := 1 to FIndent do
      FBuffer.Append('  ');
  end;
end;

procedure TJSONBuilder.WriteCommaIfNeeded;
begin
  if FNeedComma.Peek then
    FBuffer.Append(',');
end;

procedure TJSONBuilder.PushState(AState: TJSONBuilderState);
begin
  FStateStack.Push(AState);
  FNeedComma.Push(False);
end;

procedure TJSONBuilder.PopState;
begin
  FStateStack.Pop;
  FNeedComma.Pop;
  // Mark that next item needs comma
  FNeedComma.Pop;
  FNeedComma.Push(True);
end;

function TJSONBuilder.GetCurrentState: TJSONBuilderState;
begin
  Result := FStateStack.Peek;
end;

procedure TJSONBuilder.WriteValue(const AValue: string);
begin
  WriteCommaIfNeeded;
  if FPrettyPrint and (GetCurrentState = jbsArray) then
    WriteIndent;
  FBuffer.Append(AValue);
  FNeedComma.Pop;
  FNeedComma.Push(True);
end;

function TJSONBuilder.BeginObject: TJSONBuilder;
begin
  WriteCommaIfNeeded;
  if FPrettyPrint and (GetCurrentState in [jbsArray]) then
    WriteIndent;
  FBuffer.Append('{');
  Inc(FIndent);
  PushState(jbsObject);
  Result := Self;
end;

function TJSONBuilder.EndObject: TJSONBuilder;
begin
  Dec(FIndent);
  if FPrettyPrint then
    WriteIndent;
  FBuffer.Append('}');
  PopState;
  Result := Self;
end;

function TJSONBuilder.BeginArray: TJSONBuilder;
begin
  WriteCommaIfNeeded;
  if FPrettyPrint and (GetCurrentState = jbsArray) then
    WriteIndent;
  FBuffer.Append('[');
  Inc(FIndent);
  PushState(jbsArray);
  Result := Self;
end;

function TJSONBuilder.EndArray: TJSONBuilder;
begin
  Dec(FIndent);
  if FPrettyPrint then
    WriteIndent;
  FBuffer.Append(']');
  PopState;
  Result := Self;
end;

function TJSONBuilder.WriteProperty(const AName: string): TJSONBuilder;
begin
  WriteCommaIfNeeded;
  if FPrettyPrint then
    WriteIndent;
  FBuffer.Append('"').Append(EscapeJSONString(AName)).Append('":');
  if FPrettyPrint then
    FBuffer.Append(' ');
  FNeedComma.Pop;
  FNeedComma.Push(False);
  Result := Self;
end;

function TJSONBuilder.WriteString(const AValue: string): TJSONBuilder;
begin
  WriteValue('"' + EscapeJSONString(AValue) + '"');
  Result := Self;
end;

function TJSONBuilder.WriteString(const AName, AValue: string): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteString(AValue);
  Result := Self;
end;

function TJSONBuilder.WriteInteger(AValue: Int64): TJSONBuilder;
begin
  WriteValue(IntToStr(AValue));
  Result := Self;
end;

function TJSONBuilder.WriteInteger(const AName: string; AValue: Int64): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteInteger(AValue);
  Result := Self;
end;

function TJSONBuilder.WriteFloat(AValue: Double): TJSONBuilder;
var
  S: string;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  S := FloatToStr(AValue, FS);
  WriteValue(S);
  Result := Self;
end;

function TJSONBuilder.WriteFloat(const AName: string; AValue: Double): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteFloat(AValue);
  Result := Self;
end;

function TJSONBuilder.WriteBoolean(AValue: Boolean): TJSONBuilder;
begin
  if AValue then
    WriteValue('true')
  else
    WriteValue('false');
  Result := Self;
end;

function TJSONBuilder.WriteBoolean(const AName: string; AValue: Boolean): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteBoolean(AValue);
  Result := Self;
end;

function TJSONBuilder.WriteNull: TJSONBuilder;
begin
  WriteValue('null');
  Result := Self;
end;

function TJSONBuilder.WriteNull(const AName: string): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteNull;
  Result := Self;
end;

function TJSONBuilder.WriteRaw(const AJson: string): TJSONBuilder;
begin
  WriteValue(AJson);
  Result := Self;
end;

function TJSONBuilder.WriteJSON(AValue: TJSONValue): TJSONBuilder;
begin
  if AValue <> nil then
    WriteRaw(AValue.ToString)
  else
    WriteNull;
  Result := Self;
end;

function TJSONBuilder.WriteJSON(const AName: string; AValue: TJSONValue): TJSONBuilder;
begin
  WriteProperty(AName);
  WriteJSON(AValue);
  Result := Self;
end;

procedure TJSONBuilder.Reset;
begin
  FBuffer.Clear;
  FStateStack.Clear;
  FNeedComma.Clear;
  FIndent := 0;
  FStateStack.Push(jbsInitial);
  FNeedComma.Push(False);
end;

function TJSONBuilder.ToString: string;
begin
  Result := FBuffer.ToString;
end;

function TJSONBuilder.ToJSON: TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(ToString);
end;

// ============================================================================
// Utility Functions
// ============================================================================

function EscapeJSONString(const S: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S) + 10);
  try
    for C in S do
    begin
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        '/': SB.Append('\/');
        #8: SB.Append('\b');
        #9: SB.Append('\t');
        #10: SB.Append('\n');
        #12: SB.Append('\f');
        #13: SB.Append('\r');
      else
        if Ord(C) < 32 then
          SB.Append('\u').Append(IntToHex(Ord(C), 4))
        else
          SB.Append(C);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function UnescapeJSONString(const S: string): string;
var
  SB: TStringBuilder;
  i: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S));
  try
    i := 1;
    while i <= Length(S) do
    begin
      C := S[i];
      if (C = '\') and (i < Length(S)) then
      begin
        Inc(i);
        C := S[i];
        case C of
          '"', '\', '/': SB.Append(C);
          'b': SB.Append(#8);
          't': SB.Append(#9);
          'n': SB.Append(#10);
          'f': SB.Append(#12);
          'r': SB.Append(#13);
          'u':
            begin
              if i + 4 <= Length(S) then
              begin
                SB.Append(Char(StrToIntDef('$' + Copy(S, i + 1, 4), 0)));
                Inc(i, 4);
              end;
            end;
        else
          SB.Append(C);
        end;
      end
      else
        SB.Append(C);
      Inc(i);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function EstimateJSONSize(AValue: TJSONValue): Integer;
var
  i: Integer;
  Obj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := 0;
  if AValue = nil then
    Exit;

  if AValue is TJSONObject then
  begin
    Obj := TJSONObject(AValue);
    Result := 2; // {}
    for i := 0 to Obj.Count - 1 do
    begin
      Result := Result + Length(Obj.Pairs[i].JsonString.Value) + 4; // "key":
      Result := Result + EstimateJSONSize(Obj.Pairs[i].JsonValue);
    end;
  end
  else if AValue is TJSONArray then
  begin
    Arr := TJSONArray(AValue);
    Result := 2; // []
    for i := 0 to Arr.Count - 1 do
      Result := Result + EstimateJSONSize(Arr.Items[i]) + 1; // ,
  end
  else if AValue is TJSONString then
    Result := Length(TJSONString(AValue).Value) + 2
  else if AValue is TJSONNumber then
    Result := Length(AValue.ToString)
  else if AValue is TJSONBool then
    Result := 5 // true/false
  else if AValue is TJSONNull then
    Result := 4; // null
end;

function CloneJSON(AValue: TJSONValue): TJSONValue;
begin
  if AValue = nil then
    Result := nil
  else
    Result := TJSONObject.ParseJSONValue(AValue.ToString);
end;

function MergeJSON(ABase, AOverlay: TJSONObject): TJSONObject;
var
  i: Integer;
  Key: string;
  BaseValue, OverlayValue: TJSONValue;
begin
  Result := TJSONObject(CloneJSON(ABase));
  if AOverlay = nil then
    Exit;

  for i := 0 to AOverlay.Count - 1 do
  begin
    Key := AOverlay.Pairs[i].JsonString.Value;
    OverlayValue := AOverlay.Pairs[i].JsonValue;

    BaseValue := Result.GetValue(Key);
    if (BaseValue <> nil) and (BaseValue is TJSONObject) and (OverlayValue is TJSONObject) then
    begin
      // Recursive merge for nested objects
      var Merged := MergeJSON(TJSONObject(BaseValue), TJSONObject(OverlayValue));
      Result.RemovePair(Key).Free;
      Result.AddPair(Key, Merged);
    end
    else
    begin
      // Replace or add
      if BaseValue <> nil then
        Result.RemovePair(Key).Free;
      Result.AddPair(Key, CloneJSON(OverlayValue));
    end;
  end;
end;

end.
