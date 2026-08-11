program TestWeChatReader;

{$APPTYPE CONSOLE}
{.$R *.res}

uses
  System.SysUtils,
  System.IOUtils,
  DeepAxis.Core.Base,
  DeepAxis.Core.DataTypes,
  DeepAxis.Core.Contracts,
  DeepAxis.WeChat.Adapter,
  DeepAxis.WeChat.Adapter411053,
  DeepAxis.WeChat.Reader;

var
  LReader: TWeChatReader;
  LAdapter: TWeChat411053Adapter;
  LContacts: TArray<TContact>;
  LContact: TContact;
  LBasePath: string;
begin
  try
    LBasePath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\dbs');
    WriteLn('Base path: ', LBasePath);
    WriteLn('Directory exists: ', TDirectory.Exists(LBasePath));

    if not TDirectory.Exists(LBasePath) then
    begin
      WriteLn('ERROR: Directory not found!');
      Exit;
    end;

    // Build correct paths
    var LContactPath := TPath.Combine(LBasePath, 'contact\contact.db');
    var LMessagePath := TPath.Combine(LBasePath, 'message\message_0.db');
    var LSessionPath := TPath.Combine(LBasePath, 'session\session.db');

    WriteLn('Contact DB: ', LContactPath, ' (exists: ', TFile.Exists(LContactPath), ')');
    WriteLn('Message DB: ', LMessagePath, ' (exists: ', TFile.Exists(LMessagePath), ')');
    WriteLn('Session DB: ', LSessionPath, ' (exists: ', TFile.Exists(LSessionPath), ')');

    // Create adapter and reader
    LAdapter := TWeChat411053Adapter.Create;
    LReader := TWeChatReader.Create(LAdapter);

    try
      // Try to open with explicit paths
      if LReader.OpenPaths(LContactPath, LMessagePath, LSessionPath) then
      begin
        WriteLn('SUCCESS: Database opened!');

        // Try to read contacts
        LContacts := LReader.ReadContacts;
        WriteLn('Contacts found: ', Length(LContacts));

        // Show first 5 contacts
        var LCount := Length(LContacts);
        if LCount > 5 then LCount := 5;

        for var I := 0 to LCount - 1 do
        begin
          LContact := LContacts[I];
          WriteLn(Format('  [%d] %s (ID: %s)', [I+1, LContact.DisplayNameRedacted, LContact.ContactId]));
        end;
      end
      else
        WriteLn('ERROR: Failed to open database');
    finally
      LReader.Free;
    end;

  except
    on E: Exception do
      WriteLn('EXCEPTION: ', E.Message);
  end;

  WriteLn;
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
