
{ ============================================================================
  DeepSpec.Delphi.PasParser

  Lightweight Pascal source parser. Extracts unit name, classes, and
  interfaces from .pas/.dpr files for module tree generation.

  Uses regex-style line scanning. Does NOT build a full AST.
  Limitations: nested types may be missed; complex generics simplified;
  conditional compilation not evaluated.
  ============================================================================ }

unit DeepSpec.Delphi.PasParser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TPasItemKind = (pikUnit, pikClass, pikInterface, pikRecord);

  TPasItem = record
    Kind: TPasItemKind;
    Name: string;
    AncestorOrInterface: string;
  end;

  TPasUnitInfo = class
  private
    FUnitName: string;
    FItems: TList<TPasItem>;
    FUsesList: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    {$WARN HIDING_MEMBER OFF}
    property UnitName: string read FUnitName write FUnitName;
    {$WARN HIDING_MEMBER DEFAULT}
    property Items: TList<TPasItem> read FItems;
    property UsesList: TList<string> read FUsesList;
  end;

  TPasParser = class
  private
    function StripComments(const ALine: string): string;
  public
    function ParseFile(const APath: string): TPasUnitInfo;
    function Parse(const AContent: string): TPasUnitInfo;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Character,
  System.RegularExpressions;

{ TPasUnitInfo }

constructor TPasUnitInfo.Create;
begin
  inherited Create;
  FItems := TList<TPasItem>.Create;
  FUsesList := TList<string>.Create;
end;

destructor TPasUnitInfo.Destroy;
begin
  FItems.Free;
  FUsesList.Free;
  inherited;
end;

{ TPasParser }

function TPasParser.StripComments(const ALine: string): string;
begin
  // Strip // comments
  var LIdx := ALine.IndexOf('//');
  if LIdx >= 0 then
    Result := ALine.Substring(0, LIdx)
  else
    Result := ALine;
  // Strip { } comments (single-line only)
  while True do
  begin
    var LStart := Result.IndexOf('{');
    if LStart < 0 then Break;
    var LEnd := Result.IndexOf('}', LStart);
    if LEnd < 0 then
    begin
      Result := Result.Substring(0, LStart);
      Break;
    end;
    Result := Result.Substring(0, LStart) + Result.Substring(LEnd + 1);
  end;
end;

function TPasParser.ParseFile(const APath: string): TPasUnitInfo;
begin
  Result := nil;
  if not TFile.Exists(APath) then Exit;
  try
    var LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
    Result := Parse(LContent);
  except
    // UTF-8 failed — try system default encoding (legacy GBK/ANSI files)
    try
      var LContent := TFile.ReadAllText(APath, TEncoding.Default);
      Result := Parse(LContent);
    except
      Result := nil;
    end;
  end;
end;

function TPasParser.Parse(const AContent: string): TPasUnitInfo;
const
  // Pascal identifier pattern
  IDENT_PATTERN = '[A-Za-z_][A-Za-z0-9_]*';
var
  LLines: TArray<string>;
  LInInterface, LInUses: Boolean;
  LUnitRegex, LClassRegex, LInterfaceRegex, LRecordRegex: TRegEx;
  LMatch: TMatch;
begin
  Result := TPasUnitInfo.Create;
  try
    var LNormalized := AContent.Replace(#13#10, #10).Replace(#13, #10);
    LLines := LNormalized.Split([#10]);

    LUnitRegex := TRegEx.Create('^\s*(unit|program|library)\s+(' + IDENT_PATTERN +
      '(\.' + IDENT_PATTERN + ')*)\s*[;\.]', [roIgnoreCase]);
    LClassRegex := TRegEx.Create('^\s*(' + IDENT_PATTERN +
      ')\s*=\s*class\s*(\(([^)]+)\))?', [roIgnoreCase]);
    LInterfaceRegex := TRegEx.Create('^\s*(' + IDENT_PATTERN +
      ')\s*=\s*interface\s*(\(([^)]+)\))?', [roIgnoreCase]);
    LRecordRegex := TRegEx.Create('^\s*(' + IDENT_PATTERN +
      ')\s*=\s*(packed\s+)?record\s*$', [roIgnoreCase]);

    LInInterface := False;
    LInUses := False;

    for var LRawLine in LLines do
    begin
      var LLine := StripComments(LRawLine);
      var LTrimmed := LLine.Trim;
      if LTrimmed = '' then Continue;

      // Unit declaration
      LMatch := LUnitRegex.Match(LLine);
      if LMatch.Success and (Result.UnitName = '') then
      begin
        Result.UnitName := LMatch.Groups[2].Value;
        Continue;
      end;

      // interface section marker
      if SameText(LTrimmed, 'interface') then
      begin
        LInInterface := True;
        Continue;
      end;
      if SameText(LTrimmed, 'implementation') then
      begin
        LInInterface := False;
        LInUses := False;
        Continue;
      end;

      // Uses clause
      if LInInterface and LTrimmed.ToLower.StartsWith('uses') then
      begin
        LInUses := True;
        // Remove "uses" keyword
        var LUsesContent := LTrimmed.Substring(4).Trim;
        // Process the rest inline
        var LParts := LUsesContent.Split([',', ';']);
        for var LPart in LParts do
        begin
          var LName := LPart.Trim;
          if LName <> '' then
            Result.UsesList.Add(LName);
        end;
        if LTrimmed.EndsWith(';') then
          LInUses := False;
        Continue;
      end;

      if LInUses then
      begin
        var LParts := LTrimmed.Split([',', ';']);
        for var LPart in LParts do
        begin
          var LName := LPart.Trim;
          if LName <> '' then
            Result.UsesList.Add(LName);
        end;
        if LTrimmed.EndsWith(';') then
          LInUses := False;
        Continue;
      end;

      // Class/Interface/Record declarations (only in interface section)
      if not LInInterface then Continue;

      LMatch := LClassRegex.Match(LLine);
      if LMatch.Success then
      begin
        var LItem: TPasItem;
        LItem.Kind := pikClass;
        LItem.Name := LMatch.Groups[1].Value;
        if LMatch.Groups.Count > 3 then
          LItem.AncestorOrInterface := LMatch.Groups[3].Value.Trim
        else
          LItem.AncestorOrInterface := '';
        Result.Items.Add(LItem);
        Continue;
      end;

      LMatch := LInterfaceRegex.Match(LLine);
      if LMatch.Success then
      begin
        var LItem: TPasItem;
        LItem.Kind := pikInterface;
        LItem.Name := LMatch.Groups[1].Value;
        if LMatch.Groups.Count > 3 then
          LItem.AncestorOrInterface := LMatch.Groups[3].Value.Trim
        else
          LItem.AncestorOrInterface := '';
        Result.Items.Add(LItem);
        Continue;
      end;

      LMatch := LRecordRegex.Match(LLine);
      if LMatch.Success then
      begin
        var LItem: TPasItem;
        LItem.Kind := pikRecord;
        LItem.Name := LMatch.Groups[1].Value;
        LItem.AncestorOrInterface := '';
        Result.Items.Add(LItem);
        Continue;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
