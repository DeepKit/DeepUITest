program TestEncoding;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef, FireDAC.Stan.Param,
  DeepAxis.Core.Base,
  DeepAxis.Core.DataTypes,
  DeepAxis.WeChat.Zstd;

var
  FConnection: TFDConnection;

procedure Diagnose;
var
  LQuery: TFDQuery;
  LZstd: TZstdDecompressor;
  LMsgBlob: TBytes;
  LDecompressed: TBytes;
  LStream: TMemoryStream;
  LRowCount, I: Integer;
  LTableName: string;
  LBytesFile, LUtf8File, LGbkFile: string;
  LUtf8Str, LGbkStr: string;
  LGbkEnc: TEncoding;
  LIsValidUtf8: Boolean;
  LFirst20: string;
begin
  LZstd := TZstdDecompressor.Create;
  LQuery := TFDQuery.Create(nil);
  LStream := TMemoryStream.Create;
  try
    // Connect
    FConnection := TFDConnection.Create(nil);
    try
      FConnection.DriverName := 'SQLite';
      FConnection.Params.Database := 'D:\tmp\decrypted_dbs\message\message_0.db';
      FConnection.Params.Add('OpenMode=ReadOnly');
      FConnection.Connected := True;
    except
      on E: Exception do
      begin
        Writeln('DB error: ', E.Message);
        Exit;
      end;
    end;

    // Find first Msg_* table
    LQuery.Connection := FConnection;
    LQuery.SQL.Text :=
      'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%'' LIMIT 1';
    LQuery.Open;
    if LQuery.Eof then
    begin
      Writeln('No Msg tables found');
      Exit;
    end;
    LTableName := LQuery.FieldByName('name').AsString;
    Writeln('Using table: ', LTableName);
    LQuery.Close;

    // Read first 3 messages
    LQuery.SQL.Text :=
      'SELECT local_id, local_type, CAST(message_content AS BLOB) as msg_blob ' +
      'FROM ' + LTableName + ' ' +
      'WHERE message_content IS NOT NULL LIMIT 3';
    LQuery.Open;

    LRowCount := 0;
    while not LQuery.Eof do
    begin
      Inc(LRowCount);
      Writeln;
      Writeln('=== Row ', LRowCount,
        ' (local_id=', LQuery.FieldByName('local_id').AsInteger,
        ', type=', LQuery.FieldByName('local_type').AsInteger, ') ===');

      LStream.Clear;
      TBlobField(LQuery.FieldByName('msg_blob')).SaveToStream(LStream);
      SetLength(LMsgBlob, LStream.Size);
      if LStream.Size > 0 then
      begin
        LStream.Position := 0;
        LStream.ReadBuffer(LMsgBlob[0], LStream.Size);
      end;

      Writeln('  Compressed size: ', Length(LMsgBlob));
      Writeln('  First 8 bytes: ',
        Format('%.2x %.2x %.2x %.2x %.2x %.2x %.2x %.2x',
          [LMsgBlob[0], LMsgBlob[1], LMsgBlob[2], LMsgBlob[3],
           LMsgBlob[4], LMsgBlob[5], LMsgBlob[6], LMsgBlob[7]]));

      if not TZstdDecompressor.IsZstdData(LMsgBlob) then
      begin
        Writeln('  Not zstd data');
        LQuery.Next;
        Continue;
      end;

      // Decompress to raw bytes
      LDecompressed := LZstd.Decompress(LMsgBlob);
      Writeln('  Decompressed size: ', Length(LDecompressed));
      if Length(LDecompressed) >= 8 then
        Writeln('  First 8 bytes decompressed: ',
          Format('%.2x %.2x %.2x %.2x %.2x %.2x %.2x %.2x',
            [LDecompressed[0], LDecompressed[1], LDecompressed[2], LDecompressed[3],
             LDecompressed[4], LDecompressed[5], LDecompressed[6], LDecompressed[7]]));

      // Save raw bytes
      LBytesFile := Format('D:\tmp\diag_msg_%d.bin', [LRowCount]);
      TFile.WriteAllBytes(LBytesFile, LDecompressed);
      Writeln('  Raw bytes saved to: ', LBytesFile);

      // Check UTF-8 validity
      LIsValidUtf8 := TZstdDecompressor.IsValidUtf8(LDecompressed);
      Writeln('  IsValidUtf8: ', LIsValidUtf8);

      // Decode as UTF-8
      LUtf8Str := TEncoding.UTF8.GetString(LDecompressed);
      // Show first few chars as code points
      LFirst20 := '';
      for I := 1 to Min(20, Length(LUtf8Str)) do
        LFirst20 := LFirst20 + Format('U+%4.4x ', [Ord(LUtf8Str[I])]);
      Writeln('  UTF-8 first 20 code points: ', LFirst20);

      // Decode as GBK
      LGbkEnc := TEncoding.GetEncoding(936);
      try
        LGbkStr := LGbkEnc.GetString(LDecompressed);
        LFirst20 := '';
        for I := 1 to Min(20, Length(LGbkStr)) do
          LFirst20 := LFirst20 + Format('U+%4.4x ', [Ord(LGbkStr[I])]);
        Writeln('  GBK   first 20 code points: ', LFirst20);
      finally
        LGbkEnc.Free;
      end;

      // Save UTF-8 text
      LUtf8File := Format('D:\tmp\diag_msg_%d.utf8.txt', [LRowCount]);
      TFile.WriteAllBytes(LUtf8File, TEncoding.UTF8.GetBytes(LUtf8Str));
      Writeln('  UTF-8 text saved to: ', LUtf8File);

      // Save GBK text (as UTF-8 for inspection)
      LGbkFile := Format('D:\tmp\diag_msg_%d.gbk_as_utf8.txt', [LRowCount]);
      TFile.WriteAllBytes(LGbkFile, TEncoding.UTF8.GetBytes(LGbkStr));
      Writeln('  GBK->UTF8 text saved to: ', LGbkFile);

      LQuery.Next;
    end;

    FConnection.Free;
  finally
    LStream.Free;
    LQuery.Free;
    LZstd.Free;
  end;
end;

begin
  try
    Diagnose;
  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;
  Writeln;
  Writeln('Done. Check D:\tmp\diag_msg_* files.');
end.
