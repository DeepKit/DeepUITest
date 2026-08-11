{ ============================================================================
  DeepSpec.Delphi.DfmParser

  Lightweight DFM (Delphi Form) text parser. Extracts form/control hierarchy
  from text-format .dfm files for view tree generation.

  Supports: object/end blocks, Caption/Name/Left/Top properties,
  nested controls. Skips: binary DFM, complex property values,
  references, sets, and arrays.

  Output: a tree of TDfmObject records.
  ============================================================================ }

unit DeepSpec.Delphi.DfmParser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TDfmObject = class
  private
    FName: string;
    FClassName: string;
    FCaption: string;
    FChildren: TObjectList<TDfmObject>;
  public
    constructor Create;
    destructor Destroy; override;
    property Name: string read FName write FName;
    {$WARN HIDING_MEMBER OFF}
    property ClassName: string read FClassName write FClassName;
    {$WARN HIDING_MEMBER DEFAULT}
    property Caption: string read FCaption write FCaption;
    property Children: TObjectList<TDfmObject> read FChildren;
  end;

  TDfmParser = class
  private
    FLines: TArray<string>;
    FPos: Integer;
    function ParseObject: TDfmObject;
    function StripQuotes(const S: string): string;
  public
    /// <summary>
    /// Parse a text DFM file. Returns nil if file is binary or parse fails.
    /// </summary>
    function ParseFile(const APath: string): TDfmObject;
    function Parse(const AContent: string): TDfmObject;

    /// <summary>
    /// Returns True if the file appears to be text-format DFM.
    /// </summary>
    class function IsTextDfm(const APath: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils;

{ TDfmObject }

constructor TDfmObject.Create;
begin
  inherited Create;
  FChildren := TObjectList<TDfmObject>.Create(True);
end;

destructor TDfmObject.Destroy;
begin
  FChildren.Free;
  inherited;
end;

{ TDfmParser }

class function TDfmParser.IsTextDfm(const APath: string): Boolean;
begin
  Result := False;
  if not TFile.Exists(APath) then Exit;

  var LStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    if LStream.Size < 4 then Exit;
    var LSig: array[0..3] of Byte;
    LStream.ReadBuffer(LSig, 4);
    // Binary DFM starts with "TPF0" (54 50 46 30)
    if (LSig[0] = $54) and (LSig[1] = $50) and (LSig[2] = $46) and (LSig[3] = $30) then
      Exit(False);
    // Text DFM starts with "object " or "inherited " or with optional BOM
    Result := True;
  finally
    LStream.Free;
  end;
end;

function TDfmParser.ParseFile(const APath: string): TDfmObject;
begin
  Result := nil;
  if not IsTextDfm(APath) then Exit;
  try
    var LContent := TFile.ReadAllText(APath);
    Result := Parse(LContent);
  except
    Result := nil;
  end;
end;

function TDfmParser.Parse(const AContent: string): TDfmObject;
begin
  var LNormalized := AContent.Replace(#13#10, #10).Replace(#13, #10);
  FLines := LNormalized.Split([#10]);
  FPos := 0;

  // Skip leading blank lines
  while (FPos < Length(FLines)) and (FLines[FPos].Trim = '') do
    Inc(FPos);

  if FPos >= Length(FLines) then
    Exit(nil);

  Result := ParseObject;
end;

function TDfmParser.StripQuotes(const S: string): string;
var
  LTrimmed: string;
begin
  LTrimmed := S.Trim;
  if (LTrimmed.Length >= 2) and LTrimmed.StartsWith('''') and LTrimmed.EndsWith('''') then
    Result := LTrimmed.Substring(1, LTrimmed.Length - 2).Replace('''''', '''')
  else
    Result := LTrimmed;
end;

function TDfmParser.ParseObject: TDfmObject;
var
  LLine, LTrimmed, LHeader, LName, LClassName: string;
  LColonPos: Integer;
begin
  Result := nil;
  if FPos >= Length(FLines) then Exit;

  LLine := FLines[FPos];
  LTrimmed := LLine.Trim;

  // Expect "object Name: ClassName" or "inherited Name: ClassName"
  if LTrimmed.StartsWith('object ') then
    LHeader := LTrimmed.Substring(7).Trim
  else if LTrimmed.StartsWith('inherited ') then
    LHeader := LTrimmed.Substring(10).Trim
  else if LTrimmed.StartsWith('inline ') then
    LHeader := LTrimmed.Substring(7).Trim
  else
  begin
    Inc(FPos);
    Exit(nil);
  end;

  LColonPos := LHeader.IndexOf(':');
  if LColonPos < 0 then
  begin
    LName := '';
    LClassName := LHeader;
  end
  else
  begin
    LName := LHeader.Substring(0, LColonPos).Trim;
    LClassName := LHeader.Substring(LColonPos + 1).Trim;
    // Strip array suffix [0], [1], etc.
    var LBracketPos := LClassName.IndexOf('[');
    if LBracketPos > 0 then
      LClassName := LClassName.Substring(0, LBracketPos).Trim;
  end;

  Result := TDfmObject.Create;
  Result.Name := LName;
  Result.ClassName := LClassName;

  Inc(FPos);

  while FPos < Length(FLines) do
  begin
    LLine := FLines[FPos];
    LTrimmed := LLine.Trim;

    if LTrimmed = 'end' then
    begin
      Inc(FPos);
      Break;
    end;

    if LTrimmed.StartsWith('object ') or LTrimmed.StartsWith('inherited ')
       or LTrimmed.StartsWith('inline ') then
    begin
      var LChild := ParseObject;
      if LChild <> nil then
        Result.Children.Add(LChild);
      Continue;
    end;

    // Property: "PropName = Value"
    var LEqPos := LTrimmed.IndexOf('=');
    if LEqPos > 0 then
    begin
      var LPropName := LTrimmed.Substring(0, LEqPos).Trim;
      var LPropValue := LTrimmed.Substring(LEqPos + 1).Trim;

      if SameText(LPropName, 'Caption') then
        Result.Caption := StripQuotes(LPropValue);
    end;

    Inc(FPos);

    // Skip multi-line property values (indented continuations)
    while FPos < Length(FLines) do
    begin
      var LNextLine := FLines[FPos];
      var LNextTrim := LNextLine.Trim;
      if (LNextTrim = '') or (LNextTrim = 'end')
         or LNextTrim.StartsWith('object ') or LNextTrim.StartsWith('inherited ')
         or LNextTrim.StartsWith('inline ') or (LNextTrim.IndexOf('=') > 0) then
        Break;
      Inc(FPos);
    end;
  end;
end;

end.
