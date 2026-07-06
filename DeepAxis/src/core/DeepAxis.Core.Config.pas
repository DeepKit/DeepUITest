unit DeepAxis.Core.Config;

interface

uses
  System.SysUtils, System.IniFiles, System.IOUtils,
  DeepAxis.Core.Base;

type
  /// <summary>
  ///   配置��理：使用项目目录下的 DeepAxis.ini 文件。
  ///   独立于 DeepBase，不依赖任何外部框架。
  /// </summary>
  TDeepAxisConfig = class
  private
    class function GetIniPath: string; static;
    class var FIni: TMemIniFile;
    class function GetIni: TMemIniFile; static;
  public
    class constructor Create;
    class destructor Destroy;

    class function GetProfile: string;
    class procedure SetProfile(const AValue: string);
    class function GetPollIntervalForeground: Integer;
    class function GetPollIntervalBackground: Integer;
    class function GetAdMaxCount: Integer;
    class function GetWeChatPath: string;
    class procedure SetWeChatPath(const APath: string);
    class function GetWeChatDataPath: string;
    class procedure SetWeChatDataPath(const APath: string);
    class function GetDecryptedDataPath: string;
    class procedure SetDecryptedDataPath(const APath: string);
    class function GetCapability(const AKey: string): string;
    class procedure SetCapability(const AKey, AValue: string);
    class function GetDB2Path: string;
  end;

implementation

{ TDeepAxisConfig }

class constructor TDeepAxisConfig.Create;
begin
  FIni := nil;
end;

class destructor TDeepAxisConfig.Destroy;
begin
  FIni.Free;
end;

class function TDeepAxisConfig.GetIniPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepAxis.ini');
end;

class function TDeepAxisConfig.GetIni: TMemIniFile;
begin
  if FIni = nil then
    FIni := TMemIniFile.Create(GetIniPath);
  Result := FIni;
end;

class function TDeepAxisConfig.GetProfile: string;
begin
  Result := GetIni.ReadString('DeepAxis', 'Profile', 'personal_full');
end;

class procedure TDeepAxisConfig.SetProfile(const AValue: string);
begin
  GetIni.WriteString('DeepAxis', 'Profile', AValue);
  GetIni.UpdateFile;
end;

class function TDeepAxisConfig.GetPollIntervalForeground: Integer;
begin
  Result := GetIni.ReadInteger('DeepAxis', 'PollForeground', POLL_INTERVAL_FOREGROUND);
end;

class function TDeepAxisConfig.GetPollIntervalBackground: Integer;
begin
  Result := GetIni.ReadInteger('DeepAxis', 'PollBackground', POLL_INTERVAL_BACKGROUND);
end;

class function TDeepAxisConfig.GetAdMaxCount: Integer;
begin
  Result := GetIni.ReadInteger('DeepAxis', 'AdMaxCount', AD_MAX_COUNT);
end;

class function TDeepAxisConfig.GetWeChatPath: string;
begin
  Result := GetIni.ReadString('DeepAxis', 'WeChatPath', '');
end;

class procedure TDeepAxisConfig.SetWeChatPath(const APath: string);
begin
  GetIni.WriteString('DeepAxis', 'WeChatPath', APath);
  GetIni.UpdateFile;
end;

class function TDeepAxisConfig.GetWeChatDataPath: string;
begin
  Result := GetIni.ReadString('DeepAxis', 'WeChatDataPath', '');
end;

class procedure TDeepAxisConfig.SetWeChatDataPath(const APath: string);
begin
  GetIni.WriteString('DeepAxis', 'WeChatDataPath', APath);
  GetIni.UpdateFile;
end;

class function TDeepAxisConfig.GetDecryptedDataPath: string;
begin
  Result := GetIni.ReadString('DeepAxis', 'DecryptedDataPath', '');
end;

class procedure TDeepAxisConfig.SetDecryptedDataPath(const APath: string);
begin
  GetIni.WriteString('DeepAxis', 'DecryptedDataPath', APath);
  GetIni.UpdateFile;
end;

class function TDeepAxisConfig.GetCapability(const AKey: string): string;
begin
  Result := GetIni.ReadString('Capabilities', AKey, 'on');
end;

class procedure TDeepAxisConfig.SetCapability(const AKey, AValue: string);
begin
  GetIni.WriteString('Capabilities', AKey, AValue);
  GetIni.UpdateFile;
end;

class function TDeepAxisConfig.GetDB2Path: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepAxis.Data.db');
end;

end.