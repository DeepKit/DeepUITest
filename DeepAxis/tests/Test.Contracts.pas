unit Test.Contracts;

interface

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts;

type
  [TestFixture]
  TTestContracts = class
  public
    [Test]
    procedure TestContactDefaults;
    [Test]
    procedure TestContactPrivacy;
    [Test]
    procedure TestMessageMetaCreateM0;
    [Test]
    procedure TestInteractionMetricIsValid;
    [Test]
    procedure TestBodyZeroReportIsClean;
    [Test]
    procedure TestGenerateId;
    [Test]
    procedure TestSHA256Hex;
    [Test]
    procedure TestDirectionToStr;
    [Test]
    procedure TestRadarHintTypeToChinese;
    [Test]
    procedure TestProfileIdentityToStr;
    [Test]
    procedure TestAxis1StateToChinese;
  end;

implementation

{ TTestContracts }

procedure TTestContracts.TestContactDefaults;
begin
  var LContact := Default(TContact);
  Assert.IsFalse(LContact.IsBusiness);
  Assert.IsTrue(LContact.IsUnknown);
  Assert.AreEqual('', LContact.DisplayNameHash);
  Assert.AreEqual(0, LContact.AdCount);
  Assert.AreEqual(0, LContact.ProductCount);
end;

procedure TTestContracts.TestContactPrivacy;
begin
  var LContact := Default(TContact);
  LContact.Privacy := psBusiness;
  Assert.IsTrue(LContact.IsBusiness);
  Assert.IsFalse(LContact.IsPrivate);
  Assert.IsFalse(LContact.IsUnknown);
  LContact.Privacy := psPrivate;
  Assert.IsTrue(LContact.IsPrivate);
  LContact.Privacy := psIdle;
  Assert.IsTrue(LContact.IsIdle);
end;

procedure TTestContracts.TestMessageMetaCreateM0;
begin
  var LMsg := TMessageMeta.CreateM0;
  Assert.IsTrue(LMsg.BodyQueried, 'BodyQueried must be True (user command override)');
  Assert.AreEqual(dUnknown, LMsg.Direction);
  Assert.AreEqual(nmtUnknown, LMsg.NormalizedType);
end;

procedure TTestContracts.TestInteractionMetricIsValid;
begin
  var LMetric := Default(TInteractionMetric);
  Assert.IsFalse(LMetric.IsValid);
  LMetric.MetricId := 'test-123';
  LMetric.DataQuality := dqOK;
  Assert.IsTrue(LMetric.IsValid);
end;

procedure TTestContracts.TestBodyZeroReportIsClean;
begin
  var LReport := TBodyZeroReport.CreateClean;
  Assert.IsTrue(LReport.IsClean);
  Assert.AreEqual(0, LReport.WriteAttempts);
  Assert.AreEqual(0, LReport.UiaCalls);
  Assert.IsFalse(LReport.BodyColumnsQueried);
end;

procedure TTestContracts.TestGenerateId;
begin
  var LId1 := GenerateId;
  var LId2 := GenerateId;
  Assert.IsTrue(Length(LId1) = 32);
  Assert.AreNotEqual(LId1, LId2);
end;

procedure TTestContracts.TestSHA256Hex;
begin
  var LHash := SHA256Hex('test');
  Assert.IsTrue(Length(LHash) = 64);
  Assert.AreEqual(LHash, SHA256Hex('test'), 'SHA256 must be deterministic');
end;

procedure TTestContracts.TestDirectionToStr;
begin
  Assert.AreEqual('inbound', DirectionToStr(dInbound));
  Assert.AreEqual('outbound', DirectionToStr(dOutbound));
  Assert.AreEqual('unknown', DirectionToStr(dUnknown));
end;

procedure TTestContracts.TestRadarHintTypeToChinese;
begin
  // 验证所有 5 种提示类型都有中文描述
  Assert.IsTrue(Length(RadarHintTypeToChinese(rhtCooling)) > 0);
  Assert.IsTrue(Length(RadarHintTypeToChinese(rhtLongSilence)) > 0);
  Assert.IsTrue(Length(RadarHintTypeToChinese(rhtReactivated)) > 0);
  Assert.IsTrue(Length(RadarHintTypeToChinese(rhtOutboundHeavy)) > 0);
  Assert.IsTrue(Length(RadarHintTypeToChinese(rhtDataInsufficient)) > 0);
end;

procedure TTestContracts.TestProfileIdentityToStr;
begin
  Assert.AreEqual('personal_full', ProfileIdentityToStr(piPersonalFull));
  Assert.AreEqual('external_safe', ProfileIdentityToStr(piExternalSafe));
  Assert.AreEqual('strict_compliance', ProfileIdentityToStr(piStrictCompliance));
end;

procedure TTestContracts.TestAxis1StateToChinese;
begin
  Assert.IsTrue(Length(Axis1StateToChinese(0)) > 0); // 关联未激活
  Assert.IsTrue(Length(Axis1StateToChinese(5)) > 0); // 首单
  Assert.IsTrue(Length(Axis1StateToChinese(8)) > 0); // 已流失
  Assert.IsTrue(Length(Axis1StateToChinese(9)) > 0); // 不适用
end;

end.