program TestDecryptSimple;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DeepAxis.WeChat.Decrypt;

procedure WriteLog(const AMsg: string);
begin
  Writeln(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

var
  LKeyMgr: TKeyManager;
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
  LDataDir, LSrcPath, LDecPath, LKeysPath: string;
  LContactPath, LMessage0Path: string;
begin
  WriteLog('=== 解密测试 ===');

  LKeyMgr := TKeyManager.Create;
  try
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
    WriteLog('密钥文件: ' + LKeysPath);

    if not LKeyMgr.LoadFromJSON(LKeysPath) then
    begin
      WriteLog('X 加载密钥失败');
      Exit;
    end;
    WriteLog('OK 加载 ' + IntToStr(LKeyMgr.GetKeyCount) + ' 个密钥');

    LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage';
    WriteLog('数据目录: ' + LDataDir);

    LKeys := LKeyMgr.FindKeysForDir(LDataDir);
    WriteLog('匹配密钥: ' + IntToStr(Length(LKeys)) + ' 个');
    WriteLog('');

    LContactPath := '';
    LMessage0Path := '';

    for LEntry in LKeys do
    begin
      LSrcPath := TPath.Combine(LDataDir, LEntry.DbRelPath.Replace('/', '\'));
      if not TFile.Exists(LSrcPath) then Continue;

      WriteLog('解密: ' + LEntry.DbRelPath);
      LDecPath := TWeChatDecryptor.DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);

      if LDecPath <> '' then
      begin
        WriteLog('  OK (' + IntToStr(TFile.GetSize(LDecPath)) + ' bytes)');
        var LFileName := TPath.GetFileName(LEntry.DbRelPath).ToLower;
        if LFileName = 'contact.db' then LContactPath := LDecPath;
        if LFileName = 'message_0.db' then LMessage0Path := LDecPath;
      end
      else
        WriteLog('  X 失败');
    end;

    WriteLog('');
    if (LContactPath <> '') and (LMessage0Path <> '') then
      WriteLog('=== 成功! ===')
    else
      WriteLog('=== 失败 ===');
  finally
    LKeyMgr.Free;
  end;

  Write('按回车退出...');
  Readln;
end.
