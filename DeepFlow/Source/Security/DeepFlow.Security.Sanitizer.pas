{ ============================================================================
  UniFlow.Security.Sanitizer - Input Sanitization Module

  Version: 1.0
  Description: Provides input sanitization to prevent injection attacks

  Features:
    - HTML entity encoding
    - SQL injection prevention
    - Path traversal prevention
    - String length limiting
    - Whitespace normalization
    - Control character removal
    - URL validation

  Usage:
    var Safe := TSanitizer.SanitizeHTML(UserInput);
    var Safe := TSanitizer.SanitizePath(FilePath);
    var Safe := TSanitizer.Sanitize(Input, [soHTML, soTrim, soMaxLength]);
  ============================================================================ }

unit UniFlow.Security.Sanitizer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.RegularExpressions,
  System.NetEncoding,
  System.Generics.Collections;

type
  /// <summary>
  /// Sanitization options
  /// </summary>
  TSanitizeOption = (
    soHTML,           // Encode HTML entities
    soSQL,            // Escape SQL special characters
    soPath,           // Prevent path traversal
    soTrim,           // Trim whitespace
    soNormalize,      // Normalize whitespace
    soControlChars,   // Remove control characters
    soMaxLength,      // Enforce max length
    soLowerCase,      // Convert to lowercase
    soUpperCase       // Convert to uppercase
  );
  TSanitizeOptions = set of TSanitizeOption;

  /// <summary>
  /// Sanitization configuration
  /// </summary>
  TSanitizeConfig = record
    MaxLength: Integer;
    AllowedChars: string;  // Regex pattern for allowed characters
    ReplacementChar: Char;

    class function Default: TSanitizeConfig; static;
  end;

  /// <summary>
  /// Input sanitizer
  /// </summary>
  TSanitizer = class
  private
    class var FHTMLEntities: TDictionary<Char, string>;
    class var FSQLEscapeChars: TDictionary<Char, string>;

    class procedure InitHTMLEntities;
    class procedure InitSQLEscapeChars;
    class function ReDeepMoveControlChars(const S: string): string;
    class function NormalizeWhitespace(const S: string): string;
  public
    class constructor Create;
    class destructor Destroy;

    /// <summary>
    /// Sanitize string with specified options
    /// </summary>
    class function Sanitize(const Input: string; Options: TSanitizeOptions;
      const Config: TSanitizeConfig): string; overload;
    class function Sanitize(const Input: string; Options: TSanitizeOptions): string; overload;

    /// <summary>
    /// HTML entity encoding (&lt; &gt; &amp; &quot; etc.)
    /// </summary>
    class function SanitizeHTML(const Input: string): string;

    /// <summary>
    /// SQL special character escaping
    /// </summary>
    class function SanitizeSQL(const Input: string): string;

    /// <summary>
    /// Path traversal prevention (removes ../, ..\, etc.)
    /// </summary>
    class function SanitizePath(const Input: string): string;

    /// <summary>
    /// Validate and sanitize filename
    /// </summary>
    class function SanitizeFileName(const Input: string): string;

    /// <summary>
    /// Validate URL (returns empty if invalid)
    /// </summary>
    class function ValidateURL(const Input: string): string;

    /// <summary>
    /// Validate email format
    /// </summary>
    class function ValidateEmail(const Input: string): Boolean;

    /// <summary>
    /// Limit string length with ellipsis
    /// </summary>
    class function TruncateWithEllipsis(const Input: string; MaxLen: Integer): string;

    /// <summary>
    /// Check if string contains potentially dangerous patterns
    /// </summary>
    class function ContainsDangerousPatterns(const Input: string): Boolean;

    /// <summary>
    /// Strip all HTML tags
    /// </summary>
    class function StripHTMLTags(const Input: string): string;

    /// <summary>
    /// Escape for JSON string value
    /// </summary>
    class function EscapeJSON(const Input: string): string;
  end;

  /// <summary>
  /// Prompt injection detection
  /// </summary>
  TPromptGuard = class
  private
    class var FDangerousPatterns: TArray<string>;
    class procedure InitPatterns;
  public
    class constructor Create;

    /// <summary>
    /// Check if input contains potential prompt injection attempts
    /// </summary>
    class function DetectInjection(const Input: string): Boolean;

    /// <summary>
    /// Get list of detected injection patterns
    /// </summary>
    class function GetDetectedPatterns(const Input: string): TArray<string>;

    /// <summary>
    /// Sanitize prompt to reduce injection risk
    /// </summary>
    class function SanitizePrompt(const Input: string): string;
  end;

implementation

{ TSanitizeConfig }

class function TSanitizeConfig.Default: TSanitizeConfig;
begin
  Result.MaxLength := 10000;
  Result.AllowedChars := '';
  Result.ReplacementChar := '_';
end;

{ TSanitizer }

class constructor TSanitizer.Create;
begin
  FHTMLEntities := TDictionary<Char, string>.Create;
  FSQLEscapeChars := TDictionary<Char, string>.Create;
  InitHTMLEntities;
  InitSQLEscapeChars;
end;

class destructor TSanitizer.Destroy;
begin
  FHTMLEntities.Free;
  FSQLEscapeChars.Free;
end;

class procedure TSanitizer.InitHTMLEntities;
begin
  FHTMLEntities.Add('<', '&lt;');
  FHTMLEntities.Add('>', '&gt;');
  FHTMLEntities.Add('&', '&amp;');
  FHTMLEntities.Add('"', '&quot;');
  FHTMLEntities.Add('''', '&#39;');
  FHTMLEntities.Add('/', '&#47;');
end;

class procedure TSanitizer.InitSQLEscapeChars;
begin
  FSQLEscapeChars.Add('''', '''''');
  FSQLEscapeChars.Add('\', '\\');
  FSQLEscapeChars.Add('"', '\"');
  FSQLEscapeChars.Add(#0, '');
  FSQLEscapeChars.Add(#10, '\n');
  FSQLEscapeChars.Add(#13, '\r');
  FSQLEscapeChars.Add(#26, '\Z');
end;

class function TSanitizer.ReDeepMoveControlChars(const S: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S));
  try
    for C in S do
    begin
      // Keep printable chars, tabs, newlines
      if (Ord(C) >= 32) or (C in [#9, #10, #13]) then
        SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSanitizer.NormalizeWhitespace(const S: string): string;
begin
  // Replace multiple spaces with single space
  Result := TRegEx.Replace(S, '\s+', ' ');
  Result := Result.Trim;
end;

class function TSanitizer.Sanitize(const Input: string; Options: TSanitizeOptions;
  const Config: TSanitizeConfig): string;
begin
  Result := Input;

  if soControlChars in Options then
    Result := ReDeepMoveControlChars(Result);

  if soTrim in Options then
    Result := Result.Trim;

  if soNormalize in Options then
    Result := NormalizeWhitespace(Result);

  if soHTML in Options then
    Result := SanitizeHTML(Result);

  if soSQL in Options then
    Result := SanitizeSQL(Result);

  if soPath in Options then
    Result := SanitizePath(Result);

  if soLowerCase in Options then
    Result := Result.ToLower;

  if soUpperCase in Options then
    Result := Result.ToUpper;

  if (soMaxLength in Options) and (Config.MaxLength > 0) then
  begin
    if Length(Result) > Config.MaxLength then
      Result := Copy(Result, 1, Config.MaxLength);
  end;
end;

class function TSanitizer.Sanitize(const Input: string; Options: TSanitizeOptions): string;
begin
  Result := Sanitize(Input, Options, TSanitizeConfig.Default);
end;

class function TSanitizer.SanitizeHTML(const Input: string): string;
var
  SB: TStringBuilder;
  C: Char;
  Entity: string;
begin
  SB := TStringBuilder.Create(Length(Input) * 2);
  try
    for C in Input do
    begin
      if FHTMLEntities.TryGetValue(C, Entity) then
        SB.Append(Entity)
      else
        SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSanitizer.SanitizeSQL(const Input: string): string;
var
  SB: TStringBuilder;
  C: Char;
  Escaped: string;
begin
  SB := TStringBuilder.Create(Length(Input) * 2);
  try
    for C in Input do
    begin
      if FSQLEscapeChars.TryGetValue(C, Escaped) then
        SB.Append(Escaped)
      else
        SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSanitizer.SanitizePath(const Input: string): string;
begin
  Result := Input;
  // Remove path traversal sequences
  Result := StringReplace(Result, '../', '', [rfReplaceAll]);
  Result := StringReplace(Result, '..\', '', [rfReplaceAll]);
  Result := StringReplace(Result, '..%2F', '', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '..%5C', '', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%2e%2e%2f', '', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%2e%2e/', '', [rfReplaceAll, rfIgnoreCase]);
  // Remove absolute path indicators
  Result := StringReplace(Result, '/', '', []);
  Result := StringReplace(Result, '\', '', []);
  if (Length(Result) > 1) and (Result[2] = ':') then
    Result := Copy(Result, 3, MaxInt);
end;

class function TSanitizer.SanitizeFileName(const Input: string): string;
const
  InvalidChars = '<>:"/\|?*';
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(Input));
  try
    for C in Input do
    begin
      if (Pos(C, InvalidChars) = 0) and (Ord(C) >= 32) then
        SB.Append(C);
    end;
    Result := SB.ToString.Trim;
    // Prevent reserved names
    if Result.ToUpper.StartsWith('CON') or
       Result.ToUpper.StartsWith('PRN') or
       Result.ToUpper.StartsWith('AUX') or
       Result.ToUpper.StartsWith('NUL') then
      Result := '_' + Result;
  finally
    SB.Free;
  end;
end;

class function TSanitizer.ValidateURL(const Input: string): string;
const
  URLPattern = '^https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/[^\s]*)?$';
begin
  if TRegEx.IsMatch(Input, URLPattern) then
    Result := Input
  else
    Result := '';
end;

class function TSanitizer.ValidateEmail(const Input: string): Boolean;
const
  EmailPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
begin
  Result := TRegEx.IsMatch(Input, EmailPattern);
end;

class function TSanitizer.TruncateWithEllipsis(const Input: string; MaxLen: Integer): string;
begin
  if Length(Input) <= MaxLen then
    Result := Input
  else if MaxLen > 3 then
    Result := Copy(Input, 1, MaxLen - 3) + '...'
  else
    Result := Copy(Input, 1, MaxLen);
end;

class function TSanitizer.ContainsDangerousPatterns(const Input: string): Boolean;
const
  Patterns: array[0..9] of string = (
    '<script',
    'javascript:',
    'data:text/html',
    'onerror=',
    'onclick=',
    'onload=',
    'eval(',
    'expression(',
    'vbscript:',
    'onmouseover='
  );
var
  LowerInput: string;
  Pattern: string;
begin
  LowerInput := Input.ToLower;
  for Pattern in Patterns do
  begin
    if LowerInput.Contains(Pattern) then
      Exit(True);
  end;
  Result := False;
end;

class function TSanitizer.StripHTMLTags(const Input: string): string;
begin
  Result := TRegEx.Replace(Input, '<[^>]+>', '');
end;

class function TSanitizer.EscapeJSON(const Input: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(Input) * 2);
  try
    for C in Input do
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
          SB.AppendFormat('\u%.4x', [Ord(C)])
        else
          SB.Append(C);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TPromptGuard }

class constructor TPromptGuard.Create;
begin
  InitPatterns;
end;

class procedure TPromptGuard.InitPatterns;
begin
  FDangerousPatterns := [
    'ignore previous',
    'ignore above',
    'ignore all previous',
    'disregard previous',
    'disregard above',
    'forget previous',
    'forget your instructions',
    'new instructions:',
    'system prompt:',
    'you are now',
    'act as if',
    'pretend you are',
    'roleplay as',
    'jailbreak',
    'developer mode',
    'dan mode',
    'bypass',
    'override',
    '```system',
    '[system]',
    '###system',
    'admin override'
  ];
end;

class function TPromptGuard.DetectInjection(const Input: string): Boolean;
var
  LowerInput: string;
  Pattern: string;
begin
  LowerInput := Input.ToLower;
  for Pattern in FDangerousPatterns do
  begin
    if LowerInput.Contains(Pattern) then
      Exit(True);
  end;
  Result := False;
end;

class function TPromptGuard.GetDetectedPatterns(const Input: string): TArray<string>;
var
  LowerInput: string;
  Pattern: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    LowerInput := Input.ToLower;
    for Pattern in FDangerousPatterns do
    begin
      if LowerInput.Contains(Pattern) then
        List.Add(Pattern);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TPromptGuard.SanitizePrompt(const Input: string): string;
begin
  Result := Input;
  // Remove common delimiter patterns that could confuse the model
  Result := StringReplace(Result, '```', '` ` `', [rfReplaceAll]);
  Result := StringReplace(Result, '###', '# # #', [rfReplaceAll]);
  Result := StringReplace(Result, '---', '- - -', [rfReplaceAll]);
  // Normalize quotes
  Result := StringReplace(Result, '"', '''', [rfReplaceAll]);
end;

end.
