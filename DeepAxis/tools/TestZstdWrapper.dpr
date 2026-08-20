program TestZstdWrapper;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  FireDAC.Comp.UI, FireDAC.VCLUI.Wait, FireDAC.DApt, FireDAC.Stan.Async,
  DeepAxis.WeChat.Zstd in 'src/wechat/DeepAxis.WeChat.Zstd.pas';

var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LField: TField;
  LStream: TMemoryStream;
  LData: TBytes;
  LSize: Integer;
  LDecompressor: TZstdDecompressor;
  LDecompressed: string;
begin
  try
    Writeln('=== Testing Zstd Wrapper ===');
    Writeln('');

    // Create decompressor
    LDecompressor := TZstdDecompressor.Create;
    try
      // Load library
      if LDecompressor.LoadLibrary then
        Writeln('✓ zstd.dll loaded successfully')
      else
      begin
        Writeln('✗ Failed to load zstd.dll');
        Exit;
      end;

      // Connect to database
      LConn := TFDConnection.Create(nil);
      try
        LConn.DriverName := 'SQLite';
        LConn.Params.Database := 'D:\tmp\decrypted_dbs\message\message_0.db';
        LConn.Open;
        Writeln('✓ Database opened');

        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConn;

          // Test 1: Read a text message (type=1)
          Writeln('');
          Writeln('--- Test 1: Text message (type=1) ---');
          LQuery.SQL.Text := 'SELECT CAST(message_content AS BLOB) as msg_blob ' +
            'FROM "Msg_c8528f4d430010b8ab15c67ed4e4de85" WHERE local_type=1 LIMIT 1';
          LQuery.Open;

          if not LQuery.Eof then
          begin
            LField := LQuery.FieldByName('msg_blob');
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

              Writeln(Format('Compressed size: %d bytes', [LSize]));
              Writeln(Format('Is zstd: %s', [BoolToStr(TZstdDecompressor.IsZstdData(LData), True)]));

              // Decompress
              LDecompressed := LDecompressor.DecompressToString(LData);
              Writeln(Format('Decompressed size: %d chars', [Length(LDecompressed)]));
              Writeln('First 200 chars:');
              Writeln(Copy(LDecompressed, 1, 200));
            finally
              LStream.Free;
            end;
          end
          else
            Writeln('No text message found');

          LQuery.Close;

          // Test 2: Read an image message (type=3)
          Writeln('');
          Writeln('--- Test 2: Image message (type=3) ---');
          LQuery.SQL.Text := 'SELECT CAST(message_content AS BLOB) as msg_blob ' +
            'FROM "Msg_c8528f4d430010b8ab15c67ed4e4de85" WHERE local_type=3 LIMIT 1';
          LQuery.Open;

          if not LQuery.Eof then
          begin
            LField := LQuery.FieldByName('msg_blob');
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

              Writeln(Format('Compressed size: %d bytes', [LSize]));
              LDecompressed := LDecompressor.DecompressToString(LData);
              Writeln(Format('Decompressed size: %d chars', [Length(LDecompressed)]));
              Writeln('First 150 chars:');
              Writeln(Copy(LDecompressed, 1, 150));
            finally
              LStream.Free;
            end;
          end
          else
            Writeln('No image message found');

        finally
          LQuery.Free;
        end;

        LConn.Close;
      finally
        LConn.Free;
      end;

    finally
      LDecompressor.Free;
    end;

    Writeln('');
    Writeln('=== All tests passed ===');
  except
    on E: Exception do
    begin
      Writeln('');
      Writeln('✗ Error: ' + E.Message);
      Writeln(E.StackTrace);
    end;
  end;
end.
