unit DeepRKey.DeepBaseAdapter;

interface

uses
  DeepRKey.Interfaces;

type
  /// <summary>DeepBase Config adapter — delegates to DeepBase.Config (SQLite-backed)</summary>
  /// <remarks>T-201: Replaces TStubConfig for USE_DEEPBASE builds.
  /// DeepBase writes are immediate (no separate Apply needed).</remarks>
  TDeepBaseConfigAdapter = class(TInterfacedObject, IRKeyConfig)
  public
    function ReadBool(const Key: string; Default: Boolean): Boolean;
    function ReadString(const Key, Default: string): string;
    function ReadInteger(const Key: string; Default: Integer): Integer;
    procedure WriteBool(const Key: string; Value: Boolean);
    procedure WriteString(const Key, Default: string);
    procedure WriteInteger(const Key: string; Value: Integer);
    procedure Apply;
  end;

  /// <summary>DeepBase Logger adapter — delegates to DeepBase.Logger (DB+File)</summary>
  /// <remarks>T-203: Structured logging via DeepBase. Category maps to Source parameter.</remarks>
  TDeepBaseLoggerAdapter = class(TInterfacedObject, IRKeyLogger)
  public
    procedure Info(const Msg, Category: string);
    procedure Warn(const Msg, Category: string);
    procedure Error(const Msg, Category: string);
    procedure Debug(const Msg: string);
  end;

  /// <summary>DeepBase I18n adapter — delegates to DeepBase.I18n (DB-backed translations)</summary>
  /// <remarks>T-201: Uses DeepBase.I18n engine with DB storage instead of in-memory stub.</remarks>
  TDeepBaseI18nAdapter = class(TInterfacedObject, IRKeyI18n)
  private
    FCurrentLang: string;
  public
    constructor Create(const ALangCode: string);
    function T(const Key, Default: string): string;
    procedure SetLanguage(const LangCode: string);
    function GetCurrentLanguage: string;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.Logging,
  DeepBase.i18n;

{ TDeepBaseConfigAdapter }

function TDeepBaseConfigAdapter.ReadBool(const Key: string; Default: Boolean): Boolean;
begin
  Result := UBConfig.GetConfigBool(Key, Default);
end;

function TDeepBaseConfigAdapter.ReadString(const Key, Default: string): string;
begin
  Result := UBConfig.GetConfig(Key, Default);
end;

function TDeepBaseConfigAdapter.ReadInteger(const Key: string; Default: Integer): Integer;
begin
  Result := UBConfig.GetConfigInt(Key, Default);
end;

procedure TDeepBaseConfigAdapter.WriteBool(const Key: string; Value: Boolean);
begin
  UBConfig.SetConfigBool(Key, Value);
end;

procedure TDeepBaseConfigAdapter.WriteString(const Key, Default: string);
begin
  UBConfig.SetConfig(Key, Default);
end;

procedure TDeepBaseConfigAdapter.WriteInteger(const Key: string; Value: Integer);
begin
  UBConfig.SetConfigInt(Key, Value);
end;

procedure TDeepBaseConfigAdapter.Apply;
begin
  // DeepBase writes are immediate — no separate flush needed.
  // Method exists to satisfy IRKeyConfig interface contract.
end;

{ TDeepBaseLoggerAdapter }

procedure TDeepBaseLoggerAdapter.Info(const Msg, Category: string);
begin
  UBLogger.Info(Msg, Category);
end;

procedure TDeepBaseLoggerAdapter.Warn(const Msg, Category: string);
begin
  UBLogger.Warn(Msg, Category);
end;

procedure TDeepBaseLoggerAdapter.Error(const Msg, Category: string);
begin
  UBLogger.Error(Msg, Category);
end;

procedure TDeepBaseLoggerAdapter.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  UBLogger.Debug(Msg, 'Debug');
  {$ENDIF}
end;

{ TDeepBaseI18nAdapter }

constructor TDeepBaseI18nAdapter.Create(const ALangCode: string);
begin
  FCurrentLang := ALangCode;
  // Set the DeepBase manager's current language
  DeepBase.Manager.DeepBase.CurrentLanguage := ALangCode;
end;

function TDeepBaseI18nAdapter.T(const Key, Default: string): string;
begin
  // Try to translate via DeepBase.I18n engine
  var translated := UBI18n.TranslateTo(Key, FCurrentLang);
  if translated <> '' then
    Result := translated
  else
    Result := Default;  // Fallback to source/default string
end;

procedure TDeepBaseI18nAdapter.SetLanguage(const LangCode: string);
begin
  FCurrentLang := LangCode;
  DeepBase.Manager.DeepBase.CurrentLanguage := LangCode;
end;

function TDeepBaseI18nAdapter.GetCurrentLanguage: string;
begin
  Result := FCurrentLang;
end;

end.
