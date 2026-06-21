unit DeepRKey.StubAdapter;

interface

uses
  System.SysUtils, System.StrUtils, System.IOUtils, System.JSON,
  System.Classes, System.Generics.Collections,
  Winapi.Windows,
  DeepRKey.Interfaces,
  DeepBase.Storage.Interfaces, DeepBase.i18n, DeepBase.Consts, DeepBase.Types;

/// <summary>T-451: 获取用户数据目录（%LOCALAPPDATA%\DeepRKey\）</summary>
/// <remarks>适合存储配置/日志/布局等用户数据，避免写入 EXE 目录（Program Files 不可写）</remarks>
function GetDeepRKeyDataDir: string;

type
  /// <summary>Stub configuration adapter (INI file, v0.1 default)</summary>
  TStubConfig = class(TInterfacedObject, IRKeyConfig)
  private
    FData: TDictionary<string, string>;
    FDirty: Boolean;
    FFilePath: string;
    procedure Load;
    procedure Save;
  public
    constructor Create(const AFilePath: string = '');
    destructor Destroy; override;
    function ReadBool(const Key: string; Default: Boolean): Boolean;
    function ReadString(const Key, Default: string): string;
    function ReadInteger(const Key: string; Default: Integer): Integer;
    procedure WriteBool(const Key: string; Value: Boolean);
    procedure WriteString(const Key, Default: string);
    procedure WriteInteger(const Key: string; Value: Integer);
    procedure Apply;
  end;

  /// <summary>Stub logger adapter (OutputDebugString + file log)</summary>
  TStubLogger = class(TInterfacedObject, IRKeyLogger)
  private
    FLogPath: string;
    procedure WriteToFile(const Level, Msg, Category: string);
  public
    constructor Create(const ALogPath: string = '');
    procedure Info(const Msg, Category: string);
    procedure Warn(const Msg, Category: string);
    procedure Error(const Msg, Category: string);
    procedure Debug(const Msg: string);
  end;

  /// <summary>Memory-backed II18nStorage for stub mode</summary>
  TMemoryI18nStorage = class(TInterfacedObject, II18nStorage)
  private
    FData: TDictionary<string, TDictionary<string, string>>;
    FLanguages: TList<TLanguageInfo>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadTranslation(const SourceText, LangCode: string): string;
    function ReadTranslations(const LangCode: string): TDictionary<string, string>;
    procedure RecordMissingTranslation(const SourceText, LangCode: string);
    function ReadLanguages(EnabledOnly: Boolean): TLanguageInfoArray;
    function ReadDefaultLanguage(const Fallback: string): string;
    procedure UpsertTranslation(const SourceText, LangCode, TranslatedText: string);
    /// <summary>Load translations from a UTF-8 JSON file (stub convenience)</summary>
    procedure LoadFromJSON(const AFilePath: string);
  end;

  /// <summary>Stub i18n adapter — wraps DeepBase.i18n with in-memory storage</summary>
  TStubI18n = class(TInterfacedObject, IRKeyI18n)
  private
    FEngine: TDeepBaseI18n;
    FCurrentLang: string;
  public
    constructor Create(const ALangCode: string = 'zh-CN');
    destructor Destroy; override;
    function T(const Key, Default: string): string;
    procedure SetLanguage(const LangCode: string);
    function GetCurrentLanguage: string;
  end;

implementation

{ T-451: 用户数据目录 }

function GetDeepRKeyDataDir: string;
begin
  // 优先使用 %LOCALAPPDATA%（用户本地数据，不漫游）
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  if Result = '' then
  begin
    // 回退到 %APPDATA%
    Result := GetEnvironmentVariable('APPDATA');
    if Result = '' then
      // 最终回退到 EXE 目录（兼容无用户环境）
      Result := ExtractFilePath(ParamStr(0));
  end;
  Result := TPath.Combine(Result, 'DeepRKey');
  // 确保目录存在
  if not TDirectory.Exists(Result) then
    TDirectory.CreateDirectory(Result);
end;

{ TStubConfig }

constructor TStubConfig.Create(const AFilePath: string);
begin
  FData := TDictionary<string, string>.Create;
  FDirty := False;
  if AFilePath.IsEmpty then
    // T-451: 使用用户数据目录，避免写入 EXE 目录（Program Files 不可写）
    FFilePath := TPath.Combine(GetDeepRKeyDataDir, 'DeepRKey.ini')
  else
    FFilePath := AFilePath;
  Load;
end;

destructor TStubConfig.Destroy;
begin
  if FDirty then Save;
  FData.Free;
  inherited;
end;

procedure TStubConfig.Load;
begin
  if not TFile.Exists(FFilePath) then Exit;
  var lines := TFile.ReadAllLines(FFilePath);
  for var line in lines do
  begin
    var trimmed := line.Trim;
    if trimmed.IsEmpty or trimmed.StartsWith(';') or trimmed.StartsWith('#') then Continue;
    var eqPos := trimmed.IndexOf('=');
    if eqPos < 0 then Continue;
    var key := trimmed.Substring(0, eqPos).Trim;
    var value := trimmed.Substring(eqPos + 1).Trim;
    FData.AddOrSetValue(key, value);
  end;
end;

procedure TStubConfig.Save;
begin
  var lines := TStringList.Create;
  try
    for var pair in FData do
      lines.Add(pair.Key + '=' + pair.Value);
    lines.SaveToFile(FFilePath);
    FDirty := False;
  finally
    lines.Free;
  end;
end;

function TStubConfig.ReadBool(const Key: string; Default: Boolean): Boolean;
begin
  var s: string;
  if not FData.TryGetValue(Key, s) then Exit(Default);
  Result := SameText(s, 'true') or SameText(s, '1') or SameText(s, 'yes');
end;

function TStubConfig.ReadString(const Key, Default: string): string;
begin
  if not FData.TryGetValue(Key, Result) then
    Result := Default;
end;

function TStubConfig.ReadInteger(const Key: string; Default: Integer): Integer;
begin
  var s: string;
  if not FData.TryGetValue(Key, s) then Exit(Default);
  Result := StrToIntDef(s, Default);
end;

procedure TStubConfig.WriteBool(const Key: string; Value: Boolean);
begin
  FData.AddOrSetValue(Key, BoolToStr(Value, True));
  FDirty := True;
end;

procedure TStubConfig.WriteString(const Key, Default: string);
begin
  FData.AddOrSetValue(Key, Default);
  FDirty := True;
end;

procedure TStubConfig.WriteInteger(const Key: string; Value: Integer);
begin
  FData.AddOrSetValue(Key, IntToStr(Value));
  FDirty := True;
end;

procedure TStubConfig.Apply;
begin
  Save;
end;

{ TStubLogger }

constructor TStubLogger.Create(const ALogPath: string);
begin
  if ALogPath.IsEmpty then
    // T-451: 使用用户数据目录，避免写入 EXE 目录（Program Files 不可写）
    FLogPath := TPath.Combine(GetDeepRKeyDataDir, 'DeepRKey.log')
  else
    FLogPath := ALogPath;
end;

procedure TStubLogger.WriteToFile(const Level, Msg, Category: string);
begin
  var line := Format('%s [%s] [%s] %s', [
    FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), Level, Category, Msg]);
  OutputDebugString(PChar(line));

  // BUG-M1 修复：实际写入日志文件
  try
    TFile.AppendAllText(FLogPath, line + sLineBreak, TEncoding.UTF8);
  except
    on E: Exception do
      OutputDebugString(PChar('[DeepRKey] Log write failed: ' + E.Message));
  end;
end;

procedure TStubLogger.Info(const Msg, Category: string);
begin WriteToFile('INFO', Msg, Category); end;

procedure TStubLogger.Warn(const Msg, Category: string);
begin WriteToFile('WARN', Msg, Category); end;

procedure TStubLogger.Error(const Msg, Category: string);
begin WriteToFile('ERROR', Msg, Category); end;

procedure TStubLogger.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  WriteToFile('DEBUG', Msg, '');
  {$ENDIF}
end;

{ TMemoryI18nStorage }

constructor TMemoryI18nStorage.Create;
begin
  FData := TDictionary<string, TDictionary<string, string>>.Create;
  FLanguages := TList<TLanguageInfo>.Create;

  // Register zh-CN as enabled language
  var info: TLanguageInfo;
  info.LangCode := 'zh-CN';
  info.LangName := 'Chinese (Simplified)';
  info.NativeName := '简体中文';
  info.IsEnabled := True;
  info.IsDefault := True;
  FLanguages.Add(info);

  info.LangCode := 'en-US';
  info.LangName := 'English';
  info.NativeName := 'English';
  info.IsEnabled := True;
  info.IsDefault := False;
  FLanguages.Add(info);
end;

destructor TMemoryI18nStorage.Destroy;
begin
  for var pair in FData do
    pair.Value.Free;
  FData.Free;
  FLanguages.Free;
  inherited;
end;

function TMemoryI18nStorage.ReadTranslation(const SourceText, LangCode: string): string;
begin
  var dict: TDictionary<string, string>;
  if FData.TryGetValue(LangCode, dict) then
  begin
    if dict.TryGetValue(SourceText, Result) then
      Exit;
  end;
  Result := '';
end;

function TMemoryI18nStorage.ReadTranslations(const LangCode: string): TDictionary<string, string>;
begin
  if not FData.TryGetValue(LangCode, Result) then
    Result := nil;
end;

procedure TMemoryI18nStorage.RecordMissingTranslation(const SourceText, LangCode: string);
begin
  // Stub mode: silently ignore missing translations
end;

function TMemoryI18nStorage.ReadLanguages(EnabledOnly: Boolean): TLanguageInfoArray;
begin
  SetLength(Result, FLanguages.Count);
  var idx := 0;
  for var i := 0 to FLanguages.Count - 1 do
  begin
    if EnabledOnly and not FLanguages[i].IsEnabled then Continue;
    Result[idx] := FLanguages[i];
    Inc(idx);
  end;
  SetLength(Result, idx);
end;

function TMemoryI18nStorage.ReadDefaultLanguage(const Fallback: string): string;
begin
  for var lang in FLanguages do
    if lang.IsDefault then Exit(lang.LangCode);
  Result := Fallback;
end;

procedure TMemoryI18nStorage.UpsertTranslation(const SourceText, LangCode, TranslatedText: string);
begin
  var dict: TDictionary<string, string>;
  if not FData.TryGetValue(LangCode, dict) then
  begin
    dict := TDictionary<string, string>.Create;
    FData.Add(LangCode, dict);
  end;
  dict.AddOrSetValue(SourceText, TranslatedText);
end;

procedure TMemoryI18nStorage.LoadFromJSON(const AFilePath: string);
begin
  if not TFile.Exists(AFilePath) then Exit;
  try
    var content := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    var root := TJSONObject.ParseJSONValue(content) as TJSONObject;
    if root = nil then Exit;
    try
      for var pair in root do
      begin
        // Store each key under zh-CN
        UpsertTranslation(pair.JsonString.Value, 'zh-CN', pair.JsonValue.Value);
      end;
    finally
      root.Free;
    end;
  except
  end;
end;

{ TStubI18n }

constructor TStubI18n.Create(const ALangCode: string);
begin
  FCurrentLang := ALangCode;
  var storage := TMemoryI18nStorage.Create;

  // Load translations from external UTF-8 JSON file
  var jsonPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'translations.json');
  storage.LoadFromJSON(jsonPath);

  // Create DeepBase i18n engine with memory storage
  FEngine := TDeepBaseI18n.Create(storage as II18nStorage);
  FEngine.CurrentLanguage := ALangCode;
end;

destructor TStubI18n.Destroy;
begin
  FEngine.Free;
  // FStorage is owned by FEngine (via interface ref counting), don't free
  inherited;
end;

function TStubI18n.T(const Key, Default: string): string;
begin
  var translated := FEngine.TranslateTo(Key, FCurrentLang);
  if translated <> '' then
    Result := translated
  else
    Result := Default;
  OutputDebugString(PChar(Format('I18N: T("%s") lang=%s => "%s"',
    [Key, FCurrentLang, Result])));
end;

procedure TStubI18n.SetLanguage(const LangCode: string);
begin
  FCurrentLang := LangCode;
  FEngine.CurrentLanguage := LangCode;
end;

function TStubI18n.GetCurrentLanguage: string;
begin
  Result := FCurrentLang;
end;

end.