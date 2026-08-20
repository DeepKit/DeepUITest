unit DeepAxis.Core.Profile;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DeepAxis.Core.Base;

type
  /// <summary>
  ///   Capability matrix for personal_full / external_safe / strict_compliance.
  ///   Answers "is capability X enabled under the current Profile?"
  ///   The matrix is encoded as a constant lookup table.
  /// </summary>
  TDeepAxisProfile = class
  private type
    TCapModeEntry = record
      PersonalFull: string;
      ExternalSafe: string;
      StrictCompliance: string;
      class function Make(const APersonal, AExternal, AStrict: string): TCapModeEntry; static;
    end;
  private
    class var FCapabilityMatrix: TDictionary<string, TCapModeEntry>;
    class constructor Create;
    class destructor Destroy;
    class function GetModeForProfile(const AEntry: TCapModeEntry;
      const AProfile: TProfileIdentity): string; static;
  public
    class function Current: TProfileIdentity;
    class procedure SetProfile(const AIdentity: TProfileIdentity); overload;
    class procedure SetProfile(const AName: string); overload;

    class function IsCapabilityEnabled(const ACapabilityId: string): Boolean;
    class function GetCapabilityMode(const ACapabilityId: string): string;

    // Convenience accessors
    class function IsWeChatM0MetadataRead: Boolean;
    class function IsWeChatM1BodyRead: Boolean;
    class function IsWeChatM2Writeback: Boolean;
    class function IsWeChatM3UiaPaste: Boolean;
    class function IsWeChatFinalSend: Boolean;
    class function IsContactDelete: Boolean;
    class function IsBulkPrepare: Boolean;
    class function IsBulkWaveSending: Boolean;
    class function IsLLMLocal: Boolean;
    class function IsLLMCloud: Boolean;
    class function IsExportReport: Boolean;
  end;

implementation

uses
  DeepAxis.Core.Config;

{ TDeepAxisProfile }

class function TDeepAxisProfile.TCapModeEntry.Make(const APersonal, AExternal,
  AStrict: string): TCapModeEntry;
begin
  Result.PersonalFull := APersonal;
  Result.ExternalSafe := AExternal;
  Result.StrictCompliance := AStrict;
end;

class constructor TDeepAxisProfile.Create;
begin
  FCapabilityMatrix := TDictionary<string, TCapModeEntry>.Create;

  FCapabilityMatrix.Add(CAP_WECHAT_M0_METADATA,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_ON, CAP_MODE_ON));
  FCapabilityMatrix.Add(CAP_WECHAT_M1_BODY,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_PER_CONTACT_CONFIRM, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_WECHAT_M2_WRITEBACK,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_CONFIRM_EACH_BATCH, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_WECHAT_M3_UIA_PASTE,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_CONFIRM_EACH_BATCH, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_WECHAT_FINAL_SEND,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_OFF, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_CONTACT_DELETE,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_CONFIRM_EACH_CONTACT, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_BULK_PREPARE,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_CONFIRM_EACH_BATCH, CAP_MODE_CONFIRM_EACH_BATCH));
  FCapabilityMatrix.Add(CAP_BULK_WAVE,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_CONFIRM_EACH_WAVE, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_LLM_LOCAL,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_ON, CAP_MODE_ON));
  FCapabilityMatrix.Add(CAP_LLM_CLOUD,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_EXPLICIT_CONSENT, CAP_MODE_OFF));
  FCapabilityMatrix.Add(CAP_EXPORT_REPORT,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_PRIVACY_FILTERED, CAP_MODE_PRIVACY_FILTERED));
  FCapabilityMatrix.Add(CAP_MULTI_ACCOUNT,
    TCapModeEntry.Make(CAP_MODE_ON, CAP_MODE_ON, CAP_MODE_REVIEW_REQUIRED));
end;

class destructor TDeepAxisProfile.Destroy;
begin
  FCapabilityMatrix.Free;
end;

class function TDeepAxisProfile.GetModeForProfile(const AEntry: TCapModeEntry;
  const AProfile: TProfileIdentity): string;
begin
  case AProfile of
    piPersonalFull:     Result := AEntry.PersonalFull;
    piExternalSafe:     Result := AEntry.ExternalSafe;
    piStrictCompliance: Result := AEntry.StrictCompliance;
  else
    Result := CAP_MODE_OFF;
  end;
end;

class function TDeepAxisProfile.Current: TProfileIdentity;
begin
  Result := StrToProfileIdentity(TDeepAxisConfig.GetProfile);
end;

class procedure TDeepAxisProfile.SetProfile(const AIdentity: TProfileIdentity);
begin
  TDeepAxisConfig.SetProfile(ProfileIdentityToStr(AIdentity));
end;

class procedure TDeepAxisProfile.SetProfile(const AName: string);
begin
  TDeepAxisConfig.SetProfile(AName);
end;

class function TDeepAxisProfile.IsCapabilityEnabled(const ACapabilityId: string): Boolean;
var
  LMode: string;
begin
  LMode := GetCapabilityMode(ACapabilityId);
  Result := (LMode <> CAP_MODE_OFF);
end;

class function TDeepAxisProfile.GetCapabilityMode(const ACapabilityId: string): string;
var
  LEntry: TCapModeEntry;
begin
  if FCapabilityMatrix.TryGetValue(ACapabilityId, LEntry) then
    Result := GetModeForProfile(LEntry, Current)
  else
    Result := CAP_MODE_OFF; // unknown capability: deny by default
end;

// ── Convenience accessors ────────────────────────────────────────

class function TDeepAxisProfile.IsWeChatM0MetadataRead: Boolean;
begin Result := IsCapabilityEnabled(CAP_WECHAT_M0_METADATA); end;

class function TDeepAxisProfile.IsWeChatM1BodyRead: Boolean;
begin Result := IsCapabilityEnabled(CAP_WECHAT_M1_BODY); end;

class function TDeepAxisProfile.IsWeChatM2Writeback: Boolean;
begin Result := IsCapabilityEnabled(CAP_WECHAT_M2_WRITEBACK); end;

class function TDeepAxisProfile.IsWeChatM3UiaPaste: Boolean;
begin Result := IsCapabilityEnabled(CAP_WECHAT_M3_UIA_PASTE); end;

class function TDeepAxisProfile.IsWeChatFinalSend: Boolean;
begin Result := IsCapabilityEnabled(CAP_WECHAT_FINAL_SEND); end;

class function TDeepAxisProfile.IsContactDelete: Boolean;
begin Result := IsCapabilityEnabled(CAP_CONTACT_DELETE); end;

class function TDeepAxisProfile.IsBulkPrepare: Boolean;
begin Result := IsCapabilityEnabled(CAP_BULK_PREPARE); end;

class function TDeepAxisProfile.IsBulkWaveSending: Boolean;
begin Result := IsCapabilityEnabled(CAP_BULK_WAVE); end;

class function TDeepAxisProfile.IsLLMLocal: Boolean;
begin Result := IsCapabilityEnabled(CAP_LLM_LOCAL); end;

class function TDeepAxisProfile.IsLLMCloud: Boolean;
begin Result := IsCapabilityEnabled(CAP_LLM_CLOUD); end;

class function TDeepAxisProfile.IsExportReport: Boolean;
begin Result := IsCapabilityEnabled(CAP_EXPORT_REPORT); end;

end.