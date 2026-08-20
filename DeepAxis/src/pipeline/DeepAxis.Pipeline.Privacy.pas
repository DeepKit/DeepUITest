unit DeepAxis.Pipeline.Privacy;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   Privacy classification engine.
  ///   P0 M0: Uses metadata signals only (no body content).
  ///   Default-reject: UNKNOWN contacts are excluded from analysis.
  ///   PRIVATE contacts are excluded and their derived data is cascade-deleted.
  /// </summary>
  TPrivacyClassifier = class
  private
    // Known patterns for privacy detection
    class var FPrivateKeywords: TArray<string>;
    class var FBusinessKeywords: TArray<string>;
    class constructor Create;
    function IsPrivateByGroup(const AContact: TContact; const AConversations: TArray<TConversation>): Boolean;
    function IsPrivateByLabels(const AContact: TContact): Boolean;
    function IsPrivateByPattern(const AContact: TContact): Boolean;
  public
    /// <summary>Classify a single contact. Returns updated privacy scope.</summary>
    function Classify(const AContact: TContact;
      const AConversations: TArray<TConversation>): TContact;

    /// <summary>Batch classify all contacts.</summary>
    function ClassifyBatch(const AContacts: TArray<TContact>;
      const AConversations: TArray<TConversation>): TArray<TContact>;

    /// <summary>Get contacts that should be excluded from radar.</summary>
    function FilterExcluded(const AContacts: TArray<TContact>): TArray<TContact>;

    /// <summary>Get contacts that are safe for analysis.</summary>
    function FilterBusiness(const AContacts: TArray<TContact>): TArray<TContact>;

    /// <summary>Cascade delete derived data for a PRIVATE contact.</summary>
    procedure CascadeDelete(var AContact: TContact);
  end;

implementation

{ TPrivacyClassifier }

class constructor TPrivacyClassifier.Create;
begin
  // Private keywords: family members, personal relationships
  FPrivateKeywords := TArray<string>.Create(
    '老婆', '老公', '爸爸', '妈妈', '爸', '妈', '儿子', '女儿',
    '舅舅', '姑姑', '姨妈', '叔叔', '姐姐', '哥哥', '弟弟', '妹妹',
    '宝贝', '亲爱的', '老公大人', '老婆大人',
    '丈母娘', '婆婆', '公公', '岳父', '岳母'
  );

  // Business keywords: customer-related
  FBusinessKeywords := TArray<string>.Create(
    '客户', '顾客', '买家', '老板', '总', '经理', '代理',
    '下单', '发货', '付款', '订单', '物流', '快递',
    '微信号', '二维码', '加好友', '咨询', '了解'
  );
end;

function TPrivacyClassifier.IsPrivateByGroup(const AContact: TContact;
  const AConversations: TArray<TConversation>): Boolean;
var
  LConv: TConversation;
begin
  Result := False;
  // If contact is in a group chat with family-like name
  for LConv in AConversations do
    if LConv.Kind = 'GROUP' then
    begin
      for var LK in FPrivateKeywords do
        if Pos(LK, LConv.ConversationId) > 0 then
          Exit(True);
    end;
end;

function TPrivacyClassifier.IsPrivateByLabels(const AContact: TContact): Boolean;
const
  FAMILY_LABELS: array[0..3] of string = ('家人', '亲戚', '家庭', '亲友');
  FRIEND_LABELS: array[0..2] of string = ('朋友', '好友', '死党');
var
  L: string;
begin
  Result := False;
  for L in AContact.WeChatLabels do
  begin
    for var LF in FAMILY_LABELS do
      if L.Contains(LF) then Exit(True);
    for var LF in FRIEND_LABELS do
      if L.Contains(LF) then
      begin
        // 朋友标签: 不直接判 PRIVATE，设为 UNKNOWN 等待用户确认
        Exit(False);
      end;
  end;
end;

function TPrivacyClassifier.IsPrivateByPattern(const AContact: TContact): Boolean;
var
  LDisplayName: string;
begin
  Result := False;
  LDisplayName := AContact.DisplayNameRedacted;

  for var LK in FPrivateKeywords do
    if Pos(LK, LDisplayName) > 0 then
      Exit(True);
end;

function TPrivacyClassifier.Classify(const AContact: TContact;
  const AConversations: TArray<TConversation>): TContact;
begin
  Result := AContact;

  // Already confirmed — don't override
  if Result.PrivacySource = psHumanConfirmed then
    Exit;

  // Check private signals
  if IsPrivateByLabels(Result) then
  begin
    Result.Privacy := psPrivate;
    Result.PrivacySource := psSystemGuess;
    Exit;
  end;

  if IsPrivateByGroup(Result, AConversations) then
  begin
    Result.Privacy := psPrivate;
    Result.PrivacySource := psSystemGuess;
    Exit;
  end;

  if IsPrivateByPattern(Result) then
  begin
    Result.Privacy := psPrivate;
    Result.PrivacySource := psSystemGuess;
    Exit;
  end;

  // Default: UNKNOWN — exclude from analysis until user confirms
  Result.Privacy := psUnknown;
  Result.PrivacySource := psSystemGuess;
end;

function TPrivacyClassifier.ClassifyBatch(const AContacts: TArray<TContact>;
  const AConversations: TArray<TConversation>): TArray<TContact>;
var
  I: Integer;
begin
  SetLength(Result, Length(AContacts));
  for I := 0 to Length(AContacts) - 1 do
    Result[I] := Classify(AContacts[I], AConversations);
end;

function TPrivacyClassifier.FilterExcluded(const AContacts: TArray<TContact>): TArray<TContact>;
var
  LContact: TContact;
begin
  Result := nil;
  for LContact in AContacts do
    if LContact.Privacy in [psPrivate, psUnknown] then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LContact;
    end;
end;

function TPrivacyClassifier.FilterBusiness(const AContacts: TArray<TContact>): TArray<TContact>;
var
  LContact: TContact;
begin
  Result := nil;
  for LContact in AContacts do
    if LContact.IsBusiness then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LContact;
    end;
end;

procedure TPrivacyClassifier.CascadeDelete(var AContact: TContact);
begin
  // ✅ FIXED: Reset all derived data without TagProfile JSON
  AContact.ProductCount := 0;
  AContact.IsUserPreserved := False;
  AContact.Privacy := psPrivate;
  AContact.PrivacySource := psHumanConfirmed;
  AContact.LastSeen := 0;
end;

end.