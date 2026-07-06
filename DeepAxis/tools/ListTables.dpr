program ListTables;

{$APPTYPE CONSOLE}

uses
  FireDAC.Stan.Async,
  System.SysUtils, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.DApt, FireDAC.Comp.UI, FireDAC.VCLUI.Wait,
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
  LKeyMgr := TKeyManager.Create;
  try
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
    LKeyMgr.LoadFromJSON(LKeysPath);
    LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage';
    LKeys := LKeyMgr.FindKeysForDir(LDataDir);

    for LEntry in LKeys do
    begin
      if LEntry.DbRelPath = 'contact\contact.db' then
      begin
        LSrcPath := TPath.Combine(LDataDir, 'contact\contact.db');
        LDecPath := TWeChatDecryptor.DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);
        Break;
      end;
    end;

    Writeln('解密文件: ' + LDecPath);
    Writeln('');

    LWait := TFDGUIxWaitCursor.Create(nil);
    try
      LConn := TFDConnection.Create(nil);
      try
        LConn.DriverName := 'SQLite';
        LConn.Params.Database := LDecPath;
        LConn.Open;

        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConn;
          LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' ORDER BY name';
          LQuery.Open;
          Writeln('表列表:');
          while not LQuery.Eof do
          begin
            Writeln('  - ' + LQuery.Fields[0].AsString);
            LQuery.Next;
          end;
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
