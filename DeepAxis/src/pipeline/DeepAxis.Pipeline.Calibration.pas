unit DeepAxis.Pipeline.Calibration;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.DateUtils,
  System.Math,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   校准数据点 — 记录一次判断的预测与实际结果
  /// </summary>
  TCalibrationPoint = record
    PointId: string;
    RuleName: string;       // 被校准的规则名
    PredictedValue: Double; // 预测值
    ActualValue: Double;    // 实际值
    Deviation: Double;      // 偏差 = 实际 - 预测
    Timestamp: TDateTime;
  end;

  /// <summary>
  ///   校准引擎。N≥30 次同类判决后自动校准阈值。
  ///   校准对象: 感知规则阈值、G/U/L 参数、红黄绿边界、规则准确率。
  /// </summary>
  TCalibrationEngine = class
  private
    FPoints: TDictionary<string, TList<TCalibrationPoint>>;
    FMinSamples: Integer;
    procedure AutoCalibrateRule(const ARuleName: string;
      const APoints: TList<TCalibrationPoint>);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>记录一个校准数据点</summary>
    procedure RecordPoint(const ARuleName: string;
      APredictedValue, AActualValue: Double);

    /// <summary>触发校准（所有规则的数据点 ≥ N 时）</summary>
    procedure TriggerCalibration;

    /// <summary>获取规则的统计信息</summary>
    function GetRuleStats(const ARuleName: string): string;

    /// <summary>获取规则准确率</summary>
    function GetRuleAccuracy(const ARuleName: string): Double;

    /// <summary>获取所有规则的状态</summary>
    function GetAllRuleStatus: string;
  end;

implementation

{ TCalibrationEngine }

constructor TCalibrationEngine.Create;
begin
  inherited Create;
  FPoints := TObjectDictionary<string, TList<TCalibrationPoint>>.Create([doOwnsValues]);
  FMinSamples := 30;
end;

destructor TCalibrationEngine.Destroy;
begin
  FPoints.Free;
  inherited;
end;

procedure TCalibrationEngine.RecordPoint(const ARuleName: string;
  APredictedValue, AActualValue: Double);
var
  LPoint: TCalibrationPoint;
  LList: TList<TCalibrationPoint>;
begin
  if not FPoints.TryGetValue(ARuleName, LList) then
  begin
    LList := TList<TCalibrationPoint>.Create;
    FPoints.Add(ARuleName, LList);
  end;

  LPoint.PointId := GenerateId;
  LPoint.RuleName := ARuleName;
  LPoint.PredictedValue := APredictedValue;
  LPoint.ActualValue := AActualValue;
  LPoint.Deviation := AActualValue - APredictedValue;
  LPoint.Timestamp := Now;

  LList.Add(LPoint);
end;

procedure TCalibrationEngine.AutoCalibrateRule(const ARuleName: string;
  const APoints: TList<TCalibrationPoint>);
var
  LSumDeviation: Double;
  LPoint: TCalibrationPoint;
  LMeanDeviation: Double;
  LAccuracy: Double;
  LCorrectCount: Integer;
  LStatus: string;
begin
  if APoints.Count < FMinSamples then Exit;

  LSumDeviation := 0;
  LCorrectCount := 0;
  for LPoint in APoints do
  begin
    LSumDeviation := LSumDeviation + LPoint.Deviation;
    if Abs(LPoint.Deviation) < 0.2 then
      Inc(LCorrectCount);
  end;

  LMeanDeviation := LSumDeviation / APoints.Count;
  LAccuracy := LCorrectCount / APoints.Count;

  // 判断规则状态
  if LAccuracy >= 0.9 then
    LStatus := '工程层 — 成熟规则'
  else if LAccuracy >= 0.7 then
    LStatus := '行动层 — 已验证'
  else if LAccuracy >= 0.5 then
    LStatus := '思维层 — 初步判断'
  else
    LStatus := '待废弃 — 准确率过低';

  // 校准动作
  if Abs(LMeanDeviation) > 0.3 then
    LStatus := LStatus + Format(' [偏差: %.1f%%, 建议调整阈值]', [LMeanDeviation * 100]);
end;

procedure TCalibrationEngine.TriggerCalibration;
var
  LPair: TPair<string, TList<TCalibrationPoint>>;
begin
  for LPair in FPoints do
    AutoCalibrateRule(LPair.Key, LPair.Value);
end;

function TCalibrationEngine.GetRuleStats(const ARuleName: string): string;
var
  LList: TList<TCalibrationPoint>;
  LPoint: TCalibrationPoint;
  LSumDeviation: Double;
  LCorrectCount: Integer;
begin
  if not FPoints.TryGetValue(ARuleName, LList) then
  begin
    Result := Format('%s: 无数据', [ARuleName]);
    Exit;
  end;

  LSumDeviation := 0;
  LCorrectCount := 0;
  for LPoint in LList do
  begin
    LSumDeviation := LSumDeviation + LPoint.Deviation;
    if Abs(LPoint.Deviation) < 0.2 then
      Inc(LCorrectCount);
  end;

  Result := Format('%s: %d 样本, 准确率 %.1f%%, 平均偏差 %.2f',
    [ARuleName, LList.Count, (LCorrectCount / LList.Count) * 100,
     LSumDeviation / LList.Count]);
end;

function TCalibrationEngine.GetRuleAccuracy(const ARuleName: string): Double;
var
  LList: TList<TCalibrationPoint>;
  LPoint: TCalibrationPoint;
  LCorrectCount: Integer;
begin
  Result := 0;
  if not FPoints.TryGetValue(ARuleName, LList) then Exit;
  if LList.Count = 0 then Exit;

  LCorrectCount := 0;
  for LPoint in LList do
    if Abs(LPoint.Deviation) < 0.2 then
      Inc(LCorrectCount);

  Result := LCorrectCount / LList.Count;
end;

function TCalibrationEngine.GetAllRuleStatus: string;
var
  LPair: TPair<string, TList<TCalibrationPoint>>;
begin
  Result := '';
  for LPair in FPoints do
    Result := Result + GetRuleStats(LPair.Key) + #13#10;
  if Result = '' then
    Result := '无校准数据';
end;

end.