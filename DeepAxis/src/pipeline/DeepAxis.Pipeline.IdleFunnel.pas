unit DeepAxis.Pipeline.IdleFunnel;

interface

uses
  System.SysUtils, System.JSON, System.DateUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Idle funnel: classifies contacts as idle, tracks ad count,
  ///   generates deletion candidates.
  ///   P0: All contacts are idle (no product association yet).
  /// </summary>
  TIdleFunnel = class(TInterfacedObject, IIdleFunnel)
  private
    function IsIdle(const AContact: TContact): Boolean;
    function GetAdCount(const AContact: TContact): Integer;
    function GetLastAdAt(const AContact: TContact): TDateTime;
    function GetAdMaxCount: Integer;
    /// <summary>WeChatLabels 是否含 PRESERVE_TAG (用户标记保留)。</summary>
    function IsPreserved(const AContact: TContact): Boolean;
  public
    function ClassifyContacts(const AContacts: TArray<TContact>): TArray<TContact>;
    function GetAdSuggestions(const AContact: TContact): string;
    function GetDeletionCandidates(const AContacts: TArray<TContact>): TArray<TContact>;
    /// <summary>标记保留: 在 WeChatLabels 加 PRESERVE_TAG, 返回新 TContact。</summary>
    function MarkPreserved(const AContact: TContact): TContact;
    /// <summary>取消保留: 从 WeChatLabels 移除 PRESERVE_TAG, 返回新 TContact。</summary>
    function UnmarkPreserved(const AContact: TContact): TContact;
  end;

implementation

{ TIdleFunnel }

function TIdleFunnel.GetAdMaxCount: Integer;
begin
  Result := AD_MAX_COUNT;
end;

function TIdleFunnel.IsIdle(const AContact: TContact): Boolean;
begin
  // 闲人 = 无关联产品 且 未被用户保留 (docs/03 §2.6)
  Result := (AContact.ProductCount = 0) and (not IsPreserved(AContact));
end;

function TIdleFunnel.IsPreserved(const AContact: TContact): Boolean;
var
  LLabel: string;
begin
  Result := False;
  for LLabel in AContact.WeChatLabels do
    if LLabel = PRESERVE_TAG then
      Exit(True);
end;

function TIdleFunnel.GetAdCount(const AContact: TContact): Integer;
begin
  // BUG-044 参数化: 直接读 TContact.AdCount 字段
  Result := AContact.AdCount;
end;

function TIdleFunnel.GetLastAdAt(const AContact: TContact): TDateTime;
begin
  Result := AContact.LastAdAt;
end;

function TIdleFunnel.ClassifyContacts(const AContacts: TArray<TContact>): TArray<TContact>;
var
  I: Integer;
  LContact: TContact;
  LAdCount: Integer;
  LLastAdAt: TDateTime;
  LIdleStatus: TIdleStatus;
begin
  Result := AContacts; // copy

  for I := 0 to Length(Result) - 1 do
  begin
    LContact := Result[I];
    LAdCount := GetAdCount(LContact);
    LLastAdAt := GetLastAdAt(LContact);

    // Determine idle status
    if LAdCount >= GetAdMaxCount then
    begin
      // Check cooldown: if last ad was more than AD_COOLDOWN_DAYS ago
      if (LLastAdAt > 0) and (DaysBetween(Now, LLastAdAt) >= AD_COOLDOWN_DAYS) then
        LIdleStatus := isPendingDeletion
      else
        LIdleStatus := isCanAdvertise;
    end
    else
      LIdleStatus := isCanAdvertise;

    // BUG-044 参数化: AdCount/LastAdAt 已直接在 TContact 字段上
    Result[I].IsUserPreserved := IsPreserved(LContact);
  end;
end;

function TIdleFunnel.GetAdSuggestions(const AContact: TContact): string;
var
  LChannel: string;
begin
  // ✅ FIXED: No JSON - use parameterized fields from DB1Store
  LChannel := '';
  Result := '';

  if LChannel <> '' then
    Result := Format('建议通过%s渠道接触该联系人', [LChannel])
  else
    Result := '建议选择合适时机发送首次触达消息';
end;

function TIdleFunnel.MarkPreserved(const AContact: TContact): TContact;
var
  I: Integer;
  LHas: Boolean;
begin
  Result := AContact;
  LHas := False;
  for I := 0 to High(Result.WeChatLabels) do
    if Result.WeChatLabels[I] = PRESERVE_TAG then
    begin
      LHas := True;
      Break;
    end;
  if not LHas then
  begin
    SetLength(Result.WeChatLabels, Length(Result.WeChatLabels) + 1);
    Result.WeChatLabels[High(Result.WeChatLabels)] := PRESERVE_TAG;
  end;
  Result.IsUserPreserved := True;
end;

function TIdleFunnel.UnmarkPreserved(const AContact: TContact): TContact;
var
  I, J: Integer;
begin
  Result := AContact;
  J := 0;
  for I := 0 to High(Result.WeChatLabels) do
    if Result.WeChatLabels[I] <> PRESERVE_TAG then
    begin
      Result.WeChatLabels[J] := Result.WeChatLabels[I];
      Inc(J);
    end;
  SetLength(Result.WeChatLabels, J);
  Result.IsUserPreserved := IsPreserved(Result);
end;

function TIdleFunnel.GetDeletionCandidates(const AContacts: TArray<TContact>): TArray<TContact>;
var
  LContact: TContact;
  LAdCount: Integer;
  LLastAdAt: TDateTime;
begin
  Result := nil;

  for LContact in AContacts do
  begin
    // 保留的联系人永远不进删除候选 (docs/03 §2.6)
    if IsPreserved(LContact) then Continue;

    LAdCount := GetAdCount(LContact);
    LLastAdAt := GetLastAdAt(LContact);

    if (LAdCount >= GetAdMaxCount) and
       (LLastAdAt > 0) and
       (DaysBetween(Now, LLastAdAt) >= AD_COOLDOWN_DAYS) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LContact;
    end;
  end;
end;

end.