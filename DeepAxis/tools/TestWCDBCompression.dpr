program TestWCDBCompression;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait, FireDAC.DApt, FireDAC.Stan.Async;

procedure DumpHex(const AData: TBytes; AMaxBytes: Integer = 64);
var
  I: Integer;
  LHex, LAscii: string;
  LCount: Integer;
begin
  LCount := Length(AData);
  if LCount > AMaxBytes then
    LCount := AMaxBytes;

  LHex := '';
  LAscii := '';
  for I := 0 to LCount - 1 do
  begin
    LHex := LHex + IntToHex(AData[I], 2) + ' ';
    if (AData[I] >= 32) and (AData[I] < 127) then
      LAscii := LAscii + Chr(AData[I])
    else
      LAscii := LAscii + '.';
    if ((I + 1) mod 16 = 0) or (I = LCount - 1) then
    begin
      Writeln(Format('  %.4x: %-48s  %s', [I - (I mod 16), LHex, LAscii]));
      LHex := '';
      LAscii := '';
    end;
  end;
end;

procedure CheckCompression;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LData: TBytes;
  LField: TField;
  LStream: TStream;
  LSize: Integer;
begin
  Writeln('=== WCDB 内容压缩分析 ===');
  Writeln('');

  LConn := TFDConnection.Create(nil);
  try
    LConn.DriverName := 'SQLite';
    LConn.Params.Database := 'D:\tmp\decrypted_dbs\message\message_0.db';
    LConn.Open;

    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;

      // 查看 wcdb_builtin_compression_record 表
      Writeln('--- wcdb_builtin_compression_record ---');
      LQuery.SQL.Text := 'SELECT * FROM wcdb_builtin_compression_record';
      LQuery.Open;
      while not LQuery.Eof do
      begin
        Writeln('  tableName=' + LQuery.FieldByName('tableName').AsString +
                ', columns=' + LQuery.FieldByName('columns').AsString +
                ', rowid=' + LQuery.FieldByName('rowid').AsString);
        LQuery.Next;
      end;
      LQuery.Close;
      Writeln('');

      // 用 CAST AS BLOB 读取原始字节
      LQuery.SQL.Text := 'SELECT local_id, local_type, WCDB_CT_message_content, ' +
        'CAST(message_content AS BLOB) as msg_blob, ' +
        'LENGTH(message_content) as msg_len ' +
        'FROM "Msg_c8528f4d430010b8ab15c67ed4e4de85" LIMIT 3';
      LQuery.Open;

      while not LQuery.Eof do
      begin
        Writeln(Format('  local_id=%s, type=%s, WCDB_CT=%s, msg_len=%s',
          [LQuery.FieldByName('local_id').AsString,
           LQuery.FieldByName('local_type').AsString,
           LQuery.FieldByName('WCDB_CT_message_content').AsString,
           LQuery.FieldByName('msg_len').AsString]));

        // 读取 BLOB
        LField := LQuery.FieldByName('msg_blob');
        if not LField.IsNull then
        begin
          LStream := TMemoryStream.Create;
          try
            TBlobField(LField).SaveToStream(LStream);
            LSize := LStream.Size;
            SetLength(LData, LSize);
            if LSize > 0 then
            begin
              LStream.Position := 0;
              LStream.ReadBuffer(LData[0], LSize);
            end;
            Writeln(Format('    msg_blob: %d bytes', [LSize]));
            if LSize > 0 then
              DumpHex(LData, Min(LSize, 80));

            // 检查是否是 zstd 魔数
            if LSize >= 4 then
            begin
              if (LData[0] = $28) and (LData[1] = $B5) and (LData[2] = $2F) and (LData[3] = $FD) then
                Writeln('    >>> zstd magic detected! (28 B5 2F FD)')
              else if (LData[0] = $28) and (LData[1] = $00) and (LData[2] = $B5) and (LData[3] = $00) then
                Writeln('    >>> zstd magic in UTF-16LE pattern detected! (28 00 B5 00 2F 00 FD xx)')
              else
                Writeln(Format('    >>> Not zstd. First 4 bytes: %02x %02x %02x %02x',
                  [LData[0], LData[1], LData[2], LData[3]]));
            end;
          finally
            LStream.Free;
          end;
        end
        else
          Writeln('    msg_blob: NULL');

        Writeln('');
        LQuery.Next;
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
    CheckCompression;
  except
    on E: Exception do
      Writeln('错误: ' + E.Message);
  end;
end.
