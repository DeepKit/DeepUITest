(* ============================================================================
  UniFlow.Security.Filter - Sensitive Information Filter

  Version: 1.0
  Description: Filters and masks sensitive information in text content

  Features:
    - Sensitive word dictionary
    - Pattern-based detection (PII, credentials, etc.)
    - Content masking/redaction
    - Custom filter rules
    - Logging sanitization

  Usage:
    var Filter := TSensitiveFilter.Create;
    Filter.LoadPatterns('patterns.json');
    var Masked := Filter.Mask(Content);
  ============================================================================ *)

unit UniFlow.Security.Filter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.Generics.Collections,
  System.RegularExpressions,
  System.SyncObjs,
  System.IOUtils;

type
  // ============================================================================
  // Filter Types
  // ============================================================================

  /// <summary>
  /// Sensitive data category
  /// </summary>
  TSensitiveCategory = (
    scPII,           // Personally Identifiable Information
    scCredential,    // Passwords, API keys, tokens
    scFinancial,     // Credit cards, bank accounts
    scHealth,        // Medical information
    scCustom         // User-defined patterns
  );

  /// <summary>
  /// Detection result
  /// </summary>
  TSensitiveMatch = record
    Category: TSensitiveCategory;
    PatternName: string;
    MatchedText: string;
    StartPos: Integer;
    EndPos: Integer;
    Confidence: Double;
  end;

  /// <summary>
  /// Filter pattern definition
  /// </summary>
  TFilterPattern = class
  private
    FName: string;
    FCategory: TSensitiveCategory;
    FPattern: string;
    FRegex: TRegEx;
    FMaskChar: Char;
    FMaskMode: string;  // 'full', 'partial', 'hash'
    FEnabled: Boolean;
    FDescription: string;
  public
    constructor Create(const AName, APattern: string; ACategory: TSensitiveCategory);

    property Name: string read FName write FName;
    property Category: TSensitiveCategory read FCategory write FCategory;
    property Pattern: string read FPattern;
    property MaskChar: Char read FMaskChar write FMaskChar;
    property MaskMode: string read FMaskMode write FMaskMode;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Description: string read FDescription write FDescription;

    function Match(const AText: string): TArray<TMatch>;
  end;

  /// <summary>
  /// Word-based filter
  /// </summary>
  TSensitiveWordList = class
  private
    FWords: TDictionary<string, TSensitiveCategory>;
    FCaseSensitive: Boolean;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddWord(const AWord: string; ACategory: TSensitiveCategory);
    procedure AddWords(const AWords: TArray<string>; ACategory: TSensitiveCategory);
    procedure RemoveWord(const AWord: string);
    procedure Clear;

    function Contains(const AWord: string): Boolean;
    function GetCategory(const AWord: string): TSensitiveCategory;
    function FindInText(const AText: string): TArray<TSensitiveMatch>;

    procedure LoadFromFile(const AFilePath: string);
    procedure SaveToFile(const AFilePath: string);

    property CaseSensitive: Boolean read FCaseSensitive write FCaseSensitive;
  end;

  /// <summary>
  /// Filter scan result
  /// </summary>
  TFilterResult = class
  private
    FOriginalText: string;
    FMaskedText: string;
    FMatches: TList<TSensitiveMatch>;
    FHasSensitiveData: Boolean;
    FScanTimeMs: Double;
  public
    constructor Create;
    destructor Destroy; override;

    property OriginalText: string read FOriginalText write FOriginalText;
    property MaskedText: string read FMaskedText write FMaskedText;
    property Matches: TList<TSensitiveMatch> read FMatches;
    property HasSensitiveData: Boolean read FHasSensitiveData write FHasSensitiveData;
    property ScanTimeMs: Double read FScanTimeMs write FScanTimeMs;

    function ToJSON: TJSONObject;
  end;

  /// <summary>
  /// Filter event handler
  /// </summary>
  TOnSensitiveDetected = reference to procedure(const Match: TSensitiveMatch);

  /// <summary>
  /// Main sensitive information filter
  /// </summary>
  TSensitiveFilter = class
  private
    FPatterns: TObjectList<TFilterPattern>;
    FWordList: TSensitiveWordList;
    FLock: TCriticalSection;
    FEnabled: Boolean;
    FDefaultMaskChar: Char;
    FOnSensitiveDetected: TOnSensitiveDetected;

    procedure InitializeDefaultPatterns;
    function ApplyMask(const AText: string; const AMatch: TMatch;
      AMaskChar: Char; const AMaskMode: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Add a custom pattern
    /// </summary>
    procedure AddPattern(const AName, APattern: string;
      ACategory: TSensitiveCategory; const AMaskMode: string = 'partial');

    /// <summary>
    /// Remove a pattern
    /// </summary>
    procedure RemovePattern(const AName: string);

    /// <summary>
    /// Enable/disable a pattern
    /// </summary>
    procedure SetPatternEnabled(const AName: string; AEnabled: Boolean);

    /// <summary>
    /// Scan text for sensitive data
    /// </summary>
    function Scan(const AText: string): TFilterResult;

    /// <summary>
    /// Mask sensitive data in text
    /// </summary>
    function Mask(const AText: string): string;

    /// <summary>
    /// Check if text contains sensitive data
    /// </summary>
    function ContainsSensitive(const AText: string): Boolean;

    /// <summary>
    /// Get all matches without masking
    /// </summary>
    function FindAll(const AText: string): TArray<TSensitiveMatch>;

    /// <summary>
    /// Load patterns from JSON file
    /// </summary>
    procedure LoadPatterns(const AFilePath: string);

    /// <summary>
    /// Save patterns to JSON file
    /// </summary>
    procedure SavePatterns(const AFilePath: string);

    /// <summary>
    /// Sanitize for logging (aggressive masking)
    /// </summary>
    function SanitizeForLog(const AText: string): string;

    property Patterns: TObjectList<TFilterPattern> read FPatterns;
    property WordList: TSensitiveWordList read FWordList;
    property Enabled: Boolean read FEnabled write FEnabled;
    property DefaultMaskChar: Char read FDefaultMaskChar write FDefaultMaskChar;
    property OnSensitiveDetected: TOnSensitiveDetected read FOnSensitiveDetected write FOnSensitiveDetected;
  end;

  /// <summary>
  /// Log sanitizer for safe logging
  /// </summary>
  TLogSanitizer = class
  private
    FFilter: TSensitiveFilter;
    FMaxLength: Integer;
    FTruncateMarker: string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Sanitize text for logging
    /// </summary>
    function Sanitize(const AText: string): string;

    /// <summary>
    /// Sanitize JSON object for logging
    /// </summary>
    function SanitizeJSON(AJson: TJSONObject): TJSONObject;

    /// <summary>
    /// Sanitize key-value pairs
    /// </summary>
    function SanitizeKeyValue(const AKey, AValue: string): string;

    property Filter: TSensitiveFilter read FFilter;
    property MaxLength: Integer read FMaxLength write FMaxLength;
    property TruncateMarker: string read FTruncateMarker write FTruncateMarker;
  end;

  /// <summary>
  /// Helper function for category to string
  /// </summary>
  function CategoryToString(ACategory: TSensitiveCategory): string;
  function StringToCategory(const AStr: string): TSensitiveCategory;

implementation

uses
  System.Diagnostics;

function CategoryToString(ACategory: TSensitiveCategory): string;
begin
  case ACategory of
    scPII: Result := 'PII';
    scCredential: Result := 'CREDENTIAL';
    scFinancial: Result := 'FINANCIAL';
    scHealth: Result := 'HEALTH';
    scCustom: Result := 'CUSTOM';
  else
    Result := 'UNKNOWN';
  end;
end;

function StringToCategory(const AStr: string): TSensitiveCategory;
var
  UpperStr: string;
begin
  UpperStr := UpperCase(AStr);
  if UpperStr = 'PII' then Result := scPII
  else if UpperStr = 'CREDENTIAL' then Result := scCredential
  else if UpperStr = 'FINANCIAL' then Result := scFinancial
  else if UpperStr = 'HEALTH' then Result := scHealth
  else Result := scCustom;
end;

{ TFilterPattern }

constructor TFilterPattern.Create(const AName, APattern: string;
  ACategory: TSensitiveCategory);
begin
  inherited Create;
  FName := AName;
  FPattern := APattern;
  FCategory := ACategory;
  FMaskChar := '*';
  FMaskMode := 'partial';
  FEnabled := True;

  try
    FRegex := TRegEx.Create(APattern, [roIgnoreCase]);
  except
    FEnabled := False;
  end;
end;

function TFilterPattern.Match(const AText: string): TArray<TMatch>;
var
  MatchCollection: TMatchCollection;
  I: Integer;
begin
  if not FEnabled then
    Exit(nil);

  try
    MatchCollection := FRegex.Matches(AText);
    SetLength(Result, MatchCollection.Count);
    for I := 0 to MatchCollection.Count - 1 do
      Result[I] := MatchCollection[I];
  except
    SetLength(Result, 0);
  end;
end;

{ TSensitiveWordList }

constructor TSensitiveWordList.Create;
begin
  inherited;
  FWords := TDictionary<string, TSensitiveCategory>.Create;
  FLock := TCriticalSection.Create;
  FCaseSensitive := False;
end;

destructor TSensitiveWordList.Destroy;
begin
  FWords.Free;
  FLock.Free;
  inherited;
end;

procedure TSensitiveWordList.AddWord(const AWord: string;
  ACategory: TSensitiveCategory);
var
  Key: string;
begin
  if FCaseSensitive then
    Key := AWord
  else
    Key := LowerCase(AWord);

  FLock.Enter;
  try
    FWords.AddOrSetValue(Key, ACategory);
  finally
    FLock.Leave;
  end;
end;

procedure TSensitiveWordList.AddWords(const AWords: TArray<string>;
  ACategory: TSensitiveCategory);
var
  Word: string;
begin
  for Word in AWords do
    AddWord(Word, ACategory);
end;

procedure TSensitiveWordList.RemoveWord(const AWord: string);
var
  Key: string;
begin
  if FCaseSensitive then
    Key := AWord
  else
    Key := LowerCase(AWord);

  FLock.Enter;
  try
    FWords.Remove(Key);
  finally
    FLock.Leave;
  end;
end;

procedure TSensitiveWordList.Clear;
begin
  FLock.Enter;
  try
    FWords.Clear;
  finally
    FLock.Leave;
  end;
end;

function TSensitiveWordList.Contains(const AWord: string): Boolean;
var
  Key: string;
begin
  if FCaseSensitive then
    Key := AWord
  else
    Key := LowerCase(AWord);

  FLock.Enter;
  try
    Result := FWords.ContainsKey(Key);
  finally
    FLock.Leave;
  end;
end;

function TSensitiveWordList.GetCategory(const AWord: string): TSensitiveCategory;
var
  Key: string;
begin
  if FCaseSensitive then
    Key := AWord
  else
    Key := LowerCase(AWord);

  FLock.Enter;
  try
    if not FWords.TryGetValue(Key, Result) then
      Result := scCustom;
  finally
    FLock.Leave;
  end;
end;

function TSensitiveWordList.FindInText(const AText: string): TArray<TSensitiveMatch>;
var
  ResultList: TList<TSensitiveMatch>;
  Word: string;
  SearchText: string;
  Pos: Integer;
  Match: TSensitiveMatch;
begin
  ResultList := TList<TSensitiveMatch>.Create;
  try
    if FCaseSensitive then
      SearchText := AText
    else
      SearchText := LowerCase(AText);

    FLock.Enter;
    try
      for Word in FWords.Keys do
      begin
        Pos := 1;
        while Pos <= Length(SearchText) do
        begin
          Pos := System.Pos(Word, SearchText, Pos);
          if Pos = 0 then
            Break;

          Match.Category := FWords[Word];
          Match.PatternName := 'WordList';
          Match.MatchedText := Copy(AText, Pos, Length(Word));
          Match.StartPos := Pos;
          Match.EndPos := Pos + Length(Word) - 1;
          Match.Confidence := 1.0;
          ResultList.Add(Match);

          Inc(Pos, Length(Word));
        end;
      end;
    finally
      FLock.Leave;
    end;

    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

procedure TSensitiveWordList.LoadFromFile(const AFilePath: string);
var
  JsonStr: string;
  JsonArr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Word, CategoryStr: string;
begin
  if not TFile.Exists(AFilePath) then
    Exit;

  JsonStr := TFile.ReadAllText(AFilePath);
  JsonArr := TJSONObject.ParseJSONValue(JsonStr) as TJSONArray;
  if JsonArr = nil then
    Exit;

  try
    Clear;
    for I := 0 to JsonArr.Count - 1 do
    begin
      Item := JsonArr.Items[I] as TJSONObject;
      Word := Item.GetValue<string>('word', '');
      CategoryStr := Item.GetValue<string>('category', 'CUSTOM');
      if Word <> '' then
        AddWord(Word, StringToCategory(CategoryStr));
    end;
  finally
    JsonArr.Free;
  end;
end;

procedure TSensitiveWordList.SaveToFile(const AFilePath: string);
var
  JsonArr: TJSONArray;
  Item: TJSONObject;
  Pair: TPair<string, TSensitiveCategory>;
begin
  JsonArr := TJSONArray.Create;
  try
    FLock.Enter;
    try
      for Pair in FWords do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('word', Pair.Key);
        Item.AddPair('category', CategoryToString(Pair.Value));
        JsonArr.Add(Item);
      end;
    finally
      FLock.Leave;
    end;

    TFile.WriteAllText(AFilePath, JsonArr.Format(2));
  finally
    JsonArr.Free;
  end;
end;

{ TFilterResult }

constructor TFilterResult.Create;
begin
  inherited;
  FMatches := TList<TSensitiveMatch>.Create;
  FHasSensitiveData := False;
end;

destructor TFilterResult.Destroy;
begin
  FMatches.Free;
  inherited;
end;

function TFilterResult.ToJSON: TJSONObject;
var
  MatchesArr: TJSONArray;
  Match: TSensitiveMatch;
  MatchObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('has_sensitive_data', TJSONBool.Create(FHasSensitiveData));
  Result.AddPair('scan_time_ms', TJSONNumber.Create(FScanTimeMs));
  Result.AddPair('match_count', TJSONNumber.Create(FMatches.Count));

  MatchesArr := TJSONArray.Create;
  for Match in FMatches do
  begin
    MatchObj := TJSONObject.Create;
    MatchObj.AddPair('category', CategoryToString(Match.Category));
    MatchObj.AddPair('pattern', Match.PatternName);
    MatchObj.AddPair('start', TJSONNumber.Create(Match.StartPos));
    MatchObj.AddPair('end', TJSONNumber.Create(Match.EndPos));
    MatchObj.AddPair('confidence', TJSONNumber.Create(Match.Confidence));
    // Don't include actual matched text in result for security
    MatchesArr.Add(MatchObj);
  end;
  Result.AddPair('matches', MatchesArr);
end;

{ TSensitiveFilter }

constructor TSensitiveFilter.Create;
begin
  inherited;
  FPatterns := TObjectList<TFilterPattern>.Create;
  FWordList := TSensitiveWordList.Create;
  FLock := TCriticalSection.Create;
  FEnabled := True;
  FDefaultMaskChar := '*';

  InitializeDefaultPatterns;
end;

destructor TSensitiveFilter.Destroy;
begin
  FPatterns.Free;
  FWordList.Free;
  FLock.Free;
  inherited;
end;

procedure TSensitiveFilter.InitializeDefaultPatterns;
begin
  // Email addresses
  AddPattern('email', '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
    scPII, 'partial');

  // Phone numbers (various formats)
  AddPattern('phone_us', '\b\d{3}[-.]?\d{3}[-.]?\d{4}\b', scPII, 'partial');
  AddPattern('phone_intl', '\+\d{1,3}[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}',
    scPII, 'partial');

  // Social Security Number (US)
  AddPattern('ssn', '\b\d{3}-\d{2}-\d{4}\b', scPII, 'partial');

  // Credit card numbers
  AddPattern('credit_card', '\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b',
    scFinancial, 'partial');

  // API Keys (generic patterns)
  AddPattern('api_key_generic', '\b[A-Za-z0-9]{32,}\b', scCredential, 'partial');
  AddPattern('api_key_prefix', '(api[_-]?key|apikey|api_secret|secret_key)\s*[:=]\s*[''"]?([A-Za-z0-9_-]+)[''"]?',
    scCredential, 'full');

  // Bearer tokens
  AddPattern('bearer_token', 'Bearer\s+[A-Za-z0-9_-]+\.?[A-Za-z0-9_-]*\.?[A-Za-z0-9_-]*',
    scCredential, 'partial');

  // Passwords in config
  AddPattern('password_field', '(password|passwd|pwd|secret)\s*[:=]\s*[''"]?([^''"}\s]+)[''"]?',
    scCredential, 'full');

  // IP addresses
  AddPattern('ipv4', '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', scPII, 'partial');

  // Chinese ID card
  AddPattern('china_id', '\b\d{17}[\dXx]\b', scPII, 'partial');

  // Chinese phone
  AddPattern('china_phone', '\b1[3-9]\d{9}\b', scPII, 'partial');

  // Bank account (generic)
  AddPattern('bank_account', '\b\d{12,19}\b', scFinancial, 'partial');

  // JWT tokens
  AddPattern('jwt', 'eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*',
    scCredential, 'partial');

  // Private keys
  AddPattern('private_key', '-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----',
    scCredential, 'full');

  // AWS keys
  AddPattern('aws_access_key', 'AKIA[0-9A-Z]{16}', scCredential, 'partial');
  AddPattern('aws_secret_key', '[A-Za-z0-9/+=]{40}', scCredential, 'partial');
end;

procedure TSensitiveFilter.AddPattern(const AName, APattern: string;
  ACategory: TSensitiveCategory; const AMaskMode: string);
var
  Pattern: TFilterPattern;
begin
  FLock.Enter;
  try
    // Remove existing pattern with same name
    RemovePattern(AName);

    Pattern := TFilterPattern.Create(AName, APattern, ACategory);
    Pattern.MaskMode := AMaskMode;
    Pattern.MaskChar := FDefaultMaskChar;
    FPatterns.Add(Pattern);
  finally
    FLock.Leave;
  end;
end;

procedure TSensitiveFilter.RemovePattern(const AName: string);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FPatterns.Count - 1 downto 0 do
    begin
      if FPatterns[I].Name = AName then
      begin
        FPatterns.Delete(I);
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSensitiveFilter.SetPatternEnabled(const AName: string;
  AEnabled: Boolean);
var
  Pattern: TFilterPattern;
begin
  FLock.Enter;
  try
    for Pattern in FPatterns do
    begin
      if Pattern.Name = AName then
      begin
        Pattern.Enabled := AEnabled;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSensitiveFilter.ApplyMask(const AText: string; const AMatch: TMatch;
  AMaskChar: Char; const AMaskMode: string): string;
var
  MaskedPart: string;
  VisibleChars: Integer;
  I: Integer;
begin
  if AMaskMode = 'full' then
  begin
    // Mask entire match
    SetLength(MaskedPart, AMatch.Length);
    for I := 1 to Length(MaskedPart) do
      MaskedPart[I] := AMaskChar;
  end
  else if AMaskMode = 'hash' then
  begin
    // Replace with hash indicator
    MaskedPart := '[REDACTED]';
  end
  else // partial
  begin
    // Keep first and last few chars visible
    if AMatch.Length <= 4 then
    begin
      SetLength(MaskedPart, AMatch.Length);
      for I := 1 to Length(MaskedPart) do
        MaskedPart[I] := AMaskChar;
    end
    else
    begin
      VisibleChars := Min(2, AMatch.Length div 4);
      MaskedPart := Copy(AMatch.Value, 1, VisibleChars);
      for I := 1 to AMatch.Length - (VisibleChars * 2) do
        MaskedPart := MaskedPart + AMaskChar;
      MaskedPart := MaskedPart + Copy(AMatch.Value, AMatch.Length - VisibleChars + 1, VisibleChars);
    end;
  end;

  Result := Copy(AText, 1, AMatch.Index - 1) + MaskedPart +
            Copy(AText, AMatch.Index + AMatch.Length, MaxInt);
end;

function TSensitiveFilter.Scan(const AText: string): TFilterResult;
var
  Stopwatch: TStopwatch;
  Pattern: TFilterPattern;
  Matches: TArray<TMatch>;
  M: TMatch;
  SensitiveMatch: TSensitiveMatch;
  WordMatches: TArray<TSensitiveMatch>;
  WM: TSensitiveMatch;
  MaskedText: string;
  Offset: Integer;
  SortedMatches: TList<TSensitiveMatch>;
  I, J: Integer;
  Temp: TSensitiveMatch;
begin
  Result := TFilterResult.Create;
  Result.FOriginalText := AText;

  if not FEnabled or (AText = '') then
  begin
    Result.FMaskedText := AText;
    Exit;
  end;

  Stopwatch := TStopwatch.StartNew;

  // Collect all matches
  FLock.Enter;
  try
    // Pattern matches
    for Pattern in FPatterns do
    begin
      if not Pattern.Enabled then
        Continue;

      Matches := Pattern.Match(AText);
      for M in Matches do
      begin
        SensitiveMatch.Category := Pattern.Category;
        SensitiveMatch.PatternName := Pattern.Name;
        SensitiveMatch.MatchedText := M.Value;
        SensitiveMatch.StartPos := M.Index;
        SensitiveMatch.EndPos := M.Index + M.Length - 1;
        SensitiveMatch.Confidence := 0.9;
        Result.FMatches.Add(SensitiveMatch);

        if Assigned(FOnSensitiveDetected) then
          FOnSensitiveDetected(SensitiveMatch);
      end;
    end;

    // Word list matches
    WordMatches := FWordList.FindInText(AText);
    for WM in WordMatches do
    begin
      Result.FMatches.Add(WM);
      if Assigned(FOnSensitiveDetected) then
        FOnSensitiveDetected(WM);
    end;
  finally
    FLock.Leave;
  end;

  Result.FHasSensitiveData := Result.FMatches.Count > 0;

  // Sort matches by position (descending) for masking
  SortedMatches := TList<TSensitiveMatch>.Create;
  try
    for I := 0 to Result.FMatches.Count - 1 do
      SortedMatches.Add(Result.FMatches[I]);

    // Simple bubble sort by position descending
    for I := 0 to SortedMatches.Count - 2 do
      for J := I + 1 to SortedMatches.Count - 1 do
        if SortedMatches[J].StartPos > SortedMatches[I].StartPos then
        begin
          Temp := SortedMatches[I];
          SortedMatches[I] := SortedMatches[J];
          SortedMatches[J] := Temp;
        end;

    // Apply masking from end to start to preserve positions
    MaskedText := AText;
    for I := 0 to SortedMatches.Count - 1 do
    begin
      SensitiveMatch := SortedMatches[I];
      // Create a dummy TMatch for ApplyMask
      var DummyMatch: TMatch;
      // Manually construct mask
      var MaskLen := SensitiveMatch.EndPos - SensitiveMatch.StartPos + 1;
      var MaskedPart := StringOfChar(FDefaultMaskChar, MaskLen);

      // Keep partial visible for partial mode
      if MaskLen > 4 then
      begin
        MaskedPart := Copy(SensitiveMatch.MatchedText, 1, 2) +
                      StringOfChar(FDefaultMaskChar, MaskLen - 4) +
                      Copy(SensitiveMatch.MatchedText, MaskLen - 1, 2);
      end;

      MaskedText := Copy(MaskedText, 1, SensitiveMatch.StartPos - 1) +
                    MaskedPart +
                    Copy(MaskedText, SensitiveMatch.EndPos + 1, MaxInt);
    end;

    Result.FMaskedText := MaskedText;
  finally
    SortedMatches.Free;
  end;

  Stopwatch.Stop;
  Result.FScanTimeMs := Stopwatch.Elapsed.TotalMilliseconds;
end;

function TSensitiveFilter.Mask(const AText: string): string;
var
  ScanResult: TFilterResult;
begin
  ScanResult := Scan(AText);
  try
    Result := ScanResult.MaskedText;
  finally
    ScanResult.Free;
  end;
end;

function TSensitiveFilter.ContainsSensitive(const AText: string): Boolean;
var
  ScanResult: TFilterResult;
begin
  ScanResult := Scan(AText);
  try
    Result := ScanResult.HasSensitiveData;
  finally
    ScanResult.Free;
  end;
end;

function TSensitiveFilter.FindAll(const AText: string): TArray<TSensitiveMatch>;
var
  ScanResult: TFilterResult;
begin
  ScanResult := Scan(AText);
  try
    Result := ScanResult.Matches.ToArray;
  finally
    ScanResult.Free;
  end;
end;

procedure TSensitiveFilter.LoadPatterns(const AFilePath: string);
var
  JsonStr: string;
  JsonObj, PatternObj: TJSONObject;
  PatternsArr: TJSONArray;
  I: Integer;
  Name, Pattern, MaskMode, CategoryStr: string;
begin
  if not TFile.Exists(AFilePath) then
    Exit;

  JsonStr := TFile.ReadAllText(AFilePath);
  JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JsonObj = nil then
    Exit;

  try
    PatternsArr := JsonObj.GetValue('patterns') as TJSONArray;
    if PatternsArr = nil then
      Exit;

    for I := 0 to PatternsArr.Count - 1 do
    begin
      PatternObj := PatternsArr.Items[I] as TJSONObject;
      Name := PatternObj.GetValue<string>('name', '');
      Pattern := PatternObj.GetValue<string>('pattern', '');
      MaskMode := PatternObj.GetValue<string>('mask_mode', 'partial');
      CategoryStr := PatternObj.GetValue<string>('category', 'CUSTOM');

      if (Name <> '') and (Pattern <> '') then
        AddPattern(Name, Pattern, StringToCategory(CategoryStr), MaskMode);
    end;
  finally
    JsonObj.Free;
  end;
end;

procedure TSensitiveFilter.SavePatterns(const AFilePath: string);
var
  JsonObj: TJSONObject;
  PatternsArr: TJSONArray;
  PatternObj: TJSONObject;
  Pattern: TFilterPattern;
begin
  JsonObj := TJSONObject.Create;
  try
    PatternsArr := TJSONArray.Create;

    FLock.Enter;
    try
      for Pattern in FPatterns do
      begin
        PatternObj := TJSONObject.Create;
        PatternObj.AddPair('name', Pattern.Name);
        PatternObj.AddPair('pattern', Pattern.Pattern);
        PatternObj.AddPair('category', CategoryToString(Pattern.Category));
        PatternObj.AddPair('mask_mode', Pattern.MaskMode);
        PatternObj.AddPair('enabled', TJSONBool.Create(Pattern.Enabled));
        PatternObj.AddPair('description', Pattern.Description);
        PatternsArr.Add(PatternObj);
      end;
    finally
      FLock.Leave;
    end;

    JsonObj.AddPair('patterns', PatternsArr);
    TFile.WriteAllText(AFilePath, JsonObj.Format(2));
  finally
    JsonObj.Free;
  end;
end;

function TSensitiveFilter.SanitizeForLog(const AText: string): string;
begin
  // More aggressive masking for logs
  Result := Mask(AText);
  // Also truncate very long content
  if Length(Result) > 1000 then
    Result := Copy(Result, 1, 1000) + '... [TRUNCATED]';
end;

{ TLogSanitizer }

constructor TLogSanitizer.Create;
begin
  inherited;
  FFilter := TSensitiveFilter.Create;
  FMaxLength := 2000;
  FTruncateMarker := '... [TRUNCATED]';
end;

destructor TLogSanitizer.Destroy;
begin
  FFilter.Free;
  inherited;
end;

function TLogSanitizer.Sanitize(const AText: string): string;
begin
  Result := FFilter.Mask(AText);

  if Length(Result) > FMaxLength then
    Result := Copy(Result, 1, FMaxLength - Length(FTruncateMarker)) + FTruncateMarker;
end;

function TLogSanitizer.SanitizeJSON(AJson: TJSONObject): TJSONObject;
var
  Pair: TJSONPair;
  I: Integer;
  SanitizedValue: string;
  NewValue: TJSONValue;
begin
  Result := TJSONObject.Create;

  for I := 0 to AJson.Count - 1 do
  begin
    Pair := AJson.Pairs[I];

    if Pair.JsonValue is TJSONString then
    begin
      SanitizedValue := SanitizeKeyValue(Pair.JsonString.Value,
        (Pair.JsonValue as TJSONString).Value);
      NewValue := TJSONString.Create(SanitizedValue);
    end
    else if Pair.JsonValue is TJSONObject then
    begin
      NewValue := SanitizeJSON(Pair.JsonValue as TJSONObject);
    end
    else
    begin
      NewValue := Pair.JsonValue.Clone as TJSONValue;
    end;

    Result.AddPair(Pair.JsonString.Value, NewValue);
  end;
end;

function TLogSanitizer.SanitizeKeyValue(const AKey, AValue: string): string;
var
  SensitiveKeys: TArray<string>;
  Key: string;
  LowerKey: string;
begin
  // Keys that should always be fully masked
  SensitiveKeys := ['password', 'passwd', 'pwd', 'secret', 'token', 'api_key',
    'apikey', 'auth', 'authorization', 'credential', 'private_key', 'access_key',
    'secret_key', 'session_id', 'cookie'];

  LowerKey := LowerCase(AKey);

  for Key in SensitiveKeys do
  begin
    if Pos(Key, LowerKey) > 0 then
    begin
      Result := '[REDACTED]';
      Exit;
    end;
  end;

  // Apply normal filter for other values
  Result := FFilter.Mask(AValue);
end;

end.
