program TestDecryptAndVerify;

{$APPTYPE CONSOLE}

uses
  FireDAC.DApt,
  System.SysUtils, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait,
  DeepAxis.WeChat.Decrypt;

var
  LKeyMgr: TKeyManager;
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
  LDataDir, LSrcPath, LDecPath, LKeysPath: string;
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LWait: TFDGUIxWaitCursor;
begin
  Writeln('=== 解密并验证 ===');

  LKeyMgr := TKeyManager.Create;
  try
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
    if not LKeyMgr.LoadFromJSON(LKeysPath) then
    begin
      Writeln('X 加载密钥失败');
      Exit;
    end;

    LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage';
    LKeys := LKeyMgr.FindKeysForDir(LDataDir);
    Writeln('找到 ' + IntToStr(Length(LKeys)) + ' 个密钥');

    // 解密 contact.db
    for LEntry in LKeys do
    begin
      if LEntry.DbRelPath = 'contact\contact.db' then
      begin
        LSrcPath := TPath.Combine(LDataDir, 'contact\contact.db');
        Writeln('解密 contact.db...');
        LDecPath := TWeChatDecryptor.DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);
        if LDecPath = '' then
        begin
          Writeln('X 解密失败');
          Exit;
        end;
        Writeln('OK: ' + LDecPath);
        Break;
      end;
    end;

    // 验证
    Writeln('');
    Writeln('验证数据库...');
    LWait := TFDGUIxWaitCursor.Create(nil);
    try
      LConn := TFDConnection.Create(nil);
      try
        LConn.DriverName := 'SQLite';
        LConn.Params.Database := LDecPath;
        LConn.Open;
        Writeln('OK 数据库打开成功');

        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConn;
          LQuery.SQL.Text := 'SELECT COUNT(*) as cnt FROM contact';
          LQuery.Open;
          Writeln('联系人数量: ' + LQuery.Fields[0].AsString);
        finally
          LQuery.Free;
        end;

        LConn.Close;
      finally
        LConn.Free;
      end;
    finally
      LWait.Free;
    end;
  finally
    LKeyMgr.Free;
  end;

  Write('按回车退出...');
  Readln;
end.
