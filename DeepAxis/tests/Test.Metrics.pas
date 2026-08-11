unit Test.Metrics;

interface

uses
  System.SysUtils, System.DateUtils,
  DUnitX.TestFramework,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Pipeline.Metrics,
  Test.Base;

type
  [TestFixture]
  TTestMetrics = class
  public
    [Test]
    procedure TestComputeEmptyMessages;
    [Test]
    procedure TestComputeWithMessages;
    [Test]
    procedure TestComputeDataQuality;
    [Test]
    procedure TestComputeOutboundInboundRatio;
    [Test]
    procedure TestComputeBatch;
  end;

implementation

function MakeInboundMsg(const AContactId: string; ADaysAgo: Integer): TMessageMeta;
begin
  Result := TMessageMeta.CreateM0;
  Result.ContactId := AContactId;
  Result.Direction := dInbound;
  Result.SentAt := IncDay(Now, -ADaysAgo);
end;

function MakeOutboundMsg(const AContactId: string; ADaysAgo: Integer): TMessageMeta;
begin
  Result := TMessageMeta.CreateM0;
  Result.ContactId := AContactId;
  Result.Direction := dOutbound;
  Result.SentAt := IncDay(Now, -ADaysAgo);
end;

{ TTestMetrics }

procedure TTestMetrics.TestComputeEmptyMessages;
begin
  var LCalc := TMetricCalculator.Create(False); // No DB storage in tests
  var LOldMetric := Default(TInteractionMetric);
  var LMetric := LCalc.Compute(nil, LOldMetric);
  Assert.AreEqual(dqDataInsufficient, LMetric.DataQuality);
  Assert.IsFalse(LMetric.IsValid);
end;

procedure TTestMetrics.TestComputeWithMessages;
begin
  var LCalc := TMetricCalculator.Create(False); // No DB storage in tests
  var LMsgs: TArray<TMessageMeta>;
  SetLength(LMsgs, 10);
  for var I := 0 to 4 do LMsgs[I] := MakeInboundMsg('c1', I);
  for var I := 0 to 4 do LMsgs[I + 5] := MakeOutboundMsg('c1', I + 5);

  var LOldMetric := Default(TInteractionMetric);
  var LMetric := LCalc.Compute(LMsgs, LOldMetric);

  Assert.AreEqual(5, LMetric.InboundCount);
  Assert.AreEqual(5, LMetric.OutboundCount);
  Assert.AreEqual('c1', LMetric.ContactId);
end;

procedure TTestMetrics.TestComputeDataQuality;
begin
  var LCalc := TMetricCalculator.Create(False); // No DB storage in tests
  var LMsgs: TArray<TMessageMeta>;
  SetLength(LMsgs, 3);
  LMsgs[0] := MakeInboundMsg('c1', 0);
  LMsgs[1] := MakeInboundMsg('c1', 1);
  LMsgs[2] := MakeOutboundMsg('c1', 2);

  var LMetric := LCalc.Compute(LMsgs, Default(TInteractionMetric));
  Assert.AreEqual(dqDataInsufficient, LMetric.DataQuality,
    '3 messages should be insufficient');

  SetLength(LMsgs, 10);
  for var I := 0 to 9 do LMsgs[I] := MakeInboundMsg('c1', I);
  LMetric := LCalc.Compute(LMsgs, Default(TInteractionMetric));
  Assert.AreEqual(dqPartial, LMetric.DataQuality,
    '10 messages should be partial');

  SetLength(LMsgs, 25);
  for var I := 0 to 24 do LMsgs[I] := MakeInboundMsg('c1', I);
  LMetric := LCalc.Compute(LMsgs, Default(TInteractionMetric));
  Assert.AreEqual(dqOK, LMetric.DataQuality,
    '25 messages should be OK');
end;

procedure TTestMetrics.TestComputeOutboundInboundRatio;
begin
  var LCalc := TMetricCalculator.Create(False); // No DB storage in tests
  var LMsgs: TArray<TMessageMeta>;
  SetLength(LMsgs, 20);
  for var I := 0 to 14 do LMsgs[I] := MakeOutboundMsg('c1', I);
  for var I := 0 to 4 do LMsgs[I + 15] := MakeInboundMsg('c1', I + 15);

  var LMetric := LCalc.Compute(LMsgs, Default(TInteractionMetric));
  Assert.AreEqual(15, LMetric.OutboundCount);
  Assert.AreEqual(5, LMetric.InboundCount);
  Assert.AreEqual(3.0, LMetric.OutboundInboundRatio, 0.01);
end;

procedure TTestMetrics.TestComputeBatch;
begin
  var LCalc := TMetricCalculator.Create(False); // No DB storage in tests
  var LContacts := TArray<TContact>.Create(
    Default(TContact), Default(TContact));
  LContacts[0].ContactId := 'c1';
  LContacts[1].ContactId := 'c2';

  var LMsgs: TArray<TMessageMeta>;
  SetLength(LMsgs, 20);
  for var I := 0 to 9 do begin LMsgs[I] := MakeInboundMsg('c1', I); LMsgs[I].ContactId := 'c1'; end;
  for var I := 0 to 9 do begin LMsgs[I + 10] := MakeOutboundMsg('c2', I); LMsgs[I + 10].ContactId := 'c2'; end;

  var LMetrics := LCalc.ComputeBatch(LContacts, LMsgs, nil);
  Assert.AreEqual<Integer>(2, Length(LMetrics));
end;

end.