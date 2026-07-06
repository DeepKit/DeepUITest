unit DeepAxis.WeChat.MsgParser;

interface

uses
  System.SysUtils, System.RegularExpressions, System.Math, System.Classes,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   Parsed image message content (local_type=3).
  ///   Body XML: &lt;msg&gt;&lt;img aeskey="..." hdlength="..." .../&gt;&lt;/msg&gt;
  /// </summary>
  TImageContent = record
    AesKey: string;
    HdLength: Integer;   // HD image size in bytes (0 = no HD)
    Length_: Integer;    // normal image size in bytes
    Md5: string;
    CdnThumbAesKey: string;
    CdnThumbLength: Integer;
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed link / app message content (local_type=49).
  ///   Body XML: &lt;msg&gt;&lt;appmsg&gt;&lt;title&gt;...&lt;/title&gt;...&lt;/appmsg&gt;&lt;/msg&gt;
  /// </summary>
  TLinkContent = record
    Title: string;
    Des: string;           // description
    Url: string;
    AppName: string;       // source app name (e.g. "文件传输助手", "小红书")
    AppExt: string;        // app extension info
    Type_: Integer;        // appmsg type: 1=link, 2=audio, 3=video, 4=url, 5=..., 33=mini-program, 36=mini-game
    Md5: string;
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed video message content (local_type=43).
  ///   Body XML: &lt;msg&gt;&lt;videomsg aeskey="..." cdnthumbaeskey="..." .../&gt;&lt;/msg&gt;
  /// </summary>
  TVideoContent = record
    AesKey: string;
    Length_: Integer;
    PlayLength: Integer;   // duration in seconds
    Width: Integer;
    Height: Integer;
    Md5: string;
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed emoji / sticker message content (local_type=47).
  ///   Body XML: &lt;msg&gt;&lt;emoji .../&gt;&lt;/msg&gt;
  /// </summary>
  TEmojiContent = record
    AesKey: string;
    CdnUrl: string;
    Length_: Integer;
    Width: Integer;
    Height: Integer;
    Md5: string;
    IsGift: Boolean;       // 表情为礼物
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed voice message content (local_type=34).
  ///   Body XML: &lt;msg&gt;&lt;voicemsg voicelength="..." .../&gt;&lt;/msg&gt;
  /// </summary>
  TVoiceContent = record
    VoiceLength: Integer;  // duration in milliseconds
    BufId: string;
    EndFlag: Integer;
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed location message content (local_type=48).
  ///   Body XML: &lt;msg&gt;&lt;location x="..." y="..." scale="..." label="..."/&gt;&lt;/msg&gt;
  /// </summary>
  TLocationContent = record
    X: Double;             // latitude
    Y: Double;             // longitude
    Scale: Integer;        // map scale
    LocationLabel: string; // location name/address
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed contact card / friend recommendation (local_type=40).
  ///   Body XML: &lt;msg&gt;&lt;username&gt;...&lt;/username&gt;&lt;nickname&gt;...&lt;/nickname&gt;...&lt;/msg&gt;
  /// </summary>
  TContactCardContent = record
    Username: string;      // WeChat ID
    Nickname: string;      // display name
    FullPy: string;        // pinyin
    ShortPy: string;       // short pinyin
    Alias: string;         // alias
    RawXml: string;
  end;

  /// <summary>
  ///   Parsed recall message (local_type=10002).
  ///   Body: plain text like "xxx撤回了一条消息"
  /// </summary>
  TRecallContent = record
    RecallText: string;    // the recall notification text
    RawBody: string;
  end;

  /// <summary>
  ///   Union of all parsed message content types.
  ///   Use ContentType to determine which field is valid.
  /// </summary>
  TParsedContentType = (
    pctNone, pctText, pctImage, pctVoice, pctVideo,
    pctEmoji, pctLink, pctSystem, pctLocation, pctContactCard, pctRecall,
    pctUnknown
  );

  TParsedMessage = record
    ContentType: TParsedContentType;
    TextBody: string;        // plain text for pctText, system text for pctSystem
    Image: TImageContent;
    Video: TVideoContent;
    Voice: TVoiceContent;
    Emoji: TEmojiContent;
    Link: TLinkContent;
    Location: TLocationContent;
    ContactCard: TContactCardContent;
    Recall: TRecallContent;
    RawBody: string;         // original Body field value
    ParseError: string;      // non-empty if parsing failed
    class function CreateEmpty: TParsedMessage; static;
  end;

  /// <summary>
  ///   Parses TMessageMeta.Body into structured TParsedMessage.
  ///   Handles WeChat's XML-based content formats for non-text message types.
  ///   Uses regex-based attribute extraction — no full DOM parser needed.
  /// </summary>
  TMessageParser = class
  public
    /// <summary>Parse a single message's Body into structured content.</summary>
    class function Parse(const AMsg: TMessageMeta): TParsedMessage; static;

    /// <summary>Parse msgsource XML for sender info (IsSender, at list, etc.).</summary>
    class function ParseSourceXml(const ASourceXml: string;
      out AIsSender: Boolean): Boolean; static;

    /// <summary>Quick check: does the Body look like XML? (starts with &lt;msg)</summary>
    class function IsXmlBody(const ABody: string): Boolean; static;
  private
    class function ExtractXmlAttr(const AXml, AAttrName: string): string; static;
    class function ExtractXmlTag(const AXml, ATagName: string): string; static;
    class function ExtractInt(const AXml, AAttrName: string; ADefault: Integer): Integer; static;
    class function ExtractBool(const AXml, AAttrName: string): Boolean; static;
    class function ExtractDouble(const AXml, AAttrName: string; ADefault: Double): Double; static;
    class function ParseImageXml(const AXml: string): TImageContent; static;
    class function ParseVideoXml(const AXml: string): TVideoContent; static;
    class function ParseVoiceXml(const AXml: string): TVoiceContent; static;
    class function ParseEmojiXml(const AXml: string): TEmojiContent; static;
    class function ParseLinkXml(const AXml: string): TLinkContent; static;
    class function ParseLocationXml(const AXml: string): TLocationContent; static;
    class function ParseContactCardXml(const AXml: string): TContactCardContent; static;
  end;

implementation

{ TParsedMessage }

class function TParsedMessage.CreateEmpty: TParsedMessage;
begin
  Result := Default(TParsedMessage);
  Result.ContentType := pctNone;
  Result.TextBody := '';
  Result.RawBody := '';
  Result.ParseError := '';
end;

{ TMessageParser }

class function TMessageParser.IsXmlBody(const ABody: string): Boolean;
begin
  // WeChat XML bodies may start with <?xml version="1.0"?> before <msg>.
  // Just check whether <msg appears anywhere in the first ~60 chars.
  Result := ABody.Contains('<msg');
end;

class function TMessageParser.ExtractXmlAttr(const AXml, AAttrName: string): string;
var
  LMatch: TMatch;
begin
  Result := '';
  // Match: attrName="value"  or  attrName='value'
  LMatch := TRegEx.Match(AXml,
    '\b' + TRegEx.Escape(AAttrName) + '\s*=\s*"([^"]*)"',
    [roIgnoreCase]);
  if LMatch.Success then
    Result := LMatch.Groups[1].Value
  else
  begin
    LMatch := TRegEx.Match(AXml,
      '\b' + TRegEx.Escape(AAttrName) + '\s*=\s*''([^'']*)''',
      [roIgnoreCase]);
    if LMatch.Success then
      Result := LMatch.Groups[1].Value;
  end;
end;

class function TMessageParser.ExtractXmlTag(const AXml, ATagName: string): string;
var
  LMatch: TMatch;
  LContent: string;
begin
  Result := '';
  // Match: <tagName ...>content</tagName>  or  <tagName .../>  (self-closing)
  LMatch := TRegEx.Match(AXml,
    '<' + TRegEx.Escape(ATagName) + '[^>]*>(.+?)</' + TRegEx.Escape(ATagName) + '>',
    [roIgnoreCase, roSingleLine]);
  if LMatch.Success then
  begin
    LContent := Trim(LMatch.Groups[1].Value);
    // Unwrap <![CDATA[...]]> if present
    if (Copy(LContent, 1, 9) = '<![CDATA[') and
       (Copy(LContent, Length(LContent) - 2, 3) = ']]>') then
      LContent := Copy(LContent, 10, Length(LContent) - 12);
    Result := LContent;
  end
  else
  begin
    // Check for self-closing tag — just return '' (attribute extraction from full XML)
    LMatch := TRegEx.Match(AXml,
      '<' + TRegEx.Escape(ATagName) + '\b[^>]*/>',
      [roIgnoreCase]);
    if LMatch.Success then
      Result := ''; // self-closing, no text content
  end;
end;

class function TMessageParser.ExtractInt(const AXml, AAttrName: string;
  ADefault: Integer): Integer;
var
  LS: string;
begin
  LS := ExtractXmlAttr(AXml, AAttrName);
  if LS <> '' then
  begin
    try
      Result := StrToInt(LS);
    except
      Result := ADefault;
    end;
  end
  else
    Result := ADefault;
end;

class function TMessageParser.ExtractBool(const AXml, AAttrName: string): Boolean;
var
  LS: string;
begin
  LS := ExtractXmlAttr(AXml, AAttrName);
  Result := (LS = '1') or (SameText(LS, 'true'));
end;

class function TMessageParser.ParseImageXml(const AXml: string): TImageContent;
begin
  Result := Default(TImageContent);
  Result.AesKey := ExtractXmlAttr(AXml, 'aeskey');
  Result.HdLength := ExtractInt(AXml, 'hdlength', 0);
  Result.Length_ := ExtractInt(AXml, 'length', 0);
  Result.Md5 := ExtractXmlAttr(AXml, 'md5');
  Result.CdnThumbAesKey := ExtractXmlAttr(AXml, 'cdnthumbaeskey');
  Result.CdnThumbLength := ExtractInt(AXml, 'cdnthumblength', 0);
  Result.RawXml := AXml;
end;

class function TMessageParser.ParseVideoXml(const AXml: string): TVideoContent;
begin
  Result := Default(TVideoContent);
  Result.AesKey := ExtractXmlAttr(AXml, 'aeskey');
  Result.Length_ := ExtractInt(AXml, 'length', 0);
  Result.PlayLength := ExtractInt(AXml, 'playlength', 0);
  Result.Width := ExtractInt(AXml, 'width', 0);
  Result.Height := ExtractInt(AXml, 'height', 0);
  Result.Md5 := ExtractXmlAttr(AXml, 'md5');
  Result.RawXml := AXml;
end;

class function TMessageParser.ParseVoiceXml(const AXml: string): TVoiceContent;
begin
  Result := Default(TVoiceContent);
  Result.VoiceLength := ExtractInt(AXml, 'voicelength', 0);
  Result.BufId := ExtractXmlAttr(AXml, 'bufid');
  Result.EndFlag := ExtractInt(AXml, 'endflag', 0);
  Result.RawXml := AXml;
end;

class function TMessageParser.ParseEmojiXml(const AXml: string): TEmojiContent;
begin
  Result := Default(TEmojiContent);
  Result.AesKey := ExtractXmlAttr(AXml, 'aeskey');
  Result.CdnUrl := ExtractXmlAttr(AXml, 'cdnurl');
  Result.Length_ := ExtractInt(AXml, 'length', 0);
  Result.Width := ExtractInt(AXml, 'width', 0);
  Result.Height := ExtractInt(AXml, 'height', 0);
  Result.Md5 := ExtractXmlAttr(AXml, 'md5');
  Result.IsGift := ExtractBool(AXml, 'isgift');
  Result.RawXml := AXml;
end;

class function TMessageParser.ParseLinkXml(const AXml: string): TLinkContent;
var
  LAppMsg: string;
begin
  Result := Default(TLinkContent);

  // Extract the <appmsg> block
  LAppMsg := ExtractXmlTag(AXml, 'appmsg');
  if LAppMsg = '' then
  begin
    // Some links don't have appmsg, try direct extraction from AXml
    LAppMsg := AXml;
  end;

  Result.Title := ExtractXmlTag(LAppMsg, 'title');
  Result.Des := ExtractXmlTag(LAppMsg, 'des');
  Result.Url := ExtractXmlTag(LAppMsg, 'url');
  Result.AppName := ExtractXmlTag(LAppMsg, 'appname');
  Result.AppExt := ExtractXmlTag(LAppMsg, 'appext');
  Result.Type_ := ExtractInt(LAppMsg, 'type', 0);
  Result.Md5 := ExtractXmlAttr(LAppMsg, 'md5');
  Result.RawXml := AXml;
end;

class function TMessageParser.ExtractDouble(const AXml, AAttrName: string; ADefault: Double): Double;
var
  LStr: string;
begin
  LStr := ExtractXmlAttr(AXml, AAttrName);
  if LStr <> '' then
  begin
    try
      Result := StrToFloat(LStr);
      Exit;
    except
      // Fall through to default
    end;
  end;
  Result := ADefault;
end;

class function TMessageParser.ParseLocationXml(const AXml: string): TLocationContent;
begin
  Result := Default(TLocationContent);

  // Location XML: <msg><location x="..." y="..." scale="..." label="..."/></msg>
  Result.X := ExtractDouble(AXml, 'x', 0.0);
  Result.Y := ExtractDouble(AXml, 'y', 0.0);
  Result.Scale := ExtractInt(AXml, 'scale', 0);
  Result.LocationLabel := ExtractXmlAttr(AXml, 'label');
  Result.RawXml := AXml;
end;

class function TMessageParser.ParseContactCardXml(const AXml: string): TContactCardContent;
begin
  Result := Default(TContactCardContent);

  // Contact card XML: <msg><username>...</username><nickname>...</nickname>...</msg>
  Result.Username := ExtractXmlTag(AXml, 'username');
  Result.Nickname := ExtractXmlTag(AXml, 'nickname');
  Result.FullPy := ExtractXmlTag(AXml, 'fullpy');
  Result.ShortPy := ExtractXmlTag(AXml, 'shortpy');
  Result.Alias := ExtractXmlTag(AXml, 'alias');
  Result.RawXml := AXml;
end;

class function TMessageParser.Parse(const AMsg: TMessageMeta): TParsedMessage;
var
  LBody: string;
begin
  Result := TParsedMessage.CreateEmpty;
  Result.RawBody := AMsg.Body;

  LBody := Trim(AMsg.Body);
  if LBody = '' then
  begin
    Result.ContentType := pctNone;
    Result.ParseError := 'Body is empty';
    Exit;
  end;

  case AMsg.NormalizedType of
    nmtText:
    begin
      // Type 1: plain text — but some "text" might be XML (system forwarded)
      if IsXmlBody(LBody) then
      begin
        // Fallback: treat as unknown XML
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Text type but body is XML';
      end
      else
      begin
        Result.ContentType := pctText;
        Result.TextBody := AMsg.Body;
      end;
    end;

    nmtImage:
    begin
      // Type 3: <msg><img .../></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctImage;
        Result.Image := ParseImageXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Image type but body is not XML';
      end;
    end;

    nmtVoice:
    begin
      // Type 34: <msg><voicemsg .../></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctVoice;
        Result.Voice := ParseVoiceXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Voice type but body is not XML';
      end;
    end;

    nmtVideo:
    begin
      // Type 43: <msg><videomsg .../></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctVideo;
        Result.Video := ParseVideoXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Video type but body is not XML';
      end;
    end;

    nmtEmoji:
    begin
      // Type 47: <msg><emoji .../></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctEmoji;
        Result.Emoji := ParseEmojiXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Emoji type but body is not XML';
      end;
    end;

    nmtLink:
    begin
      // Type 49: <msg><appmsg>...</appmsg></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctLink;
        Result.Link := ParseLinkXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Link type but body is not XML';
      end;
    end;

    nmtSystem:
    begin
      // Type 10000: system text (e.g. "你已添加了xxx为好友")
      Result.ContentType := pctSystem;
      Result.TextBody := AMsg.Body;
    end;

    nmtLocation:
    begin
      // Type 48: <msg><location x="..." y="..." scale="..." label="..."/></msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctLocation;
        Result.Location := ParseLocationXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'Location type but body is not XML';
      end;
    end;

    nmtContactCard:
    begin
      // Type 40: <msg><username>...</username><nickname>...</nickname>...</msg>
      if IsXmlBody(LBody) then
      begin
        Result.ContentType := pctContactCard;
        Result.ContactCard := ParseContactCardXml(LBody);
      end
      else
      begin
        Result.ContentType := pctUnknown;
        Result.ParseError := 'ContactCard type but body is not XML';
      end;
    end;

    nmtRecall:
    begin
      // Type 10002: plain text like "xxx撤回了一条消息"
      Result.ContentType := pctRecall;
      Result.Recall.RecallText := AMsg.Body;
      Result.Recall.RawBody := AMsg.Body;
    end;

    nmtUnknown:
    begin
      Result.ContentType := pctUnknown;
      Result.ParseError := 'NormalizedType is nmtUnknown';
    end;
  end;
end;

class function TMessageParser.ParseSourceXml(const ASourceXml: string;
  out AIsSender: Boolean): Boolean;
var
  LMatch: TMatch;
  LIsSenderStr: string;
begin
  Result := False;
  AIsSender := False;

  if Trim(ASourceXml) = '' then Exit;

  // <msgsource><strid>...<signature>...</msgsource>
  // IsSender is sometimes in <msgsource> as <issender>1</issender>
  // Or as a direct attribute

  // Try <issender> tag
  LMatch := TRegEx.Match(ASourceXml,
    '<issender\s*>\s*(\d+)\s*</\s*issender\s*>',
    [roIgnoreCase]);
  if LMatch.Success then
  begin
    LIsSenderStr := LMatch.Groups[1].Value;
    AIsSender := LIsSenderStr = '1';
    Result := True;
    Exit;
  end;

  // Try as attribute of root tag
  LIsSenderStr := ExtractXmlAttr(ASourceXml, 'issender');
  if LIsSenderStr <> '' then
  begin
    AIsSender := LIsSenderStr = '1';
    Result := True;
  end;
end;

end.
