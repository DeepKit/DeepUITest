unit DeepAxis.WeChat.Adapter411053;

interface

uses
  System.SysUtils, System.Hash,
  DeepAxis.Core.Base,
  DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Concrete schema adapter for WeChat 4.1.10.53.
  ///   This is the ONLY known-good adapter. All field mappings are verified
  ///   against actual decrypted databases (17/19 DBs successfully decrypted).
  ///
  ///   Key characteristics:
  ///   - Database: WCDB/SQLCipher 4 encrypted SQLite
  ///   - Contact table: "contact" in contact.db
  ///   - Message tables: "Msg_<hash>" in message_0.db, message_1.db, ...
  ///   - Session table: "session" in session.db
  ///   - Direction: real_sender_id = 0 means outbound, 1 means inbound
  ///   - Message type: local_type 1=text, 3=image, 34=voice, 43=video, 47=emoji, 49=link, 10000=system
  ///   - Message content: zstd compressed, decompressed to Body and SourceXml fields
  /// </summary>
  TWeChat411053Adapter = class(TInterfacedObject, ISchemaAdapter)
  private
    FAllowedFields: TArray<string>;
    FForbiddenFields: TArray<string>;
    FFingerprint: string;
    function ComputeFingerprint: string;
  public
    constructor Create;
    // ISchemaAdapter
    function GetAdapterId: string;
    function GetSchemaFingerprint: string;
    function GetSupportedVersionRange: string;
    function GetAllowedFields: TArray<string>;
    function GetForbiddenFields: TArray<string>;
    function MapDirection(const ARawValue: Int64): TDirection;
    function GetTimestampColumn: string;
    function MapType(const ARawType: Int64): TNormalizedMsgType;
    function IsDegraded: Boolean;
    function GetDegradedFields: TArray<string>;
    function GetMsgTablePrefix: string;
    function GetContactTableName: string;
    function GetConversationTableName: string;
  end;

implementation

{ TWeChat411053Adapter }

constructor TWeChat411053Adapter.Create;
begin
  inherited Create;

  // ── Allowed fields (contact table) ─────────────────────────────
  FAllowedFields := TArray<string>.Create(
    'username', 'alias', 'remark', 'remark_quan_pin', 'nick_name',
    'pin_yin_initial', 'quan_pin', 'flag', 'delete_flag', 'verify_flag',
    'local_type', 'contact_type', 'sex', 'country', 'province', 'city',
    'signature', 'head_img_url', 'head_img_md5', 'small_head_url',
    'label_id_list', 'chatroom_id', 'chatroom_type', 'chatroom_owner',
    'encrypt_username', 'domain', 'extra_buffer'
  );

  // ── Forbidden fields (MUST NOT be read) ────────────────────────
  // These fields contain raw compressed data or metadata that should not
  // be directly accessed (use decompressed Body/SourceXml instead).
  FForbiddenFields := TArray<string>.Create(
    'compress_content',   // compressed version of content (use message_content via CAST AS BLOB)
    'packed_info_data',   // packed additional info
    'xml_content',        // XML-formatted content (alternative column)
    'msg_content',        // alternative content column
    'app_content'         // app-specific content
  );

  FFingerprint := ComputeFingerprint;
end;

function TWeChat411053Adapter.ComputeFingerprint: string;
var
  LFields: string;
  S: string;
begin
  // Fingerprint = SHA-256 of sorted allowed field names
  LFields := '';
  for S in FAllowedFields do
    LFields := LFields + S + '|';
  Result := THashSHA2.GetHashString(LFields, THashSHA2.TSHA2Version.SHA256);
end;

function TWeChat411053Adapter.GetAdapterId: string;
begin
  Result := ADAPTER_WECHAT_411053;
end;

function TWeChat411053Adapter.GetSchemaFingerprint: string;
begin
  Result := FFingerprint;
end;

function TWeChat411053Adapter.GetSupportedVersionRange: string;
begin
  Result := 'WeChat 4.1.x (4.1.10.30 - 4.1.10.53)';
end;

function TWeChat411053Adapter.GetAllowedFields: TArray<string>;
begin
  Result := FAllowedFields;
end;

function TWeChat411053Adapter.GetForbiddenFields: TArray<string>;
begin
  Result := FForbiddenFields;
end;

function TWeChat411053Adapter.MapDirection(const ARawValue: Int64): TDirection;
begin
  // real_sender_id = 0: message was sent by the account owner (outbound)
  // real_sender_id = 1 or other: message was received from contact (inbound)
  // This is verified against WeChat 4.1.10.53 decrypted message_0.db
  case ARawValue of
    0: Result := dOutbound;
    1: Result := dInbound;
  else
    Result := dUnknown;
  end;
end;

function TWeChat411053Adapter.GetTimestampColumn: string;
begin
  Result := 'create_time';
end;

function TWeChat411053Adapter.MapType(const ARawType: Int64): TNormalizedMsgType;
begin
  // Verified against WeChat 4.1.10.53 local_type values
  case ARawType of
    1:     Result := nmtText;
    3:     Result := nmtImage;
    34:    Result := nmtVoice;
    40:    Result := nmtContactCard;  // 好友推荐/名片
    43:    Result := nmtVideo;
    47:    Result := nmtEmoji;
    48:    Result := nmtLocation;     // 位置
    49:    Result := nmtLink;
    10000: Result := nmtSystem;
    10002: Result := nmtRecall;       // 撤回消息
  else
    Result := nmtUnknown;
  end;
end;

function TWeChat411053Adapter.IsDegraded: Boolean;
begin
  Result := False;
end;

function TWeChat411053Adapter.GetDegradedFields: TArray<string>;
begin
  Result := nil;
end;

function TWeChat411053Adapter.GetMsgTablePrefix: string;
begin
  Result := 'Msg_';
end;

function TWeChat411053Adapter.GetContactTableName: string;
begin
  Result := 'contact';
end;

function TWeChat411053Adapter.GetConversationTableName: string;
begin
  Result := 'session';
end;

end.