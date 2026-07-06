unit Test.Radar;

interface

uses
  System.SysUtils, System.DateUtils,
  DUnitX.TestFramework,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Pipeline.Radar,
  Test.Base;

type
  [TestFixture]
  TTestRadar = class
  public
    [Test]
    procedure TestGenerateDataInsufficient;
    [Test]
    procedure TestGenerateLongSilence;
    [Test]
    procedure TestGenerateOutboundHeavy;
    [Test]
    procedure TestSkipPrivateContacts;
    [Test]
    procedure TestConfidenceCalculation;
  end;

implementation

{ TTestRadar }

procedure TTestRadar.TestGenerateDataInsufficient;
begin
  var LEngine := TRadarEngine.Create;
  var LContact := Default(TContact);
  LContact.ContactId := 'c1';
  LContact.Privacy := psBusiness;

  var LMetric := Default(TInteractionMetric);
  LMetric.ContactId := 'c1';
  LMetric.DataQuality := dqDataInsufficient;
  LMetric.InboundCount := 0;
  LMetric.OutboundCount := 0;

  var LHints := LEngine.Generate([LMetric], [LContact], nil);
  Assert.IsTrue(Length(LHints) > 0, 'Should generate at least 1 hint');
  Assert.AreEqual(rhtDataInsufficient, LHints[0].HintType);
end;

procedure TTestRadar.TestGenerateLongSilence;
begin
  var LEngine := TRadarEngine.Create;
  var LContact := Default(TContact);
  LContact.ContactId := 'c1';
  LContact.Privacy := psBusiness;

  var LMetric := Default(TInteractionMetric);
  LMetric.ContactId := 'c1';
  LMetric.LastInteractionAt := IncDay(Now, -45);
  LMetric.InboundCount := 20;
  LMetric.OutboundCount := 15;
  LMetric.DataQuality := dqOK;

  var LHints := LEngine.Generate([LMetric], [LContact], nil);
  Assert.IsTrue(Length(LHints) > 0, 'Should generate long silence hint');
  Assert.AreEqual(rhtLongSilence, LHints[0].HintType);
end;

procedure TTestRadar.TestGenerateOutboundHeavy;
begin
  var LEngine := TRadarEngine.Create;
  var LContact := Default(TContact);
  LContact.ContactId := 'c1';
  LContact.Privacy := psBusiness;

  var LMetric := Default(TInteractionMetric);
  LMetric.ContactId := 'c1';
  LMetric.LastInteractionAt := IncDay(Now, -2);
  LMetric.InboundCount := 2;
  LMetric.OutboundCount := 20;
  LMetric.OutboundInboundRatio := 10.0;
  LMetric.DataQuality := dqOK;

  var LHints := LEngine.Generate([LMetric], [LContact], nil);
  Assert.IsTrue(Length(LHints) > 0, 'Should generate outbound_heavy hint');
  Assert.AreEqual(rhtOutboundHeavy, LHints[0].HintType);
end;

procedure TTestRadar.TestSkipPrivateContacts;
begin
  var LEngine := TRadarEngine.Create;
  var LContact := Default(TContact);
  LContact.ContactId := 'c1';
  LContact.Privacy := psPrivate;

  var LMetric := Default(TInteractionMetric);
  LMetric.ContactId := 'c1';
  LMetric.LastInteractionAt := IncDay(Now, -45);
  LMetric.InboundCount := 20;
  LMetric.DataQuality := dqOK;

  var LHints := LEngine.Generate([LMetric], [LContact], nil);
  Assert.AreEqual<NativeInt>(0, Length(LHints), 'PRIVATE contacts should not generate hints');
end;

procedure TTestRadar.TestConfidenceCalculation;
begin
  var LEngine := TRadarEngine.Create;
  var LContact := Default(TContact);
  LContact.ContactId := 'c1';
  LContact.Privacy := psBusiness;

  var LMetric := Default(TInteractionMetric);
  LMetric.ContactId := 'c1';
  LMetric.LastInteractionAt := IncDay(Now, -60);
  LMetric.InboundCount := 20;
  LMetric.OutboundCount := 10;
  LMetric.DataQuality := dqOK;

  var LHints := LEngine.Generate([LMetric], [LContact], nil);
  Assert.IsTrue(Length(LHints) > 0);
  Assert.IsTrue(LHints[0].Confidence >= 0.1, 'Confidence should be at least 0.1');
  Assert.IsTrue(LHints[0].Confidence <= 1.0, 'Confidence should be at most 1.0');
  Assert.IsTrue(LHints[0].HintId <> '', 'Hint ID should not be empty');
end;

end.