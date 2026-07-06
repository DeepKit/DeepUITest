program TestZstdRawExtract;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait, FireDAC.DApt, FireDAC.Stan.Async;

var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LField: TField;
  LStream: TMemoryStream;
  LData: TBytes;
  LSize: Integer;
  LOutFile: string;
  LType: Integer;
  LTypeIdx: Integer;
  LTypes: array[0..2] of Integer;
begin
  LTypes[0] := 1;   // 文本
  LTypes[1] := 3;   // 图片
  LTypes[2] := 49;  // 链接/文件
  LConn := TFDConnection.Create(nil);
  try
    LConn.DriverName := 'SQLite';
    LConn.Params.Database := 'D:\tmp\decrypted_dbs\message\message_0.db';
    LConn.Open;

    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      // 取各类消息各一条
      for LTypeIdx := 0 to 2 do
      begin
        LType := LTypes[LTypeIdx];
        LQuery.SQL.Text := 'SELECT local_id, local_type, CAST(message_content AS BLOB) as msg_blob, ' +
          'CAST(source AS BLOB) as src_blob ' +
          'FROM "Msg_c8528f4d430010b8ab15c67ed4e4de85" WHERE local_type=' + IntToStr(LType) + ' LIMIT 1';
        LQuery.Open;

        if not LQuery.Eof then
        begin
          Writeln(Format('--- local_type=%d, local_id=%s ---', [LType, LQuery.FieldByName('local_id').AsString]));

          // message_content
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
              LOutFile := Format('D:\tmp\wcdb_msg_type%d.zst', [LType]);
              TFile.WriteAllBytes(LOutFile, LData);
              Writeln(Format('  message_content: %d bytes -> %s', [LSize, LOutFile]));
            finally
              LStream.Free;
            end;
          end;

          // source
          LField := LQuery.FieldByName('src_blob');
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
              LOutFile := Format('D:\tmp\wcdb_source_type%d.zst', [LType]);
              TFile.WriteAllBytes(LOutFile, LData);
              Writeln(Format('  source: %d bytes -> %s', [LSize, LOutFile]));
            finally
              LStream.Free;
            end;
          end;
        end
        else
          Writeln(Format('--- local_type=%d: 无记录 ---', [LType]));

        LQuery.Close;
      end;
    finally
      LQuery.Free;
    end;

    LConn.Close;
  finally
    LConn.Free;
  end;
end.
