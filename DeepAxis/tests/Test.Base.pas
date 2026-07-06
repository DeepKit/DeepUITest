unit Test.Base;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.DateUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.WeChat.Adapter,
  DeepAxis.WeChat.Adapter411053;

type
  /// <summary>
  ///   Mock IWxReader that returns pre-configured data without real DB access.
  ///   Use TestFixtureFactory to build test data sets.
  /// </summary>
  TMockWxReader = class(TInterfacedObject, IWxReader)
  private
    FContacts: TArray<TContact>;
    FMessages: TDictionary<string, TArray<TMessageMeta>>;
    FConversations: TArray<TConversation>;
    FIsOpen: Boolean;
    FAdapter: ISchemaAdapter;
    FCursors: TScanCursorArray;
  public
    constructor Create;
    destructor Destroy; override;

    // Pre-configure data
    procedure SetContacts(const AContacts: TArray<TContact>);
    procedure SetMessages(const AContactId: string; const AMessages: TArray<TMessageMeta>);
    procedure SetConversations(const AConversations: TArray<TConversation>);

    // IWxReader
    function Open(const ADbPath: string; const AKeyBytes: TBytes): Boolean;
    function OpenPaths(const AContactPath, AMessage0Path, ASessionPath: string): Boolean;
    function ReadContacts: TArray<TContact>;
    function ReadMessages(const AContactId: string;
      const ASince: TScanCursor): TArray<TMessageMeta>;
    function ReadAllMessages(const ASince: TScanCursor):
      TDictionary<string, TArray<TMessageMeta>>;
    function ReadConversations: TArray<TConversation>;
    function GetScanCursors: TScanCursorArray;
    procedure Close;
    function IsOpen: Boolean;
    function GetAdapter: ISchemaAdapter;
  end;

  /// <summary>
  ///   Factory for creating test fixture data.
  ///   All data is synthetic — no real DB access required.
  /// </summary>
  TTestFixtureFactory = class
  public
    /// <summary>Create a business contact with the given ID and display name.</summary>
    class function MakeContact(const AId: string; const ADisplayName: string): TContact; static;

    /// <summary>Create an inbound message for the given contact.</summary>
    class function MakeInboundMsg(const AContactId: string; ADaysAgo: Integer): TMessageMeta; static;

    /// <summary>Create an outbound message for the given contact.</summary>
    class function MakeOutboundMsg(const AContactId: string; ADaysAgo: Integer): TMessageMeta; static;

    /// <summary>Create a set of messages with balanced inbound/outbound.</summary>
    class function MakeBalancedMessages(const AContactId: string;
      AInboundCount, AOutboundCount: Integer): TArray<TMessageMeta>; static;

    /// <summary>Create a metric with the given properties.</summary>
    class function MakeMetric(const AContactId: string; AInbound, AOutbound: Integer;
      ADaysSinceLast: Integer; AQuality: TDataQuality): TInteractionMetric; static;
  end;

implementation

{ TMockWxReader }

constructor TMockWxReader.Create;
begin
  inherited Create;
  FMessages := TDictionary<string, TArray<TMessageMeta>>.Create;
  FIsOpen := True;
  FAdapter := TWeChat411053Adapter.Create;
end;

destructor TMockWxReader.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TMockWxReader.SetContacts(const AContacts: TArray<TContact>);
begin
  FContacts := AContacts;
end;

procedure TMockWxReader.SetMessages(const AContactId: string;
  const AMessages: TArray<TMessageMeta>);
begin
  FMessages.AddOrSetValue(AContactId, AMessages);
end;

procedure TMockWxReader.SetConversations(const AConversations: TArray<TConversation>);
begin
  FConversations := AConversations;
end;

function TMockWxReader.Open(const ADbPath: string; const AKeyBytes: TBytes): Boolean;
begin
  FIsOpen := True;
  Result := True;
end;

function TMockWxReader.OpenPaths(const AContactPath, AMessage0Path,
  ASessionPath: string): Boolean;
begin
  FIsOpen := True;
  Result := True;
end;

function TMockWxReader.ReadContacts: TArray<TContact>;
begin
  Result := FContacts;
end;

function TMockWxReader.ReadMessages(const AContactId: string;
  const ASince: TScanCursor): TArray<TMessageMeta>;
begin
  if not FMessages.TryGetValue(AContactId, Result) then
    Result := nil;
end;

function TMockWxReader.ReadAllMessages(const ASince: TScanCursor):
  TDictionary<string, TArray<TMessageMeta>>;
begin
  // Return a copy of the internal dictionary
  Result := TDictionary<string, TArray<TMessageMeta>>.Create;
  var LPair: TPair<string, TArray<TMessageMeta>>;
  for LPair in FMessages do
    Result.Add(LPair.Key, LPair.Value);
end;

function TMockWxReader.ReadConversations: TArray<TConversation>;
begin
  Result := FConversations;
end;

function TMockWxReader.GetScanCursors: TScanCursorArray;
begin
  Result := FCursors;
end;

procedure TMockWxReader.Close;
begin
  FIsOpen := False;
end;

function TMockWxReader.IsOpen: Boolean;
begin
  Result := FIsOpen;
end;

function TMockWxReader.GetAdapter: ISchemaAdapter;
begin
  Result := FAdapter;
end;

{ TTestFixtureFactory }

class function TTestFixtureFactory.MakeContact(const AId: string;
  const ADisplayName: string): TContact;
begin
  Result := Default(TContact);
  Result.ContactId := AId;
  Result.DisplayNameHash := SHA256Hex(ADisplayName);
  Result.DisplayNameRedacted := ADisplayName;
  Result.Privacy := psBusiness;
  Result.PrivacySource := psHumanConfirmed;
  Result.TagProfile := '{}';
end;

class function TTestFixtureFactory.MakeInboundMsg(const AContactId: string;
  ADaysAgo: Integer): TMessageMeta;
begin
  Result := TMessageMeta.CreateM0;
  Result.ContactId := AContactId;
  Result.Direction := dInbound;
  Result.SentAt := IncDay(Now, -ADaysAgo);
  Result.SourceAccountId := 'test-account';
end;

class function TTestFixtureFactory.MakeOutboundMsg(const AContactId: string;
  ADaysAgo: Integer): TMessageMeta;
begin
  Result := TMessageMeta.CreateM0;
  Result.ContactId := AContactId;
  Result.Direction := dOutbound;
  Result.SentAt := IncDay(Now, -ADaysAgo);
  Result.SourceAccountId := 'test-account';
end;

class function TTestFixtureFactory.MakeBalancedMessages(const AContactId: string;
  AInboundCount, AOutboundCount: Integer): TArray<TMessageMeta>;
var
  I: Integer;
begin
  SetLength(Result, AInboundCount + AOutboundCount);
  for I := 0 to AInboundCount - 1 do
    Result[I] := MakeInboundMsg(AContactId, I);
  for I := 0 to AOutboundCount - 1 do
    Result[AInboundCount + I] := MakeOutboundMsg(AContactId, AInboundCount + I);
end;

class function TTestFixtureFactory.MakeMetric(const AContactId: string;
  AInbound, AOutbound: Integer; ADaysSinceLast: Integer;
  AQuality: TDataQuality): TInteractionMetric;
begin
  Result := Default(TInteractionMetric);
  Result.MetricId := GenerateId;
  Result.ContactId := AContactId;
  Result.SourceAccountId := 'test-account';
  Result.InboundCount := AInbound;
  Result.OutboundCount := AOutbound;
  if ADaysSinceLast > 0 then
    Result.LastInteractionAt := IncDay(Now, -ADaysSinceLast);
  Result.DataQuality := AQuality;
  Result.ComputedAt := Now;
end;

end.