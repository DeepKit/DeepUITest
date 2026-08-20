program TestDecryptedDB;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait;

var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LWait: TFDGUIxWaitCursor;
  LDbPath: string;
begin
  Writeln('=== 测试解密后的数据库 ===');
  Writeln('');

  LWait := TFDGUIxWaitCursor.Create(nil);
  try
    LConn := TFDConnection.Create(nil);
    try
      LConn.DriverName := 'SQLite';

      // 测试 contact.db
      LDbPath := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage\contact\contact.db.decrypted';
      // 注意：需要用实际解密后的临时文件路径
      
      // 查找临时解密文件
      var LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepAxis_decrypted');
      if TDirectory.Exists(LTempDir) then
      begin
        var LFiles := TDirectory.GetFiles(LTempDir, '*.decrypted');
        for var LFile in LFiles do
        begin
          Writeln('测试: ' + ExtractFileName(LFile));
          try
            LConn.Params.Database := LFile;
            LConn.Open;
            
            LQuery := TFDQuery.Create(nil);
            try
              LQuery.Connection := LConn;
              LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' LIMIT 5';
              LQuery.Open;
              Writeln('  OK - 表数量: ' + IntToStr(LQuery.RecordCount));
              while not LQuery.Eof do
              begin
                Writeln('    - ' + LQuery.Fields[0].AsString);
                LQuery.Next;
              end;
            finally
              LQuery.Free;
            end;
            
            LConn.Close;
          except
            on E: Exception do
              Writeln('  X ' + E.Message);
          end;
          Writeln('');
        end;
      end
      else
        Writeln('未找到解密文件目录');
    finally
      LConn.Free;
    end;
  finally
    LWait.Free;
  end;

  Write('按回车退出...');
  Readln;
end.
