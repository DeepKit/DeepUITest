program TestReadWeChatDB;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait, FireDAC.DApt, FireDAC.Stan.Async;

procedure ReadContacts(const ADbPath: string);
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LCount: Integer;
begin
  Writeln('=== 读取联系人数据库 ===');
  Writeln('路径: ' + ADbPath);

  if not TFile.Exists(ADbPath) then
  begin
    Writeln('错误: 文件不存在');
    Exit;
  end;

  LConn := TFDConnection.Create(nil);
  try
    LConn.DriverName := 'SQLite';
    LConn.Params.Database := ADbPath;
    LConn.Open;

    Writeln('数据库已打开');

    // 列出所有表
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
      Writeln('');
    finally
      LQuery.Free;
    end;

    // 尝试读取联系人表
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      // 尝试常见的联系人表名
      LQuery.SQL.Text := 'SELECT COUNT(*) as cnt FROM contact';
      try
        LQuery.Open;
        LCount := LQuery.FieldByName('cnt').AsInteger;
        Writeln('contact 表记录数: ' + IntToStr(LCount));

        if LCount > 0 then
        begin
          // 先读取表结构
          LQuery.Close;
          LQuery.SQL.Text := 'SELECT sql FROM sqlite_master WHERE type=''table'' AND name=''contact''';
          LQuery.Open;
          Writeln('表结构:');
          if not LQuery.Eof then
            Writeln('  ' + LQuery.Fields[0].AsString);
          LQuery.Close;

          // 读取前 10 条联系人
          LQuery.SQL.Text := 'SELECT * FROM contact LIMIT 10';
          LQuery.Open;

          Writeln('');
          Writeln('字段列表:');
          for LCount := 0 to LQuery.FieldCount - 1 do
            Writeln('  [' + IntToStr(LCount) + '] ' + LQuery.Fields[LCount].FieldName);

          Writeln('');
          Writeln('前 10 条联系人:');
          LCount := 1;
          while not LQuery.Eof and (LCount <= 10) do
          begin
            Writeln(Format('  [%d] username=%s, nick_name=%s, alias=%s, remark=%s',
              [LCount,
               LQuery.FieldByName('username').AsString,
               LQuery.FieldByName('nick_name').AsString,
               LQuery.FieldByName('alias').AsString,
               LQuery.FieldByName('remark').AsString]));
            LQuery.Next;
            Inc(LCount);
          end;
        end;
      except
        on E: Exception do
          Writeln('读取 contact 表失败: ' + E.Message);
      end;
    finally
      LQuery.Free;
    end;

    LConn.Close;
  finally
    LConn.Free;
  end;
end;

procedure ScanMessageDB(const ADbPath: string);
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LQuery2: TFDQuery;
  LTableName: string;
  LMsgCount: Integer;
  LTotalMsg: Integer;
  LTableCount: Integer;
begin
  if not TFile.Exists(ADbPath) then
  begin
    Writeln(ExtractFileName(ADbPath) + ': 文件不存在');
    Exit;
  end;

  LConn := TFDConnection.Create(nil);
  try
    LConn.DriverName := 'SQLite';
    LConn.Params.Database := ADbPath;
    LConn.Open;

    LQuery := TFDQuery.Create(nil);
    LQuery2 := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery2.Connection := LConn;

      LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%'' ORDER BY name';
      LQuery.Open;

      LTotalMsg := 0;
      LTableCount := 0;
      while not LQuery.Eof do
      begin
        LTableName := LQuery.Fields[0].AsString;
        LQuery2.SQL.Text := 'SELECT COUNT(*) FROM "' + LTableName + '"';
        LQuery2.Open;
        LMsgCount := LQuery2.Fields[0].AsInteger;
        Inc(LTotalMsg, LMsgCount);
        Inc(LTableCount);
        LQuery2.Close;
        LQuery.Next;
      end;

      Writeln(ExtractFileName(ADbPath) + ': ' + IntToStr(LTableCount) + ' 张对话表, ' + IntToStr(LTotalMsg) + ' 条消息');
    finally
      LQuery.Free;
      LQuery2.Free;
    end;

    LConn.Close;
  finally
    LConn.Free;
  end;
end;

procedure ReadMessages(const ADbPath: string);
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LQuery2: TFDQuery;
  LCount: Integer;
  LFirstTable: string;
  LMsgCount: Integer;
  LFieldIdx: Integer;
begin
  Writeln('');
  Writeln('=== 读取消息数据库 ===');
  Writeln('路径: ' + ADbPath);

  if not TFile.Exists(ADbPath) then
  begin
    Writeln('错误: 文件不存在');
    Exit;
  end;

  LConn := TFDConnection.Create(nil);
  try
    LConn.DriverName := 'SQLite';
    LConn.Params.Database := ADbPath;
    LConn.Open;

    Writeln('数据库已打开');

    // 列出所有表
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
      Writeln('');
    finally
      LQuery.Free;
    end;

    // 尝试读取消息表 (Msg_<hash> 格式)
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;

      // 查看 Name2Id 表 - 将 hash 映射到联系人 username
      LQuery.SQL.Text := 'SELECT * FROM Name2Id LIMIT 10';
      LQuery.Open;
      Writeln('Name2Id 表 (hash -> contact 映射):');
      if LQuery.FieldCount > 0 then
      begin
        Writeln('  字段: ');
        for LFieldIdx := 0 to LQuery.FieldCount - 1 do
          Writeln('    [' + IntToStr(LFieldIdx) + '] ' + LQuery.Fields[LFieldIdx].FieldName);
      end;
      LCount := 1;
      while not LQuery.Eof and (LCount <= 10) do
      begin
        Writeln('  [' + IntToStr(LCount) + '] ' + LQuery.Fields[0].AsString + ' -> ' + LQuery.Fields[1].AsString);
        LQuery.Next;
        Inc(LCount);
      end;
      LQuery.Close;

      // 查看所有消息表及其记录数
      LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%'' ORDER BY name';
      LQuery.Open;
      Writeln('');
      Writeln('所有消息表:');
      while not LQuery.Eof do
      begin
        LFirstTable := LQuery.Fields[0].AsString;
        // 统计每个表记录数
        LQuery2 := TFDQuery.Create(nil);
        try
          LQuery2.Connection := LConn;
          LQuery2.SQL.Text := 'SELECT COUNT(*) as cnt FROM "' + LFirstTable + '"';
          LQuery2.Open;
          LMsgCount := LQuery2.FieldByName('cnt').AsInteger;
          Writeln('  - ' + LFirstTable + ' (' + IntToStr(LMsgCount) + ' 条消息)');
          LQuery2.Close;
        finally
          LQuery2.Free;
        end;
        LQuery.Next;
      end;
      LQuery.Close;

      // 读取第一个消息表的结构和记录
      LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%'' LIMIT 1';
      LQuery.Open;
      if not LQuery.Eof then
      begin
        LFirstTable := LQuery.Fields[0].AsString;
        Writeln('');
        Writeln('读取消息表详情: ' + LFirstTable);

        // 检查 WCDB_CT_message_content 值分布
        LQuery.Close;
        LQuery.SQL.Text := 'SELECT WCDB_CT_message_content, COUNT(*) as cnt FROM "' + LFirstTable + '" GROUP BY WCDB_CT_message_content';
        try
          LQuery.Open;
          Writeln('消息内容类型分布 (WCDB_CT_message_content):');
          while not LQuery.Eof do
          begin
            Writeln('  type=' + LQuery.Fields[0].AsString + ' -> ' + LQuery.Fields[1].AsString + ' 条');
            LQuery.Next;
          end;
          LQuery.Close;
        except
          on E: Exception do
            Writeln('查询失败: ' + E.Message);
        end;

        // 尝试读取 type=1 (文本消息) 的内容
        LQuery.SQL.Text := 'SELECT local_id, create_time, local_type, WCDB_CT_message_content, LENGTH(message_content), LENGTH(compress_content), message_content FROM "' + LFirstTable + '" WHERE local_type=1 LIMIT 3';
        try
          LQuery.Open;
          Writeln('');
          Writeln('文本消息 (local_type=1):');
          while not LQuery.Eof do
          begin
            Writeln(Format('  local_id=%s, time=%s, ct=%s, msg_len=%s, comp_len=%s',
              [LQuery.FieldByName('local_id').AsString,
               LQuery.FieldByName('create_time').AsString,
               LQuery.FieldByName('WCDB_CT_message_content').AsString,
               LQuery.FieldByName('LENGTH(message_content)').AsString,
               LQuery.FieldByName('LENGTH(compress_content)').AsString]));
            LQuery.Next;
          end;
        except
          on E: Exception do
            Writeln('查询失败: ' + E.Message);
        end;
      end;
    finally
      LQuery.Free;
    end;

    LConn.Close;
  finally
    LConn.Free;
  end;
end;

begin
  try
    Writeln('╔══════════════════════════════════════════════════════╗');
    Writeln('║  测试读取微信解密数据库                               ║');
    Writeln('╚══════════════════════════════════════════════════════╝');
    Writeln('');

    // 读取联系人
    ReadContacts('D:\tmp\decrypted_dbs\contact\contact.db');

    // 读取消息 (所有分片)
    ReadMessages('D:\tmp\decrypted_dbs\message\message_0.db');

    // 统计其他消息分片
    Writeln('');
    Writeln('=== 其他消息分片统计 ===');
    ScanMessageDB('D:\tmp\decrypted_dbs\message\message_1.db');
    ScanMessageDB('D:\tmp\decrypted_dbs\message\message_2.db');
    ScanMessageDB('D:\tmp\decrypted_dbs\message\message_3.db');
    ScanMessageDB('D:\tmp\decrypted_dbs\message\message_4.db');

    Writeln('');
    Writeln('测试完成');
  except
    on E: Exception do
      Writeln('错误: ' + E.Message);
  end;
end.
