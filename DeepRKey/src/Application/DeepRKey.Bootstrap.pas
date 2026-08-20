unit DeepRKey.Bootstrap;

interface

uses
  DeepRKey.Interfaces;

type
  /// <summary>应用启动引导器</summary>
  TBootstrap = class
  private
    class var FConfig: IRKeyConfig;
    class var FLogger: IRKeyLogger;
    class var FI18n: IRKeyI18n;
  public
    class procedure Initialize;
    class procedure Finalize;

    class property Config: IRKeyConfig read FConfig;
    class property Logger: IRKeyLogger read FLogger;
    class property I18n: IRKeyI18n read FI18n;
  end;

implementation

uses
  System.SysUtils,
  {$IFDEF USE_DEEPBASE}
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,  // Registers FireDAC connection adapter (initialization section)
  DeepRKey.DeepBaseAdapter,
  {$ELSE}
  DeepRKey.StubAdapter,
  {$ENDIF}
  Winapi.Windows;

{ TBootstrap }

class procedure TBootstrap.Initialize;
begin
  // Detect Windows display language, switch to Chinese if zh-CN
  var langCode := 'en';
  var langId := GetUserDefaultUILanguage;
  // LANGID: primary language ID for Chinese = 0x04
  if (langId and $FF) = $04 then
    langCode := 'zh-CN';

  {$IFDEF USE_DEEPBASE}
  // v0.2+ 内部构建：初始化 DeepBase (T-201/202/203)
  DeepBase.Manager.DeepBase.InitializeOrRaise;
  FConfig := TDeepBaseConfigAdapter.Create;
  FLogger := TDeepBaseLoggerAdapter.Create;
  FI18n := TDeepBaseI18nAdapter.Create(langCode);
  FLogger.Info(Format('DeepRKey starting (DeepBase mode, lang=%s)', [langCode]), 'Bootstrap');
  {$ELSE}
  // v0.1 MVP 默认路径：Stub 适配器
  FConfig := TStubConfig.Create;
  FLogger := TStubLogger.Create;
  FI18n := TStubI18n.Create(langCode);
  FLogger.Info(Format('DeepRKey starting (Stub mode, lang=%s)', [langCode]), 'Bootstrap');
  {$ENDIF}
end;

class procedure TBootstrap.Finalize;
begin
  if FLogger <> nil then
    FLogger.Info('DeepRKey shutting down', 'Bootstrap');
  FConfig := nil;
  FLogger := nil;
  FI18n := nil;
  {$IFDEF USE_DEEPBASE}
  DeepBase.Manager.DeepBase.Finalize;
  {$ENDIF}
end;

end.