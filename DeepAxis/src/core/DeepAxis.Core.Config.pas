unit DeepAxis.Core.Config;

interface

uses
  System.SysUtils, System.IniFiles, System.IOUtils, System.Classes, System.AnsiStrings,
  DeepAxis.Core.Base,
  DeepAxis.Config.DB1;

type
  /// <summary>
  ///   配置管理：从 INI 过渡到 ConfigDB 的双模式支持。
  ///   在 INI 文件存在时优先使用 INI（向后兼容），同时自动同步到 ConfigDB。
  ///   未来切换到纯 ConfigDB 模式。
  /// </summary>
  TDeepAxisConfig = class
  private
    class function GetIniPath: string; static;
    class var FIni: TMemIniFile;
    class var FConfigDB: TDeepAxisConfigDB1;
    class var FMigrated: Boolean;
    class function GetIni: TMemIniFile; static;
    class procedure InitializeMigration; static;
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
    class function GetKeysFilePath: string;
    
    // Migration status
    class property IsMigrated: Boolean read FMigrated;
  end;

implementation

{ TDeepAxisConfig }

class constructor TDeepAxisConfig.Create;
begin
  FIni := nil;
  FConfigDB := nil;
  FMigrated := False;
end;

class destructor TDeepAxisConfig.Destroy;
begin
  if Assigned(FIni) then
    FIni.Free;
  if Assigned(FConfigDB) then
  begin
    FConfigDB.Shutdown;
    FConfigDB.Free;
  end;
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

class procedure TDeepAxisConfig.InitializeMigration;
var
  IniPath: string;
  Ini: TMemIniFile;
begin
  if FMigrated then Exit;
  
  IniPath := GetIniPath;
  
  // Check if ConfigDB exists and is already initialized
  if Assigned(FConfigDB) then
    Exit;
    
  // Try to load from INI first
  if TFile.Exists(IniPath) then
  begin
    try
      Ini := TMemIniFile.Create(IniPath);
      try
        FConfigDB := GetDeepAxisConfigDB1;
        FConfigDB.Init;
        
        // Simple migration: just copy known configuration keys
        with FConfigDB do
        begin
          SetProfile(Ini.ReadString('DeepAxis', 'Profile', ''));
          SetPollIntervalForeground(Ini.ReadInteger('DeepAxis', 'PollForeground', 60000));
          SetPollIntervalBackground(Ini.ReadInteger('DeepAxis', 'PollBackground', 300000));
          SetAdMaxCount(Ini.ReadInteger('DeepAxis', 'AdMaxCount', 500));
          SetWeChatPath(Ini.ReadString('DeepAxis', 'WeChatPath', ''));
          SetWeChatDataPath(Ini.ReadString('DeepAxis', 'WeChatDataPath', ''));
          SetDecryptedDataPath(Ini.ReadString('DeepAxis', 'DecryptedDataPath', ''));
          
          // Copy Capabilities section
          var CapKeys := TStringList.Create;
          try
            Ini.ReadSectionValues('Capabilities', CapKeys);
            for var i := 0 to CapKeys.Count - 1 do
            begin
              var EqPos := Pos('=', CapKeys[i]);
              if EqPos > 0 then
              begin
                var KeyName := Copy(CapKeys[i], 1, EqPos - 1);
                var Value := Copy(CapKeys[i], EqPos + 1, Length(CapKeys[i]) - EqPos);
                SetCapability(KeyName, Value);
              end;
            end;
          finally
            CapKeys.Free;
          end;
        end;
        
        FMigrated := True;
      finally
        Ini.Free;
      end;
    except
      // If migration fails, fall back to INI-only mode
      on E: Exception do
        ; // Silent fallback
    end;
  end
  else
  begin
    // No INI file, use ConfigDB directly
    FConfigDB := GetDeepAxisConfigDB1;
    FConfigDB.Init;
    FMigrated := True;
  end;
end;

class function TDeepAxisConfig.GetProfile: string;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetProfile
  else
    Result := GetIni.ReadString('DeepAxis', 'Profile', 'personal_full');
end;

class procedure TDeepAxisConfig.SetProfile(const AValue: string);
begin
  InitializeMigration;
  // Dual-write: update both INI and ConfigDB
  if not (FMigrated and Assigned(FConfigDB)) then
  begin
    GetIni.WriteString('DeepAxis', 'Profile', AValue);
    GetIni.UpdateFile;
  end;
  
  if Assigned(FConfigDB) then
    FConfigDB.SetProfile(AValue);
end;

class function TDeepAxisConfig.GetPollIntervalForeground: Integer;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetPollIntervalForeground
  else
    Result := GetIni.ReadInteger('DeepAxis', 'PollForeground', POLL_INTERVAL_FOREGROUND);
end;

class function TDeepAxisConfig.GetPollIntervalBackground: Integer;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetPollIntervalBackground
  else
    Result := GetIni.ReadInteger('DeepAxis', 'PollBackground', POLL_INTERVAL_BACKGROUND);
end;

class function TDeepAxisConfig.GetAdMaxCount: Integer;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetAdMaxCount
  else
    Result := GetIni.ReadInteger('DeepAxis', 'AdMaxCount', AD_MAX_COUNT);
end;

class function TDeepAxisConfig.GetWeChatPath: string;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetWeChatPath
  else
    Result := GetIni.ReadString('DeepAxis', 'WeChatPath', '');
end;

class procedure TDeepAxisConfig.SetWeChatPath(const APath: string);
begin
  InitializeMigration;
  if not (FMigrated and Assigned(FConfigDB)) then
  begin
    GetIni.WriteString('DeepAxis', 'WeChatPath', APath);
    GetIni.UpdateFile;
  end;
  
  if Assigned(FConfigDB) then
    FConfigDB.SetWeChatPath(APath);
end;

class function TDeepAxisConfig.GetWeChatDataPath: string;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetWeChatDataPath
  else
    Result := GetIni.ReadString('DeepAxis', 'WeChatDataPath', '');
end;

class procedure TDeepAxisConfig.SetWeChatDataPath(const APath: string);
begin
  InitializeMigration;
  if not (FMigrated and Assigned(FConfigDB)) then
  begin
    GetIni.WriteString('DeepAxis', 'WeChatDataPath', APath);
    GetIni.UpdateFile;
  end;
  
  if Assigned(FConfigDB) then
    FConfigDB.SetWeChatDataPath(APath);
end;

class function TDeepAxisConfig.GetDecryptedDataPath: string;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetDecryptedDataPath
  else
    Result := GetIni.ReadString('DeepAxis', 'DecryptedDataPath', '');
end;

class procedure TDeepAxisConfig.SetDecryptedDataPath(const APath: string);
begin
  InitializeMigration;
  if not (FMigrated and Assigned(FConfigDB)) then
  begin
    GetIni.WriteString('DeepAxis', 'DecryptedDataPath', APath);
    GetIni.UpdateFile;
  end;
  
  if Assigned(FConfigDB) then
    FConfigDB.SetDecryptedDataPath(APath);
end;

class function TDeepAxisConfig.GetCapability(const AKey: string): string;
begin
  InitializeMigration;
  if Assigned(FConfigDB) then
    Result := FConfigDB.GetCapability(AKey)
  else
    Result := GetIni.ReadString('Capabilities', AKey, 'on');
end;

class procedure TDeepAxisConfig.SetCapability(const AKey, AValue: string);
begin
  InitializeMigration;
  if not (FMigrated and Assigned(FConfigDB)) then
  begin
    GetIni.WriteString('Capabilities', AKey, AValue);
    GetIni.UpdateFile;
  end;
  
  if Assigned(FConfigDB) then
    FConfigDB.SetCapability(AKey, AValue);
end;

class function TDeepAxisConfig.GetDB2Path: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeepAxis.Data.db');
end;

class function TDeepAxisConfig.GetKeysFilePath: string;
var
  LExeDir: string;
begin
  // 密钥路径唯一真相源。探测顺序需与 TWeChatScanner.FindSavedKeysPath
  // 保持一致，二者此前各自硬编码导致向导与连接流程判定不一致 (BUG-030)。
  LExeDir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(LExeDir, 'DeCrypt\keys\all_keys.json');
  if TFile.Exists(Result) then Exit;
  Result := TPath.Combine(LExeDir, '..\DeCrypt\keys\all_keys.json');
  if TFile.Exists(Result) then Exit;
  Result := 'D:\tmp\found_keys\all_keys.json';
  if TFile.Exists(Result) then Exit;
  Result := '';
end;

end.
