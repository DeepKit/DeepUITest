program TestMsgParser;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.StrUtils,
  Winapi.Windows,
  Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef, FireDAC.Stan.Param,
  DeepAxis.Core.Base,
  DeepAxis.Core.DataTypes,
  DeepAxis.Core.Contracts,
  DeepAxis.WeChat.Adapter,
  DeepAxis.WeChat.Adapter411053,
  DeepAxis.WeChat.Zstd,
  DeepAxis.WeChat.MsgParser,
  DeepAxis.WeChat.Reader;

const
  DATA_PATH = 'D:\tmp\decrypted_dbs';
  REPORT_FILE = 'D:\tmp\msgparser_report.txt';

var
  GLog: TStringList;

procedure Log(const AMsg: string);
begin
  GLog.Add(AMsg);
  // Don't write to console — too slow for CJK characters on Windows console
end;

procedure PrintSep;
begin
  Log('────────────────────────────────────────────────────────');
end;

procedure TestReaderAndParser;
var
  LAdapter: ISchemaAdapter;
  LReader: IWxReader;
  LContacts: TArray<TContact>;
  LMessages: TArray<TMessageMeta>;
  LCursor: TScanCursor;
  LContact: TContact;
  LMsg: TMessageMeta;
  LParsed: TParsedMessage;
  LIsSender: Boolean;
  I, J, LMsgLimit: Integer;
  LContactsTested, LMsgsParsed, LMsgsOk: Integer;
begin
  Log('╔═══════════════════════════════════════════════════════════╗');
  Log('║  DeepAxis Reader + MsgParser 集成验证                   ║');
  Log('╚═══════════════════════════════════════════════════════════╝');
  Log('');

  // Create adapter (interface ref keeps it alive)
  LAdapter := TWeChat411053Adapter.Create as ISchemaAdapter;
  LReader := TWeChatReader.Create(LAdapter) as IWxReader;

  // Open — uses nested directory layout: contact/contact.db, message/message_*.db
  Log('Opening DBs from: ' + DATA_PATH);
  if not LReader.Open(DATA_PATH, []) then
  begin
    Log('✗ Failed to open databases at ' + DATA_PATH);
    Exit;
  end;
  Log('✓ Database opened');
  Log('');

  // Read contacts
  LContacts := LReader.ReadContacts;
  Log('✓ Read ' + IntToStr(Length(LContacts)) + ' contacts');
  Log('');

  if Length(LContacts) = 0 then
  begin
    Log('✗ No contacts found');
    Exit;
  end;

  // Test message reading + parsing: find first 3 contacts with messages
  LContactsTested := 0;
  LMsgsParsed := 0;
  LMsgsOk := 0;
  LMsgLimit := 5; // max messages per contact to display

  for I := 0 to Length(LContacts) - 1 do
  begin
    if LContactsTested >= 3 then Break;
    // Progress every 100 contacts
    if I mod 100 = 0 then
    begin
      Writeln('  scanning contact ', I, '/', Length(LContacts), '...');
      // Flush report incrementally
      TFile.WriteAllText(REPORT_FILE, GLog.Text, TEncoding.UTF8);
    end;

    LContact := LContacts[I];

    LCursor := Default(TScanCursor);
    LCursor.LastLocalId := 0;
    LCursor.LastCreateTime := 0;

    LMessages := LReader.ReadMessages(LContact.ContactId, LCursor);

    if Length(LMessages) = 0 then Continue;

    // Found a contact with messages — display it
    Inc(LContactsTested);
    Log('── Contact ' + IntToStr(LContactsTested) +
      ' (index ' + IntToStr(I) + '/' + IntToStr(Length(LContacts)) + ') ──');
    Log('  ContactId:        ' + Copy(LContact.ContactId, 1, 24) + '...');
    Log('  DisplayNameRedacted: ' + LContact.DisplayNameRedacted);
    PrintSep;
    Log('  Messages found: ' + IntToStr(Length(LMessages)));

    for J := 0 to Min(LMsgLimit - 1, Length(LMessages) - 1) do
    begin
      LMsg := LMessages[J];
      Inc(LMsgsParsed);

      // Parse message body
      LParsed := TMessageParser.Parse(LMsg);
      if LParsed.ParseError = '' then
        Inc(LMsgsOk);

      Log('  Msg ' + IntToStr(J + 1) +
        ' [type=' + IntToStr(LMsg.RawType) + '/' + IntToStr(Ord(LMsg.NormalizedType)) +
        ', dir=' + IntToStr(Ord(LMsg.Direction)) + ']' +
        ' local_id=' + LMsg.SourceRowRef);

      // Show parsed content
      case LParsed.ContentType of
        pctText:
          Log('    Text: ' +
            Copy(LParsed.TextBody, 1, 120) +
            IfThen(Length(LParsed.TextBody) > 120, '...'));

        pctImage:
        begin
          Log('    Image: hdlength=' + IntToStr(LParsed.Image.HdLength) +
            ', aeskey=' + Copy(LParsed.Image.AesKey, 1, 16) +
            ', md5=' + Copy(LParsed.Image.Md5, 1, 12));
        end;

        pctVideo:
          Log('    Video: playlength=' + IntToStr(LParsed.Video.PlayLength) + 's' +
            ', ' + IntToStr(LParsed.Video.Width) + 'x' + IntToStr(LParsed.Video.Height) +
            ', aeskey=' + Copy(LParsed.Video.AesKey, 1, 16));

        pctVoice:
          Log('    Voice: duration=' + IntToStr(LParsed.Voice.VoiceLength) + 'ms' +
            ', bufid=' + LParsed.Voice.BufId);

        pctEmoji:
          Log('    Emoji: ' + IntToStr(LParsed.Emoji.Width) + 'x' + IntToStr(LParsed.Emoji.Height) +
            ', isgift=' + IfThen(LParsed.Emoji.IsGift, 'True', 'False') +
            ', cdnurl=' + Copy(LParsed.Emoji.CdnUrl, 1, 50));

        pctLink:
        begin
          Log('    Link: title="' + Copy(LParsed.Link.Title, 1, 60) + '"');
          Log('          app="' + LParsed.Link.AppName +
            '", type=' + IntToStr(LParsed.Link.Type_));
          if LParsed.Link.Url <> '' then
            Log('          url=' + Copy(LParsed.Link.Url, 1, 80));
        end;

        pctSystem:
          Log('    System: ' +
            Copy(LParsed.TextBody, 1, 120) +
            IfThen(Length(LParsed.TextBody) > 120, '...'));

        pctNone:
          Log('    (empty)');

        pctUnknown:
          Log('    Unknown: ' + LParsed.ParseError +
            IfThen(Length(LParsed.RawBody) > 0,
              ' | raw=' + Copy(LParsed.RawBody, 1, 60)));
      end;

      // Parse SourceXml for IsSender (optional, just log if available)
      if (LMsg.SourceXml <> '') and
         TMessageParser.ParseSourceXml(LMsg.SourceXml, LIsSender) then
        Log('    SourceXml.IsSender=' + IfThen(LIsSender, 'True', 'False'));
    end;

    Log('');
  end;

  PrintSep;
  Log('Summary:');
  Log('  Contacts tested: ' + IntToStr(LContactsTested));
  Log('  Messages parsed: ' + IntToStr(LMsgsParsed));
  Log('  Parse OK:        ' + IntToStr(LMsgsOk));
  Log('  Parse errors:    ' + IntToStr(LMsgsParsed - LMsgsOk));

  LReader.Close;
end;

begin
  GLog := TStringList.Create;
  try
    Writeln('Running... (writing to ', REPORT_FILE, ')');
    try
      TestReaderAndParser;
    except
      on E: Exception do
      begin
        Log('');
        Log('✗ FATAL: ' + E.Message);
        Log(E.StackTrace);
      end;
    end;

    // Write full UTF-8 report to file (unaffected by console encoding issues)
    TFile.WriteAllText(REPORT_FILE, GLog.Text, TEncoding.UTF8);
    Writeln('Report written to: ', REPORT_FILE);
    Writeln('Lines in report: ', GLog.Count);
  finally
    GLog.Free;
  end;
end.
