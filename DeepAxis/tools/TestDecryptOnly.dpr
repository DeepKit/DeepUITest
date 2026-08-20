program TestDecryptOnly;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DeepAxis.WeChat.Decrypt;

var
  LKeyMgr: TKeyManager;
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
  LDataDir, LSrcPath, LDecPath, LKeysPath: string;
begin
  LKeyMgr := TKeyManager.Create;
  try
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
    if not LKeyMgr.LoadFromJSON(LKeysPath) then
    begin
      Writeln('X 加载失败');
      Exit;
    end;
    Writeln('加载 ' + IntToStr(LKeyMgr.GetKeyCount) + ' 个密钥');

    LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage';
    LKeys := LKeyMgr.FindKeysForDir(LDataDir);
    Writeln('匹配 ' + IntToStr(Length(LKeys)) + ' 个');

    for LEntry in LKeys do
    begin
      if LEntry.DbRelPath = 'contact/contact.db' then
      begin
        LSrcPath := TPath.Combine(LDataDir, 'contact/contact.db');
        Writeln('源文件: ' + LSrcPath);
        Writeln('源文件大小: ' + IntToStr(TFile.GetSize(LSrcPath)));
        Writeln('');

        LDecPath := TWeChatDecryptor.DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);
        Writeln('解密路径: ' + LDecPath);

        if (LDecPath <> '') and TFile.Exists(LDecPath) then
        begin
          Writeln('解密文件大小: ' + IntToStr(TFile.GetSize(LDecPath)));

          // 读取前16字节看是否是SQLite头
          var LBytes := TFile.ReadAllBytes(LDecPath);
          if Length(LBytes) >= 16 then
          begin
            var LHeader := '';
            for var I := 0 to 15 do
              if (LBytes[I] >= 32) and (LBytes[I] < 127) then
                LHeader := LHeader + Chr(LBytes[I]);
            Writeln('文件头: ' + LHeader);
          end;
        end
        else
          Writeln('X 解密文件不存在');
        Break;
      end;
    end;
  finally
    LKeyMgr.Free;
  end;

  Write('按回车...');
  Readln;
end.
