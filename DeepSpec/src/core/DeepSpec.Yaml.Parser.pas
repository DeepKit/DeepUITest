{ ============================================================================
  DeepSpec.Yaml.Parser

  Lightweight YAML parser for DeepSpec data files. Supports the subset used
  by the protocol:
    - block-style mappings and sequences
    - scalar values (string, int, bool, null)
    - quoted strings (single + double quotes)
    - nested structures via indentation
    - block literal pipe and folded greater-than scalars
    - flow sequences in square-bracket form, and empty curly-brace flow map
    - end-of-line hash-comment (when not inside quotes)
    - LLM tolerance: leading UTF-8 BOM, fenced YAML code blocks,
      leading triple-dash document marker, tab indentation
      (converted to spaces)

  Does NOT support: anchors/aliases, multi-document streams, custom tags,
  flow maps with content, or YAML 1.2 advanced features.

  Output is a tree of TYamlNode (map/sequence/scalar).
  ============================================================================ }

unit DeepSpec.Yaml.Parser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TYamlKind = (ykScalar, ykMap, ykSequence);

  TYamlNode = class
  private
    FKind: TYamlKind;
    FScalar: string;
    FMap: TObjectDictionary<string, TYamlNode>;
    FSeq: TObjectList<TYamlNode>;
  public
    constructor CreateScalar(const AValue: string);
    {$WARN DUPLICATE_CTOR_DTOR OFF}
    constructor CreateMap;
    constructor CreateSequence;
    destructor Destroy; override;

    function AsString(const ADefault: string = ''): string;
    function AsInteger(ADefault: Integer = 0): Integer;
    function AsBoolean(ADefault: Boolean = False): Boolean;
    function IsNull: Boolean;

    function Has(const AKey: string): Boolean;
    function Get(const AKey: string): TYamlNode;
    function GetString(const AKey, ADefault: string): string;
    function GetInteger(const AKey: string; ADefault: Integer): Integer;
    function GetBoolean(const AKey: string; ADefault: Boolean): Boolean;
    function GetSeq(const AKey: string): TYamlNode;

    procedure SetField(const AKey: string; ANode: TYamlNode);
    procedure AddItem(ANode: TYamlNode);

    function MapKeys: TArray<string>;
    function SeqCount: Integer;
    function SeqItem(AIndex: Integer): TYamlNode;

    property Kind: TYamlKind read FKind;
  end;

  TYamlParser = class
  private
    FLines: TArray<string>;
    FPos: Integer;
    function CountIndent(const ALine: string): Integer;
    function StripQuotes(const AValue: string): string;
    function IsBlankOrComment(const ALine: string): Boolean;
    function StripEolComment(const ALine: string): string;
    function Preprocess(const AYaml: string): string;
    function ParseBlockScalar(AIndent: Integer; AStyle: Char): TYamlNode;
    function ParseFlowSequence(const ARaw: string): TYamlNode;
    function ParseValue(const ARaw: string; AParentIndent: Integer): TYamlNode;
    function ParseMap(AIndent: Integer): TYamlNode;
    function ParseSequence(AIndent: Integer): TYamlNode;
  public
    function Parse(const AYaml: string): TYamlNode;
    function ParseFile(const APath: string): TYamlNode;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils;

{ TYamlNode }

constructor TYamlNode.CreateScalar(const AValue: string);
begin
  inherited Create;
  FKind := ykScalar;
  FScalar := AValue;
end;

constructor TYamlNode.CreateMap;
begin
  inherited Create;
  FKind := ykMap;
  FMap := TObjectDictionary<string, TYamlNode>.Create([doOwnsValues]);
end;

constructor TYamlNode.CreateSequence;
begin
  inherited Create;
  FKind := ykSequence;
  FSeq := TObjectList<TYamlNode>.Create(True);
end;

destructor TYamlNode.Destroy;
begin
  FMap.Free;
  FSeq.Free;
  inherited;
end;

function TYamlNode.AsString(const ADefault: string): string;
begin
  if FKind = ykScalar then
  begin
    if (FScalar = 'null') or (FScalar = '~') then
      Result := ADefault
    else
      Result := FScalar;
  end
  else
    Result := ADefault;
end;

function TYamlNode.AsInteger(ADefault: Integer): Integer;
begin
  if (FKind = ykScalar) and (FScalar <> '') and (FScalar <> 'null') then
    Result := StrToIntDef(FScalar, ADefault)
  else
    Result := ADefault;
end;

function TYamlNode.AsBoolean(ADefault: Boolean): Boolean;
begin
  if FKind = ykScalar then
  begin
    var LLower := LowerCase(FScalar);
    if (LLower = 'true') or (LLower = 'yes') or (LLower = 'on') then
      Result := True
    else if (LLower = 'false') or (LLower = 'no') or (LLower = 'off') then
      Result := False
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TYamlNode.IsNull: Boolean;
begin
  Result := (FKind = ykScalar) and ((FScalar = '') or (FScalar = 'null') or (FScalar = '~'));
end;

function TYamlNode.Has(const AKey: string): Boolean;
begin
  Result := (FKind = ykMap) and FMap.ContainsKey(AKey);
end;

function TYamlNode.Get(const AKey: string): TYamlNode;
begin
  if (FKind = ykMap) and FMap.TryGetValue(AKey, Result) then
    Exit;
  Result := nil;
end;

function TYamlNode.GetString(const AKey, ADefault: string): string;
begin
  var LNode := Get(AKey);
  if LNode <> nil then
    Result := LNode.AsString(ADefault)
  else
    Result := ADefault;
end;

function TYamlNode.GetInteger(const AKey: string; ADefault: Integer): Integer;
begin
  var LNode := Get(AKey);
  if LNode <> nil then
    Result := LNode.AsInteger(ADefault)
  else
    Result := ADefault;
end;

function TYamlNode.GetBoolean(const AKey: string; ADefault: Boolean): Boolean;
begin
  var LNode := Get(AKey);
  if LNode <> nil then
    Result := LNode.AsBoolean(ADefault)
  else
    Result := ADefault;
end;

function TYamlNode.GetSeq(const AKey: string): TYamlNode;
begin
  Result := Get(AKey);
  if (Result <> nil) and (Result.Kind <> ykSequence) then
    Result := nil;
end;

procedure TYamlNode.SetField(const AKey: string; ANode: TYamlNode);
begin
  if FKind <> ykMap then
    raise Exception.Create('SetField on non-map node');
  FMap.AddOrSetValue(AKey, ANode);
end;

procedure TYamlNode.AddItem(ANode: TYamlNode);
begin
  if FKind <> ykSequence then
    raise Exception.Create('AddItem on non-sequence node');
  FSeq.Add(ANode);
end;

function TYamlNode.MapKeys: TArray<string>;
begin
  if FKind = ykMap then
    Result := FMap.Keys.ToArray
  else
    Result := [];
end;

function TYamlNode.SeqCount: Integer;
begin
  if FKind = ykSequence then
    Result := FSeq.Count
  else
    Result := 0;
end;

function TYamlNode.SeqItem(AIndex: Integer): TYamlNode;
begin
  if (FKind = ykSequence) and (AIndex >= 0) and (AIndex < FSeq.Count) then
    Result := FSeq[AIndex]
  else
    Result := nil;
end;

{ TYamlParser }

function TYamlParser.Preprocess(const AYaml: string): string;
const
  CFenceLang = '```yaml';
  CFenceBare = '```';
begin
  Result := AYaml;

  // Strip UTF-8 BOM (EF BB BF)
  if (Result.Length > 0) and (Result.Chars[0] = #$FEFF) then
    Result := Result.Substring(1);

  // Normalize line endings
  Result := Result.Replace(#13#10, #10).Replace(#13, #10);

  // Convert tab indentation to 2 spaces (YAML disallows tabs but LLMs
  // sometimes emit them; safer to map than to fail).
  Result := Result.Replace(#9, '  ');

  // Strip ```yaml ... ``` or ``` ... ``` code fences if present.
  // Only if both opening and closing fences exist; otherwise leave content.
  var LLines := Result.Split([#10]);
  var LStart := 0;
  var LEnd := Length(LLines);

  // Skip leading blank lines for fence detection
  while (LStart < LEnd) and (LLines[LStart].Trim = '') do
    Inc(LStart);

  if (LStart < LEnd) then
  begin
    var LFirst := LLines[LStart].TrimRight.ToLower;
    if (LFirst = CFenceLang) or (LFirst = CFenceBare)
       or LFirst.StartsWith(CFenceLang + ' ') then
    begin
      // Look for closing fence
      var LCloseAt := -1;
      for var I := LEnd - 1 downto LStart + 1 do
        if LLines[I].Trim = CFenceBare then
        begin
          LCloseAt := I;
          Break;
        end;
      if LCloseAt > LStart then
      begin
        Inc(LStart);
        LEnd := LCloseAt;
      end;
    end;
  end;

  // Skip leading `---` document marker
  if (LStart < LEnd) and (LLines[LStart].Trim = '---') then
    Inc(LStart);

  if (LStart > 0) or (LEnd < Length(LLines)) then
  begin
    var LSelected := Copy(LLines, LStart, LEnd - LStart);
    Result := string.Join(#10, LSelected);
  end;
end;

function TYamlParser.Parse(const AYaml: string): TYamlNode;
begin
  var LPrepared := Preprocess(AYaml);
  FLines := LPrepared.Split([#10]);
  FPos := 0;

  // Skip leading blank/comment lines
  while (FPos < Length(FLines)) and IsBlankOrComment(FLines[FPos]) do
    Inc(FPos);

  if FPos >= Length(FLines) then
  begin
    Result := TYamlNode.CreateMap;
    Exit;
  end;

  Result := ParseMap(0);
end;

function TYamlParser.ParseFile(const APath: string): TYamlNode;
begin
  Result := Parse(TFile.ReadAllText(APath, TEncoding.UTF8));
end;

function TYamlParser.StripEolComment(const ALine: string): string;
var
  LInSingle, LInDouble: Boolean;
begin
  // Strip ` # comment` (must be preceded by whitespace or at start) when
  // not inside a quoted string. Preserves URL fragments like `http://x#y`.
  Result := ALine;
  LInSingle := False;
  LInDouble := False;
  for var I := 0 to ALine.Length - 1 do
  begin
    var C := ALine.Chars[I];
    if (C = '''') and not LInDouble then
      LInSingle := not LInSingle
    else if (C = '"') and not LInSingle then
      LInDouble := not LInDouble
    else if (C = '#') and not LInSingle and not LInDouble then
    begin
      if (I = 0) or (ALine.Chars[I - 1] = ' ') or (ALine.Chars[I - 1] = #9) then
      begin
        Result := ALine.Substring(0, I).TrimRight;
        Exit;
      end;
    end;
  end;
end;

function TYamlParser.CountIndent(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and (ALine.Chars[Result] = ' ') do
    Inc(Result);
end;

function TYamlParser.IsBlankOrComment(const ALine: string): Boolean;
var
  LTrimmed: string;
begin
  LTrimmed := ALine.Trim;
  Result := (LTrimmed = '') or LTrimmed.StartsWith('#');
end;

function TYamlParser.StripQuotes(const AValue: string): string;
var
  LTrimmed: string;
begin
  LTrimmed := AValue.Trim;
  if (LTrimmed.Length >= 2)
     and ((LTrimmed.StartsWith('"') and LTrimmed.EndsWith('"'))
          or (LTrimmed.StartsWith('''') and LTrimmed.EndsWith(''''))) then
  begin
    Result := LTrimmed.Substring(1, LTrimmed.Length - 2);
    // Handle escape sequences for double-quoted strings
    if LTrimmed.StartsWith('"') then
      Result := Result.Replace('\n', #10).Replace('\r', #13)
        .Replace('\"', '"').Replace('\\', '\');
  end
  else
    Result := LTrimmed;
end;

function TYamlParser.ParseBlockScalar(AIndent: Integer; AStyle: Char): TYamlNode;
// AStyle: '|' = literal (preserve newlines), '>' = folded (newlines -> spaces)
// AIndent: indent of the OWNING key. Block content must be indented deeper.
var
  LSb: TStringBuilder;
  LFirstIndent: Integer;
begin
  LSb := TStringBuilder.Create;
  try
    LFirstIndent := -1;
    while FPos < Length(FLines) do
    begin
      var LLine := FLines[FPos];
      if LLine.Trim = '' then
      begin
        // Preserve blank lines inside the block (literal: as newline, folded: as paragraph break)
        if LFirstIndent >= 0 then
        begin
          if AStyle = '|' then
            LSb.AppendLine
          else
            LSb.AppendLine;
        end;
        Inc(FPos);
        Continue;
      end;
      var LCurIndent := CountIndent(LLine);
      if LCurIndent <= AIndent then
        Break;
      if LFirstIndent < 0 then
        LFirstIndent := LCurIndent;
      var LContent := LLine.Substring(LFirstIndent);
      if AStyle = '|' then
        LSb.AppendLine(LContent)
      else
      begin
        // folded: join with space; preserve double-newline as paragraph
        if LSb.Length > 0 then
          LSb.Append(' ');
        LSb.Append(LContent.TrimRight);
      end;
      Inc(FPos);
    end;
    // Strip a single trailing newline (clip indicator default behaviour)
    var LText := LSb.ToString;
    while LText.EndsWith(sLineBreak) do
      LText := LText.Substring(0, LText.Length - Length(sLineBreak));
    Result := TYamlNode.CreateScalar(LText);
  finally
    LSb.Free;
  end;
end;

function TYamlParser.ParseFlowSequence(const ARaw: string): TYamlNode;
// Parse `[item, item, "with, comma", 'single', 42]` into a sequence of scalars.
// Does NOT recurse into nested flow maps; treats nested `[...]` as raw scalar.
var
  LBody: string;
  LStart, LDepth: Integer;
  LInSingle, LInDouble: Boolean;
begin
  Result := TYamlNode.CreateSequence;
  try
    LBody := ARaw.Trim;
    if not (LBody.StartsWith('[') and LBody.EndsWith(']')) then Exit;
    LBody := LBody.Substring(1, LBody.Length - 2);
    if LBody.Trim = '' then Exit;

    LStart := 0;
    LDepth := 0;
    LInSingle := False;
    LInDouble := False;
    for var I := 0 to LBody.Length - 1 do
    begin
      var C := LBody.Chars[I];
      if (C = '''') and not LInDouble then
        LInSingle := not LInSingle
      else if (C = '"') and not LInSingle then
        LInDouble := not LInDouble
      else if not LInSingle and not LInDouble then
      begin
        if (C = '[') or (C = '{') then
          Inc(LDepth)
        else if (C = ']') or (C = '}') then
          Dec(LDepth)
        else if (C = ',') and (LDepth = 0) then
        begin
          var LPart := LBody.Substring(LStart, I - LStart).Trim;
          if LPart <> '' then
            Result.AddItem(TYamlNode.CreateScalar(StripQuotes(LPart)));
          LStart := I + 1;
        end;
      end;
    end;
    var LLast := LBody.Substring(LStart).Trim;
    if LLast <> '' then
      Result.AddItem(TYamlNode.CreateScalar(StripQuotes(LLast)));
  except
    Result.Free;
    raise;
  end;
end;

function TYamlParser.ParseValue(const ARaw: string; AParentIndent: Integer): TYamlNode;
var
  LTrimmed: string;
begin
  LTrimmed := ARaw.Trim;

  // Inline empty array
  if LTrimmed = '[]' then
  begin
    Result := TYamlNode.CreateSequence;
    Exit;
  end;

  // Inline empty map
  if LTrimmed = '{}' then
  begin
    Result := TYamlNode.CreateMap;
    Exit;
  end;

  // Flow sequence with items: [a, b, c]
  if LTrimmed.StartsWith('[') and LTrimmed.EndsWith(']') then
  begin
    Result := ParseFlowSequence(LTrimmed);
    Exit;
  end;

  // Block scalar: `|` literal or `>` folded (with optional `-`/`+` chomping
  // indicators that we accept but ignore).
  if (LTrimmed = '|') or (LTrimmed = '>')
     or (LTrimmed = '|-') or (LTrimmed = '|+')
     or (LTrimmed = '>-') or (LTrimmed = '>+') then
  begin
    Result := ParseBlockScalar(AParentIndent, LTrimmed.Chars[0]);
    Exit;
  end;

  // Empty value: check next line for nested map or sequence
  if LTrimmed = '' then
  begin
    // Look at next non-blank line (FPos already points to the line after key:)
    var LNextPos := FPos;
    while (LNextPos < Length(FLines)) and IsBlankOrComment(FLines[LNextPos]) do
      Inc(LNextPos);

    if LNextPos < Length(FLines) then
    begin
      var LNextLine := FLines[LNextPos];
      var LNextIndent := CountIndent(LNextLine);
      if LNextIndent > AParentIndent then
      begin
        var LStripped := LNextLine.Substring(LNextIndent).TrimRight;
        FPos := LNextPos;
        if LStripped.StartsWith('- ') or (LStripped = '-') then
          Result := ParseSequence(LNextIndent)
        else
          Result := ParseMap(LNextIndent);
        Exit;
      end;
    end;
    Result := TYamlNode.CreateScalar('');
    Exit;
  end;

  Result := TYamlNode.CreateScalar(StripQuotes(LTrimmed));
end;

function TYamlParser.ParseMap(AIndent: Integer): TYamlNode;
var
  LLine, LStripped, LKey, LValue: string;
  LCurIndent, LColonPos: Integer;
  LValueNode: TYamlNode;
begin
  Result := TYamlNode.CreateMap;
  try
    while FPos < Length(FLines) do
    begin
      LLine := FLines[FPos];

      if IsBlankOrComment(LLine) then
      begin
        Inc(FPos);
        Continue;
      end;

      LCurIndent := CountIndent(LLine);
      if LCurIndent < AIndent then
        Break;
      if LCurIndent > AIndent then
      begin
        // Should not happen at this level
        Inc(FPos);
        Continue;
      end;

      LStripped := StripEolComment(LLine.Substring(LCurIndent)).TrimRight;

      // Sequence item at this level means we're not a map
      if LStripped.StartsWith('- ') or (LStripped = '-') then
        Break;

      LColonPos := LStripped.IndexOf(':');
      if LColonPos < 0 then
      begin
        Inc(FPos);
        Continue;
      end;

      LKey := LStripped.Substring(0, LColonPos).Trim;
      if LColonPos + 1 < LStripped.Length then
        LValue := LStripped.Substring(LColonPos + 1).Trim
      else
        LValue := '';

      Inc(FPos);
      LValueNode := ParseValue(LValue, AIndent);
      Result.SetField(StripQuotes(LKey), LValueNode);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYamlParser.ParseSequence(AIndent: Integer): TYamlNode;
var
  LLine, LStripped, LItemContent: string;
  LCurIndent: Integer;
  LItem: TYamlNode;
begin
  Result := TYamlNode.CreateSequence;
  try
    while FPos < Length(FLines) do
    begin
      LLine := FLines[FPos];

      if IsBlankOrComment(LLine) then
      begin
        Inc(FPos);
        Continue;
      end;

      LCurIndent := CountIndent(LLine);
      if LCurIndent < AIndent then
        Break;
      if LCurIndent > AIndent then
      begin
        Inc(FPos);
        Continue;
      end;

      LStripped := StripEolComment(LLine.Substring(LCurIndent)).TrimRight;
      if not (LStripped.StartsWith('- ') or (LStripped = '-')) then
        Break;

      if LStripped = '-' then
        LItemContent := ''
      else
        LItemContent := LStripped.Substring(2).Trim;

      Inc(FPos);

      // Item is either inline scalar, inline map (key: val on same line),
      // or starts a nested map/sequence on next lines.
      if LItemContent = '' then
      begin
        LItem := ParseValue('', AIndent);
        Result.AddItem(LItem);
      end
      else if LItemContent.StartsWith('[') and LItemContent.EndsWith(']') then
      begin
        // Nested flow sequence as item
        LItem := ParseFlowSequence(LItemContent);
        Result.AddItem(LItem);
      end
      else if LItemContent.IndexOf(':') > 0 then
      begin
        // Inline map starting on the same line as "- "
        // Treat the content area starting at AIndent + 2 as a map
        // We need to re-parse with the inline key:value as first entry
        LItem := TYamlNode.CreateMap;
        try
          var LColonPos := LItemContent.IndexOf(':');
          var LKey := LItemContent.Substring(0, LColonPos).Trim;
          var LValue: string;
          if LColonPos + 1 < LItemContent.Length then
            LValue := LItemContent.Substring(LColonPos + 1).Trim
          else
            LValue := '';
          var LValNode := ParseValue(LValue, AIndent + 2);
          LItem.SetField(StripQuotes(LKey), LValNode);

          // Continue parsing additional fields at indent AIndent + 2
          while FPos < Length(FLines) do
          begin
            var LNextLine := FLines[FPos];
            if IsBlankOrComment(LNextLine) then
            begin
              Inc(FPos);
              Continue;
            end;
            var LNextIndent := CountIndent(LNextLine);
            if LNextIndent <> AIndent + 2 then
              Break;
            var LNextStripped := LNextLine.Substring(LNextIndent).TrimRight;
            if LNextStripped.StartsWith('- ') or (LNextStripped = '-') then
              Break;
            var LNextColon := LNextStripped.IndexOf(':');
            if LNextColon < 0 then
            begin
              Inc(FPos);
              Continue;
            end;
            var LNextKey := LNextStripped.Substring(0, LNextColon).Trim;
            var LNextVal: string;
            if LNextColon + 1 < LNextStripped.Length then
              LNextVal := LNextStripped.Substring(LNextColon + 1).Trim
            else
              LNextVal := '';
            Inc(FPos);
            var LNextValNode := ParseValue(LNextVal, AIndent + 2);
            LItem.SetField(StripQuotes(LNextKey), LNextValNode);
          end;
        except
          LItem.Free;
          raise;
        end;
        Result.AddItem(LItem);
      end
      else
      begin
        // Inline scalar
        LItem := TYamlNode.CreateScalar(StripQuotes(LItemContent));
        Result.AddItem(LItem);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
