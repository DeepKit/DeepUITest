program TestDecryptDetailed;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DeepAxis.Core.Base, DeepAxis.Core.Config,
  System.Math,
  DeepAxis.WeChat.Decrypt;

procedure WriteLog(const AMsg: string);
begin
  Writeln(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

var
  LKeyMgr: TKeyManager;
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
  LDataDir, LSrcPath, LDecPath: string;
  LContactPath, LMessage0Path, LSessionPath: string;
  LKeysPath: string;
begin
  WriteLog('=== 详细解密测试 ===');
  WriteLog('');

  LKeyMgr := TKeyManager.Create;
  try
    WriteLog('[1] 加载密钥...');
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
    if not LKeyMgr.LoadFromJSON(LKeysPath) then
    begin
      WriteLog('  X 加载失败');
      Exit;
    end;
    WriteLog('  OK 加载 ' + IntToStr(LKeyMgr.GetKeyCount) + ' 个密钥');

    WriteLog('');
    WriteLog('[2] 微信数据目录: D:\xwechat_files\wxid_swkc1c57428i21_b5a0');
    LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0';

    WriteLog('');
    WriteLog('[3] 查找匹配的密钥...');
    LKeys := LKeyMgr.FindKeysForDir(LDataDir);
    WriteLog('  找到 ' + IntToStr(Length(LKeys)) + ' 个密钥');

    WriteLog('');
    WriteLog('[4] 尝试解密...');
    for LEntry in LKeys do
    begin
      LSrcPath := TPath.Combine(LDataDir, LEntry.DbRelPath.Replace('/', '\'));
      if not TFile.Exists(LSrcPath) then
      begin
        WriteLog('  跳过 ' + LEntry.DbRelPath + ' (源文件不存在)');
        Continue;
      end;

      WriteLog('  解密 ' + LEntry.DbRelPath + '...');
      LDecPath := TWeChatDecryptor.DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);
      if LDecPath <> '' then
      begin
        WriteLog('    OK -> ' + ExtractFileName(LDecPath));
        if TFile.Exists(LDecPath) then
          WriteLog('    大小: ' + IntToStr(TFile.GetSize(LDecPath)) + ' bytes');

        var LFileName := TPath.GetFileName(LEntry.DbRelPath).ToLower;
        if LFileName = 'contact.db' then LContactPath := LDecPath
        else if LFileName = 'message_0.db' then LMessage0Path := LDecPath
        else if LFileName = 'session.db' then LSessionPath := LDecPath;
      end
      else
        WriteLog('    X 失败');
    end;

    WriteLog('');
    if LContactPath <> "" then WriteLog("  Contact: OK") else WriteLog("  Contact: X");
    if LMessage0Path <> "" then WriteLog("  Message_0: OK") else WriteLog("  Message_0: X");
    if LSessionPath <> "" then WriteLog("  Session: OK") else WriteLog("  Session: X");
    WriteLog('  Session: ' + IfThen(LSessionPath <> '', 'OK', 'X'));
  finally
    LKeyMgr.Free;
  end;

  Writeln('');
  Write('按回车键退出...');
  Readln;
end.
