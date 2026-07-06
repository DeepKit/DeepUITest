program TestZstdDecompress;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.Param,
  FireDAC.Comp.UI,
  FireDAC.VCLUI.Wait,
  DeepAxis.Core.Base in '..\src\core\DeepAxis.Core.Base.pas',
  DeepAxis.Core.DataTypes in '..\src\core\DeepAxis.Core.DataTypes.pas',
  DeepAxis.Core.Contracts in '..\src\core\DeepAxis.Core.Contracts.pas',
  DeepAxis.WeChat.Adapter in '..\src\wechat\DeepAxis.WeChat.Adapter.pas',
  DeepAxis.WeChat.Adapter411053 in '..\src\wechat\DeepAxis.WeChat.Adapter411053.pas',
  DeepAxis.WeChat.Zstd in '..\src\wechat\DeepAxis.WeChat.Zstd.pas',
  DeepAxis.WeChat.Reader in '..\src\wechat\DeepAxis.WeChat.Reader.pas';

var
  FConnection: TFDConnection;

procedure InitializeDatabase;
var
  LDbPath: string;
begin
  // Try multiple possible locations
  LDbPath := 'D:\tmp\decrypted_dbs\message\message_0.db';
  if not TFile.Exists(LDbPath) then
    LDbPath := TPath.Combine(TPath.GetDocumentsPath, 'DeepAxis\decrypted\message_0.db');

  if not TFile.Exists(LDbPath) then
  begin
    Writeln('Database not found at: ', LDbPath);
    Writeln('Please ensure the decrypted database exists.');
    Exit;
  end;

  FConnection := TFDConnection.Create(nil);
  try
    FConnection.DriverName := 'SQLite';
    FConnection.Params.Database := LDbPath;
    FConnection.Params.Add('OpenMode=ReadOnly');
    FConnection.Connected := True;

    Writeln('✓ Database connected: ', LDbPath);
  except
    on E: Exception do
    begin
      Writeln('✗ Failed to connect to database: ', E.Message);
      FreeAndNil(FConnection);
    end;
  end;
end;

procedure TestZstdDecompression;
var
  LQuery: TFDQuery;
  LZstd: TZstdDecompressor;
  LCompressedData: TBytes;
  LDecompressedText: string;
  LRowCount: Integer;
  LSuccessCount: Integer;
  LFailCount: Integer;
  LStream: TMemoryStream;
begin
  if not Assigned(FConnection) then
  begin
    Writeln('✗ Database not initialized');
    Exit;
  end;

  Writeln;
  Writeln('=== Testing Zstd Decompression ===');
  Writeln;

  LZstd := TZstdDecompressor.Create;
  LQuery := TFDQuery.Create(nil);
  LStream := TMemoryStream.Create;
  try
    LQuery.Connection := FConnection;
    LQuery.SQL.Text :=
      'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%'' LIMIT 1';

    try
      LQuery.Open;
      if LQuery.Eof then
      begin
        Writeln('✗ No message tables found');
        Exit;
      end;

      var LTableName := LQuery.FieldByName('name').AsString;
      Writeln('Using table: ', LTableName);
      LQuery.Close;

      // Now query messages from this table
      LQuery.SQL.Text :=
        'SELECT local_id, local_type, create_time, ' +
        'CAST(message_content AS BLOB) as msg_blob, ' +
        'CAST(source AS BLOB) as src_blob, ' +
        'WCDB_CT_message_content ' +
        'FROM "' + LTableName + '" ' +
        'WHERE message_content IS NOT NULL ' +
        'LIMIT 10';

      LQuery.Open;
      LRowCount := 0;
      LSuccessCount := 0;
      LFailCount := 0;

      while not LQuery.Eof do
      begin
        Inc(LRowCount);
        Writeln('Row ', LRowCount, ':');
        Writeln('  local_id: ', LQuery.FieldByName('local_id').AsInteger);

        // Read compressed data as BLOB
        LStream.Clear;
        TBlobField(LQuery.FieldByName('msg_blob')).SaveToStream(LStream);
        SetLength(LCompressedData, LStream.Size);
        if LStream.Size > 0 then
        begin
          LStream.Position := 0;
          LStream.ReadBuffer(LCompressedData[0], LStream.Size);
        end;

        Writeln('  Compressed size: ', Length(LCompressedData), ' bytes');

        // Check if it's zstd data
        if TZstdDecompressor.IsZstdData(LCompressedData) then
        begin
          Writeln('  ✓ Detected zstd magic bytes');

          try
            LDecompressedText := LZstd.DecompressToString(LCompressedData);
            Writeln('  ✓ Decompression successful');
            Writeln('  Decompressed size: ', Length(LDecompressedText), ' chars');

            if Length(LDecompressedText) > 200 then
              Writeln('  Preview: ', Copy(LDecompressedText, 1, 200), '...')
            else
              Writeln('  Content: ', LDecompressedText);

            Inc(LSuccessCount);
          except
            on E: Exception do
            begin
              Writeln('  ✗ Decompression failed: ', E.Message);
              Inc(LFailCount);
            end;
          end;
        end
        else
        begin
          Writeln('  ⚠ Not zstd data (plain text or other format)');
          // Try to read as plain text
          try
            LDecompressedText := TEncoding.UTF8.GetString(LCompressedData);
            Writeln('  Plain text: ', LDecompressedText);
            Inc(LSuccessCount);
          except
            on E: Exception do
            begin
              Writeln('  ✗ Failed to read as text: ', E.Message);
              Inc(LFailCount);
            end;
          end;
        end;

        Writeln;
        LQuery.Next;
      end;

      Writeln('=== Summary ===');
      Writeln('Total rows: ', LRowCount);
      Writeln('Successful: ', LSuccessCount);
      Writeln('Failed: ', LFailCount);
      Writeln('Zstd support: ', LZstd.IsLoaded);

    except
      on E: Exception do
        Writeln('✗ Query failed: ', E.Message);
    end;
  finally
    LStream.Free;
    LQuery.Free;
    LZstd.Free;
  end;
end;

procedure TestReaderIntegration;
var
  LAdapter: TWeChat411053Adapter;
  LReader: TWeChatReader;
  LMessages: TArray<TMessageMeta>;
  LMsg: TMessageMeta;
  LContactId: string;
  LCursor: TScanCursor;
  I: Integer;
  LContacts: TArray<TContact>;
begin
  Writeln;
  Writeln('=== Testing Reader Integration ===');
  Writeln;

  LAdapter := TWeChat411053Adapter.Create;
  try
    LReader := TWeChatReader.Create(LAdapter);
    try
      // Initialize reader with database path
      if not LReader.Open('D:\tmp\decrypted_dbs', []) then
      begin
        Writeln('✗ Failed to open database');
        Exit;
      end;

      // Test reading contacts first
      Writeln('Reading contacts...');
      LContacts := LReader.ReadContacts;
      Writeln('✓ Found ', Length(LContacts), ' contacts');

      if Length(LContacts) > 0 then
      begin
        // Pick first contact to test message reading
        LContactId := LContacts[0].ContactId;
        Writeln('Testing message read for contact: ', LContactId);

        LCursor := Default(TScanCursor);
        LCursor.ContactId := LContactId;
        LCursor.LastLocalId := 0;
        LCursor.LastCreateTime := 0;

        LMessages := LReader.ReadMessages(LContactId, LCursor);
        Writeln('✓ Found ', Length(LMessages), ' messages');

        // Display first few messages with decompressed body
        for I := 0 to Min(4, Length(LMessages) - 1) do
        begin
          LMsg := LMessages[I];
          Writeln;
          Writeln('Message ', I + 1, ':');
          Writeln('  SourceRowRef: ', LMsg.SourceRowRef);
          Writeln('  RawType: ', LMsg.RawType);
          Writeln('  NormalizedType: ', Ord(LMsg.NormalizedType));
          Writeln('  SentAt: ', DateTimeToStr(LMsg.SentAt));
          Writeln('  BodyQueried: ', LMsg.BodyQueried);
          Writeln('  BodyLength: ', Length(LMsg.Body));

          if Length(LMsg.Body) > 0 then
          begin
            if Length(LMsg.Body) > 150 then
              Writeln('  BodyPreview: ', Copy(LMsg.Body, 1, 150), '...')
            else
              Writeln('  Body: ', LMsg.Body);
          end;

          if Length(LMsg.SourceXml) > 0 then
          begin
            if Length(LMsg.SourceXml) > 100 then
              Writeln('  SourceXml: ', Copy(LMsg.SourceXml, 1, 100), '...')
            else
              Writeln('  SourceXml: ', LMsg.SourceXml);
          end;
        end;
      end;

    finally
      LReader.Free;
    end;
  finally
    LAdapter.Free;
  end;
end;

begin
  try
    Writeln('╔═══════════════════════════════════════════════════════╗');
    Writeln('║  DeepAxis WCDB Message Decompression Test            ║');
    Writeln('║  Testing zstd decompression and body reading         ║');
    Writeln('╚═══════════════════════════════════════════════════════╝');
    Writeln;

    // Initialize database connection
    InitializeDatabase;

    if Assigned(FConnection) then
    try
      // Test 1: Direct zstd decompression
      TestZstdDecompression;

      // Test 2: Reader integration - skipped for now
      // TestReaderIntegration;

      Writeln;
      Writeln('✓ Direct decompression test completed');
    finally
      FreeAndNil(FConnection);
    end
    else
      Writeln('✗ Cannot proceed without database connection');

  except
    on E: Exception do
    begin
      Writeln;
      Writeln('✗ Fatal error: ', E.Message);
      Writeln(E.StackTrace);
    end;
  end;

  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
