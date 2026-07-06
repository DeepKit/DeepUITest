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
  public
    function ClassifyContacts(const AContacts: TArray<TContact>): TArray<TContact>;
    function GetAdSuggestions(const AContact: TContact): string;
    function GetDeletionCandidates(const AContacts: TArray<TContact>): TArray<TContact>;
  end;

implementation

{ TIdleFunnel }

function TIdleFunnel.GetAdMaxCount: Integer;
begin
  Result := AD_MAX_COUNT;
end;

function TIdleFunnel.IsIdle(const AContact: TContact): Boolean;
begin
  // P0: all contacts are idle (no product association)
  Result := True;
end;

function TIdleFunnel.GetAdCount(const AContact: TContact): Integer;
var
  LProfile: TJSONObject;
  LAdTrack: TJSONObject;
begin
  Result := 0;
  try
    LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
    if (LProfile <> nil) and LProfile.TryGetValue('ad_track', LAdTrack) then
      Result := LAdTrack.GetValue<Integer>('ad_count', 0);
  except
    Result := 0;
  end;
end;

function TIdleFunnel.GetLastAdAt(const AContact: TContact): TDateTime;
var
  LProfile: TJSONObject;
  LAdTrack: TJSONObject;
  LDateStr: string;
begin
  Result := 0;
  try
    LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
    if (LProfile <> nil) and LProfile.TryGetValue('ad_track', LAdTrack) then
    begin
      LDateStr := LAdTrack.GetValue<string>('last_ad_at', '');
      if LDateStr <> '' then
        Result := ISO8601ToDate(LDateStr);
    end;
  except
    Result := 0;
  end;
end;

function TIdleFunnel.ClassifyContacts(const AContacts: TArray<TContact>): TArray<TContact>;
var
  I: Integer;
  LContact: TContact;
  LAdCount: Integer;
  LLastAdAt: TDateTime;
  LIdleStatus: TIdleStatus;
  LProfile: TJSONObject;
  LAdTrack: TJSONObject;
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

    // Update contact's tag_profile with idle status
    LProfile := TJSONObject.Create;
    try
      if LContact.TagProfile <> '' then
      begin
        try
          LProfile := TJSONObject.ParseJSONValue(LContact.TagProfile) as TJSONObject;
        except
          // Use empty
        end;
      end;

      if LProfile = nil then
        LProfile := TJSONObject.Create;

      LProfile.RemovePair('ad_track');
      LAdTrack := TJSONObject.Create;
      LAdTrack.AddPair('ad_count', TJSONNumber.Create(LAdCount));
      LAdTrack.AddPair('idle_status', Ord(LIdleStatus).ToString);
      LProfile.AddPair('ad_track', LAdTrack);

      Result[I].TagProfile := LProfile.ToJSON;
    finally
      LProfile.Free;
    end;
  end;
end;

function TIdleFunnel.GetAdSuggestions(const AContact: TContact): string;
var
  LChannel: string;
begin
  // Extract channel from tag profile for personalized suggestions
  LChannel := '';
  try
    var LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
    if LProfile <> nil then
    begin
      var LChannelObj := LProfile.GetValue('channel') as TJSONObject;
      if LChannelObj <> nil then
        LChannel := LChannelObj.GetValue<string>('label', '');
    end;
  except
  end;

  if LChannel <> '' then
    Result := Format('建议通过%s渠道接触该联系人', [LChannel])
  else
    Result := '建议选择合适时机发送首次触达消息';
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