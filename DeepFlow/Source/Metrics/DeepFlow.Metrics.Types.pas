{******************************************************************************}
{                                                                              }
{  UniFlow Metrics Types                                                       }
{  Prometheus-style metrics type definitions                                   }
{                                                                              }
{  Features:                                                                   }
{  - Counter, Gauge, Histogram, Summary metrics                                }
{  - Label support for multi-dimensional metrics                               }
{  - Thread-safe metric operations                                             }
{  - JSON/Prometheus text format export                                        }
{                                                                              }
{******************************************************************************}

unit UniFlow.Metrics.Types;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  System.Math,
  DeepBase.Exceptions;

type
  //----------------------------------------------------------------------------
  // Metric types
  //----------------------------------------------------------------------------

  TMetricType = (
    mtCounter,    // Monotonically increasing counter
    mtGauge,      // Value that can go up and down
    mtHistogram,  // Distribution of values in buckets
    mtSummary     // Quantile summary
  );

  TMetricTypeHelper = record helper for TMetricType
    function ToString: string;
    class function FromString(const AValue: string): TMetricType; static;
  end;

  //----------------------------------------------------------------------------
  // TMetricLabels - Label key-value pairs
  //----------------------------------------------------------------------------

  TMetricLabels = class
  private
    FLabels: TDictionary<string, string>;
    FHash: string;
    procedure UpdateHash;
  public
    constructor Create; overload;
    constructor Create(const ALabels: array of string); overload;
    destructor Destroy; override;

    function Clone: TMetricLabels;
    function Add(const AName, AValue: string): TMetricLabels;
    function Get(const AName: string): string;
    function Has(const AName: string): Boolean;
    function Count: Integer;
    function IsEmpty: Boolean;

    function ToPrometheusString: string;
    function ToJSON: TJSONObject;

    property Hash: string read FHash;
    property Labels: TDictionary<string, string> read FLabels;
  end;

  //----------------------------------------------------------------------------
  // TMetricValue - Base metric value
  //----------------------------------------------------------------------------

  TMetricValue = class
  private
    FLabels: TMetricLabels;
    FTimestamp: TDateTime;
  public
    constructor Create(ALabels: TMetricLabels);
    destructor Destroy; override;

    property Labels: TMetricLabels read FLabels;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  //----------------------------------------------------------------------------
  // TCounterValue - Counter metric value
  //----------------------------------------------------------------------------

  TCounterValue = class(TMetricValue)
  private
    FValue: Double;
  public
    constructor Create(ALabels: TMetricLabels);

    procedure Inc(AAmount: Double = 1.0);
    procedure Reset;

    property Value: Double read FValue;
  end;

  //----------------------------------------------------------------------------
  // TGaugeValue - Gauge metric value
  //----------------------------------------------------------------------------

  TGaugeValue = class(TMetricValue)
  private
    FValue: Double;
  public
    constructor Create(ALabels: TMetricLabels);

    procedure Set_(AValue: Double);
    procedure Inc(AAmount: Double = 1.0);
    procedure Dec(AAmount: Double = 1.0);
    procedure SetToCurrentTime;

    property Value: Double read FValue;
  end;

  //----------------------------------------------------------------------------
  // THistogramBucket - Single histogram bucket
  //----------------------------------------------------------------------------

  THistogramBucket = record
    UpperBound: Double;
    Count: Int64;
  end;

  //----------------------------------------------------------------------------
  // THistogramValue - Histogram metric value
  //----------------------------------------------------------------------------

  THistogramValue = class(TMetricValue)
  private
    FBuckets: TArray<THistogramBucket>;
    FSum: Double;
    FCount: Int64;
  public
    constructor Create(ALabels: TMetricLabels; const ABuckets: TArray<Double>);

    procedure Observe(AValue: Double);
    procedure Reset;

    function GetBucketCount(AIndex: Integer): Int64;
    function GetBucketBound(AIndex: Integer): Double;
    function BucketCount: Integer;

    property Sum: Double read FSum;
    property Count: Int64 read FCount;
    property Buckets: TArray<THistogramBucket> read FBuckets;
  end;

  //----------------------------------------------------------------------------
  // TSummaryValue - Summary metric value (quantiles)
  //----------------------------------------------------------------------------

  TSummaryQuantile = record
    Quantile: Double;
    Value: Double;
  end;

  TSummaryValue = class(TMetricValue)
  private
    FValues: TList<Double>;
    FQuantiles: TArray<Double>;
    FMaxAge: Integer;       // Max age in seconds
    FMaxSize: Integer;      // Max number of observations
    FSum: Double;
    FCount: Int64;
    FLastCalculation: TDateTime;
    FCalculatedQuantiles: TArray<TSummaryQuantile>;

    procedure Compact;
    procedure CalculateQuantiles;
  public
    constructor Create(ALabels: TMetricLabels; const AQuantiles: TArray<Double>;
      AMaxAge: Integer = 600; AMaxSize: Integer = 1000);
    destructor Destroy; override;

    procedure Observe(AValue: Double);
    procedure Reset;

    function GetQuantile(AQuantile: Double): Double;

    property Sum: Double read FSum;
    property Count: Int64 read FCount;
    property Quantiles: TArray<TSummaryQuantile> read FCalculatedQuantiles;
  end;

  //----------------------------------------------------------------------------
  // TMetricFamily - Collection of metrics with same name
  //----------------------------------------------------------------------------

  TMetricFamily = class
  private
    FName: string;
    FHelp: string;
    FType: TMetricType;
    FValues: TObjectDictionary<string, TMetricValue>;
    FLock: TCriticalSection;
    FBuckets: TArray<Double>;      // For histograms
    FQuantiles: TArray<Double>;    // For summaries
  public
    constructor Create(const AName, AHelp: string; AType: TMetricType);
    destructor Destroy; override;

    // Configuration
    procedure SetBuckets(const ABuckets: TArray<Double>);
    procedure SetQuantiles(const AQuantiles: TArray<Double>);

    // Get or create metric value
    function GetCounter(ALabels: TMetricLabels = nil): TCounterValue;
    function GetGauge(ALabels: TMetricLabels = nil): TGaugeValue;
    function GetHistogram(ALabels: TMetricLabels = nil): THistogramValue;
    function GetSummary(ALabels: TMetricLabels = nil): TSummaryValue;

    // Export
    function ToPrometheusText: string;
    function ToJSON: TJSONObject;

    // Cleanup
    procedure Clear;
    function ValueCount: Integer;

    property Name: string read FName;
    property Help: string read FHelp;
    property MetricType: TMetricType read FType;
  end;

  //----------------------------------------------------------------------------
  // Predefined bucket sets
  //----------------------------------------------------------------------------

  TDefaultBuckets = class
  public
    class function Linear(AStart, AWidth: Double; ACount: Integer): TArray<Double>; static;
    class function Exponential(AStart, AFactor: Double; ACount: Integer): TArray<Double>; static;
    class function Default: TArray<Double>; static;
    class function HTTPDuration: TArray<Double>; static;
    class function LLMDuration: TArray<Double>; static;
    class function TokenCount: TArray<Double>; static;
  end;

  //----------------------------------------------------------------------------
  // Predefined quantile sets
  //----------------------------------------------------------------------------

  TDefaultQuantiles = class
  public
    class function Default: TArray<Double>; static;
    class function Detailed: TArray<Double>; static;
  end;

  //----------------------------------------------------------------------------
  // TMetricSnapshot - Point-in-time metric snapshot
  //----------------------------------------------------------------------------

  TMetricSnapshot = class
  private
    FName: string;
    FHelp: string;
    FType: TMetricType;
    FTimestamp: TDateTime;
    FValues: TList<TPair<TMetricLabels, Double>>;
    FBuckets: TList<TPair<TMetricLabels, TArray<THistogramBucket>>>;
    FQuantiles: TList<TPair<TMetricLabels, TArray<TSummaryQuantile>>>;
    FSums: TList<TPair<TMetricLabels, Double>>;
    FCounts: TList<TPair<TMetricLabels, Int64>>;
  public
    constructor Create(const AName, AHelp: string; AType: TMetricType);
    destructor Destroy; override;

    procedure AddValue(ALabels: TMetricLabels; AValue: Double);
    procedure AddHistogram(ALabels: TMetricLabels; const ABuckets: TArray<THistogramBucket>;
      ASum: Double; ACount: Int64);
    procedure AddSummary(ALabels: TMetricLabels; const AQuantiles: TArray<TSummaryQuantile>;
      ASum: Double; ACount: Int64);

    function ToPrometheusText: string;
    function ToJSON: TJSONObject;

    property Name: string read FName;
    property Help: string read FHelp;
    property MetricType: TMetricType read FType;
    property Timestamp: TDateTime read FTimestamp;
  end;

implementation

uses
  System.DateUtils;

//------------------------------------------------------------------------------
// TMetricTypeHelper
//------------------------------------------------------------------------------

function TMetricTypeHelper.ToString: string;
begin
  case Self of
    mtCounter:   Result := 'counter';
    mtGauge:     Result := 'gauge';
    mtHistogram: Result := 'histogram';
    mtSummary:   Result := 'summary';
  else
    Result := 'unknown';
  end;
end;

class function TMetricTypeHelper.FromString(const AValue: string): TMetricType;
var
  LValue: string;
begin
  LValue := LowerCase(AValue);
  if LValue = 'counter' then
    Result := mtCounter
  else if LValue = 'gauge' then
    Result := mtGauge
  else if LValue = 'histogram' then
    Result := mtHistogram
  else if LValue = 'summary' then
    Result := mtSummary
  else
    Result := mtGauge;
end;

//------------------------------------------------------------------------------
// TMetricLabels
//------------------------------------------------------------------------------

constructor TMetricLabels.Create;
begin
  inherited Create;
  FLabels := TDictionary<string, string>.Create;
  FHash := '';
end;

constructor TMetricLabels.Create(const ALabels: array of string);
var
  I: Integer;
begin
  Create;
  I := 0;
  while I < Length(ALabels) - 1 do
  begin
    FLabels.AddOrSetValue(ALabels[I], ALabels[I + 1]);
    Inc(I, 2);
  end;
  UpdateHash;
end;

destructor TMetricLabels.Destroy;
begin
  FLabels.Free;
  inherited Destroy;
end;

procedure TMetricLabels.UpdateHash;
var
  Keys: TArray<string>;
  SB: TStringBuilder;
  Key: string;
begin
  Keys := FLabels.Keys.ToArray;
  TArray.Sort<string>(Keys);

  SB := TStringBuilder.Create;
  try
    for Key in Keys do
    begin
      if SB.Length > 0 then
        SB.Append(',');
      SB.Append(Key).Append('=').Append(FLabels[Key]);
    end;
    FHash := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMetricLabels.Clone: TMetricLabels;
var
  Pair: TPair<string, string>;
begin
  Result := TMetricLabels.Create;
  for Pair in FLabels do
    Result.FLabels.Add(Pair.Key, Pair.Value);
  Result.FHash := FHash;
end;

function TMetricLabels.Add(const AName, AValue: string): TMetricLabels;
begin
  FLabels.AddOrSetValue(AName, AValue);
  UpdateHash;
  Result := Self;
end;

function TMetricLabels.Get(const AName: string): string;
begin
  if not FLabels.TryGetValue(AName, Result) then
    Result := '';
end;

function TMetricLabels.Has(const AName: string): Boolean;
begin
  Result := FLabels.ContainsKey(AName);
end;

function TMetricLabels.Count: Integer;
begin
  Result := FLabels.Count;
end;

function TMetricLabels.IsEmpty: Boolean;
begin
  Result := FLabels.Count = 0;
end;

function TMetricLabels.ToPrometheusString: string;
var
  Keys: TArray<string>;
  SB: TStringBuilder;
  Key: string;
  I: Integer;
begin
  if FLabels.Count = 0 then
    Exit('');

  Keys := FLabels.Keys.ToArray;
  TArray.Sort<string>(Keys);

  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    for I := 0 to Length(Keys) - 1 do
    begin
      if I > 0 then
        SB.Append(',');
      Key := Keys[I];
      SB.Append(Key).Append('="');
      SB.Append(StringReplace(FLabels[Key], '"', '\"', [rfReplaceAll]));
      SB.Append('"');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMetricLabels.ToJSON: TJSONObject;
var
  Pair: TPair<string, string>;
begin
  Result := TJSONObject.Create;
  for Pair in FLabels do
    Result.AddPair(Pair.Key, Pair.Value);
end;

//------------------------------------------------------------------------------
// TMetricValue
//------------------------------------------------------------------------------

constructor TMetricValue.Create(ALabels: TMetricLabels);
begin
  inherited Create;
  if ALabels <> nil then
    FLabels := ALabels.Clone
  else
    FLabels := TMetricLabels.Create;
  FTimestamp := Now;
end;

destructor TMetricValue.Destroy;
begin
  FLabels.Free;
  inherited Destroy;
end;

//------------------------------------------------------------------------------
// TCounterValue
//------------------------------------------------------------------------------

constructor TCounterValue.Create(ALabels: TMetricLabels);
begin
  inherited Create(ALabels);
  FValue := 0;
end;

procedure TCounterValue.Inc(AAmount: Double);
begin
  if AAmount < 0 then
    raise EOperationException.Create('Counter can only be incremented with positive values');
  FValue := FValue + AAmount;
  FTimestamp := Now;
end;

procedure TCounterValue.Reset;
begin
  FValue := 0;
  FTimestamp := Now;
end;

//------------------------------------------------------------------------------
// TGaugeValue
//------------------------------------------------------------------------------

constructor TGaugeValue.Create(ALabels: TMetricLabels);
begin
  inherited Create(ALabels);
  FValue := 0;
end;

procedure TGaugeValue.Set_(AValue: Double);
begin
  FValue := AValue;
  FTimestamp := Now;
end;

procedure TGaugeValue.Inc(AAmount: Double);
begin
  FValue := FValue + AAmount;
  FTimestamp := Now;
end;

procedure TGaugeValue.Dec(AAmount: Double);
begin
  FValue := FValue - AAmount;
  FTimestamp := Now;
end;

procedure TGaugeValue.SetToCurrentTime;
begin
  FValue := DateTimeToUnix(Now, False);
  FTimestamp := Now;
end;

//------------------------------------------------------------------------------
// THistogramValue
//------------------------------------------------------------------------------

constructor THistogramValue.Create(ALabels: TMetricLabels; const ABuckets: TArray<Double>);
var
  I: Integer;
  SortedBuckets: TArray<Double>;
begin
  inherited Create(ALabels);

  // Sort buckets
  SortedBuckets := Copy(ABuckets);
  TArray.Sort<Double>(SortedBuckets);

  // Initialize buckets
  SetLength(FBuckets, Length(SortedBuckets));
  for I := 0 to Length(SortedBuckets) - 1 do
  begin
    FBuckets[I].UpperBound := SortedBuckets[I];
    FBuckets[I].Count := 0;
  end;

  FSum := 0;
  FCount := 0;
end;

procedure THistogramValue.Observe(AValue: Double);
var
  I: Integer;
begin
  FSum := FSum + AValue;
  Inc(FCount);

  // Increment all buckets where value <= upper bound
  for I := 0 to Length(FBuckets) - 1 do
  begin
    if AValue <= FBuckets[I].UpperBound then
      Inc(FBuckets[I].Count);
  end;

  FTimestamp := Now;
end;

procedure THistogramValue.Reset;
var
  I: Integer;
begin
  FSum := 0;
  FCount := 0;
  for I := 0 to Length(FBuckets) - 1 do
    FBuckets[I].Count := 0;
  FTimestamp := Now;
end;

function THistogramValue.GetBucketCount(AIndex: Integer): Int64;
begin
  if (AIndex >= 0) and (AIndex < Length(FBuckets)) then
    Result := FBuckets[AIndex].Count
  else
    Result := 0;
end;

function THistogramValue.GetBucketBound(AIndex: Integer): Double;
begin
  if (AIndex >= 0) and (AIndex < Length(FBuckets)) then
    Result := FBuckets[AIndex].UpperBound
  else
    Result := 0;
end;

function THistogramValue.BucketCount: Integer;
begin
  Result := Length(FBuckets);
end;

//------------------------------------------------------------------------------
// TSummaryValue
//------------------------------------------------------------------------------

constructor TSummaryValue.Create(ALabels: TMetricLabels; const AQuantiles: TArray<Double>;
  AMaxAge: Integer; AMaxSize: Integer);
begin
  inherited Create(ALabels);
  FValues := TList<Double>.Create;
  FQuantiles := Copy(AQuantiles);
  TArray.Sort<Double>(FQuantiles);
  FMaxAge := AMaxAge;
  FMaxSize := AMaxSize;
  FSum := 0;
  FCount := 0;
  FLastCalculation := 0;
  SetLength(FCalculatedQuantiles, Length(FQuantiles));
end;

destructor TSummaryValue.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

procedure TSummaryValue.Observe(AValue: Double);
begin
  FValues.Add(AValue);
  FSum := FSum + AValue;
  Inc(FCount);
  FTimestamp := Now;

  // Compact if necessary
  if FValues.Count > FMaxSize then
    Compact;
end;

procedure TSummaryValue.Compact;
begin
  // Simple compaction: keep last FMaxSize/2 values
  while FValues.Count > FMaxSize div 2 do
    FValues.Delete(0);
end;

procedure TSummaryValue.CalculateQuantiles;
var
  SortedValues: TArray<Double>;
  I, Idx: Integer;
begin
  if FValues.Count = 0 then
  begin
    for I := 0 to Length(FCalculatedQuantiles) - 1 do
    begin
      FCalculatedQuantiles[I].Quantile := FQuantiles[I];
      FCalculatedQuantiles[I].Value := 0;
    end;
    Exit;
  end;

  SortedValues := FValues.ToArray;
  TArray.Sort<Double>(SortedValues);

  for I := 0 to Length(FQuantiles) - 1 do
  begin
    Idx := Trunc(FQuantiles[I] * (Length(SortedValues) - 1));
    FCalculatedQuantiles[I].Quantile := FQuantiles[I];
    FCalculatedQuantiles[I].Value := SortedValues[Idx];
  end;

  FLastCalculation := Now;
end;

function TSummaryValue.GetQuantile(AQuantile: Double): Double;
var
  I: Integer;
begin
  // Recalculate if stale (> 10 seconds)
  if SecondsBetween(Now, FLastCalculation) > 10 then
    CalculateQuantiles;

  for I := 0 to Length(FCalculatedQuantiles) - 1 do
  begin
    if Abs(FCalculatedQuantiles[I].Quantile - AQuantile) < 0.001 then
      Exit(FCalculatedQuantiles[I].Value);
  end;

  Result := 0;
end;

procedure TSummaryValue.Reset;
begin
  FValues.Clear;
  FSum := 0;
  FCount := 0;
  FLastCalculation := 0;
  FTimestamp := Now;
end;

//------------------------------------------------------------------------------
// TMetricFamily
//------------------------------------------------------------------------------

constructor TMetricFamily.Create(const AName, AHelp: string; AType: TMetricType);
begin
  inherited Create;
  FName := AName;
  FHelp := AHelp;
  FType := AType;
  FValues := TObjectDictionary<string, TMetricValue>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FBuckets := TDefaultBuckets.Default;
  FQuantiles := TDefaultQuantiles.Default;
end;

destructor TMetricFamily.Destroy;
begin
  FValues.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMetricFamily.SetBuckets(const ABuckets: TArray<Double>);
begin
  FBuckets := Copy(ABuckets);
end;

procedure TMetricFamily.SetQuantiles(const AQuantiles: TArray<Double>);
begin
  FQuantiles := Copy(AQuantiles);
end;

function TMetricFamily.GetCounter(ALabels: TMetricLabels): TCounterValue;
var
  Hash: string;
  Value: TMetricValue;
begin
  if FType <> mtCounter then
    raise EOperationException.CreateFmt('Metric %s is not a counter', [FName]);

  if ALabels <> nil then
    Hash := ALabels.Hash
  else
    Hash := '';

  FLock.Enter;
  try
    if FValues.TryGetValue(Hash, Value) then
      Result := TCounterValue(Value)
    else
    begin
      Result := TCounterValue.Create(ALabels);
      FValues.Add(Hash, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricFamily.GetGauge(ALabels: TMetricLabels): TGaugeValue;
var
  Hash: string;
  Value: TMetricValue;
begin
  if FType <> mtGauge then
    raise EOperationException.CreateFmt('Metric %s is not a gauge', [FName]);

  if ALabels <> nil then
    Hash := ALabels.Hash
  else
    Hash := '';

  FLock.Enter;
  try
    if FValues.TryGetValue(Hash, Value) then
      Result := TGaugeValue(Value)
    else
    begin
      Result := TGaugeValue.Create(ALabels);
      FValues.Add(Hash, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricFamily.GetHistogram(ALabels: TMetricLabels): THistogramValue;
var
  Hash: string;
  Value: TMetricValue;
begin
  if FType <> mtHistogram then
    raise EOperationException.CreateFmt('Metric %s is not a histogram', [FName]);

  if ALabels <> nil then
    Hash := ALabels.Hash
  else
    Hash := '';

  FLock.Enter;
  try
    if FValues.TryGetValue(Hash, Value) then
      Result := THistogramValue(Value)
    else
    begin
      Result := THistogramValue.Create(ALabels, FBuckets);
      FValues.Add(Hash, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricFamily.GetSummary(ALabels: TMetricLabels): TSummaryValue;
var
  Hash: string;
  Value: TMetricValue;
begin
  if FType <> mtSummary then
    raise EOperationException.CreateFmt('Metric %s is not a summary', [FName]);

  if ALabels <> nil then
    Hash := ALabels.Hash
  else
    Hash := '';

  FLock.Enter;
  try
    if FValues.TryGetValue(Hash, Value) then
      Result := TSummaryValue(Value)
    else
    begin
      Result := TSummaryValue.Create(ALabels, FQuantiles);
      FValues.Add(Hash, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricFamily.ToPrometheusText: string;
var
  SB: TStringBuilder;
  Pair: TPair<string, TMetricValue>;
  Counter: TCounterValue;
  Gauge: TGaugeValue;
  Histogram: THistogramValue;
  Summary: TSummaryValue;
  I: Integer;
  Labels: string;
  CumulativeCount: Int64;
begin
  SB := TStringBuilder.Create;
  try
    // HELP line
    SB.Append('# HELP ').Append(FName).Append(' ').AppendLine(FHelp);
    // TYPE line
    SB.Append('# TYPE ').Append(FName).Append(' ').AppendLine(FType.ToString);

    FLock.Enter;
    try
      for Pair in FValues do
      begin
        Labels := Pair.Value.Labels.ToPrometheusString;

        case FType of
          mtCounter:
          begin
            Counter := TCounterValue(Pair.Value);
            SB.Append(FName).Append(Labels).Append(' ');
            SB.AppendLine(FormatFloat('0.######', Counter.Value));
          end;

          mtGauge:
          begin
            Gauge := TGaugeValue(Pair.Value);
            SB.Append(FName).Append(Labels).Append(' ');
            SB.AppendLine(FormatFloat('0.######', Gauge.Value));
          end;

          mtHistogram:
          begin
            Histogram := THistogramValue(Pair.Value);
            CumulativeCount := 0;
            for I := 0 to Histogram.BucketCount - 1 do
            begin
              CumulativeCount := Histogram.Buckets[I].Count;
              if Labels <> '' then
                SB.Append(FName).Append('_bucket{le="')
                  .Append(FormatFloat('0.######', Histogram.Buckets[I].UpperBound))
                  .Append('",').Append(Copy(Labels, 2, Length(Labels) - 2)).Append('}')
              else
                SB.Append(FName).Append('_bucket{le="')
                  .Append(FormatFloat('0.######', Histogram.Buckets[I].UpperBound))
                  .Append('"}');
              SB.Append(' ').AppendLine(IntToStr(CumulativeCount));
            end;
            // +Inf bucket
            if Labels <> '' then
              SB.Append(FName).Append('_bucket{le="+Inf",')
                .Append(Copy(Labels, 2, Length(Labels) - 2)).Append('}')
            else
              SB.Append(FName).Append('_bucket{le="+Inf"}');
            SB.Append(' ').AppendLine(IntToStr(Histogram.Count));
            // Sum and count
            SB.Append(FName).Append('_sum').Append(Labels).Append(' ');
            SB.AppendLine(FormatFloat('0.######', Histogram.Sum));
            SB.Append(FName).Append('_count').Append(Labels).Append(' ');
            SB.AppendLine(IntToStr(Histogram.Count));
          end;

          mtSummary:
          begin
            Summary := TSummaryValue(Pair.Value);
            Summary.CalculateQuantiles;
            for I := 0 to Length(Summary.Quantiles) - 1 do
            begin
              if Labels <> '' then
                SB.Append(FName).Append('{quantile="')
                  .Append(FormatFloat('0.##', Summary.Quantiles[I].Quantile))
                  .Append('",').Append(Copy(Labels, 2, Length(Labels) - 2)).Append('}')
              else
                SB.Append(FName).Append('{quantile="')
                  .Append(FormatFloat('0.##', Summary.Quantiles[I].Quantile))
                  .Append('"}');
              SB.Append(' ').AppendLine(FormatFloat('0.######', Summary.Quantiles[I].Value));
            end;
            // Sum and count
            SB.Append(FName).Append('_sum').Append(Labels).Append(' ');
            SB.AppendLine(FormatFloat('0.######', Summary.Sum));
            SB.Append(FName).Append('_count').Append(Labels).Append(' ');
            SB.AppendLine(IntToStr(Summary.Count));
          end;
        end;
      end;
    finally
      FLock.Leave;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMetricFamily.ToJSON: TJSONObject;
var
  ValuesArray: TJSONArray;
  Pair: TPair<string, TMetricValue>;
  ValueObj: TJSONObject;
  Counter: TCounterValue;
  Gauge: TGaugeValue;
  Histogram: THistogramValue;
  Summary: TSummaryValue;
  BucketsArray, QuantilesArray: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('help', FHelp);
  Result.AddPair('type', FType.ToString);

  ValuesArray := TJSONArray.Create;
  FLock.Enter;
  try
    for Pair in FValues do
    begin
      ValueObj := TJSONObject.Create;
      ValueObj.AddPair('labels', Pair.Value.Labels.ToJSON);

      case FType of
        mtCounter:
        begin
          Counter := TCounterValue(Pair.Value);
          ValueObj.AddPair('value', TJSONNumber.Create(Counter.Value));
        end;

        mtGauge:
        begin
          Gauge := TGaugeValue(Pair.Value);
          ValueObj.AddPair('value', TJSONNumber.Create(Gauge.Value));
        end;

        mtHistogram:
        begin
          Histogram := THistogramValue(Pair.Value);
          BucketsArray := TJSONArray.Create;
          for I := 0 to Histogram.BucketCount - 1 do
          begin
            BucketsArray.Add(TJSONObject.Create
              .AddPair('le', TJSONNumber.Create(Histogram.Buckets[I].UpperBound))
              .AddPair('count', TJSONNumber.Create(Histogram.Buckets[I].Count)));
          end;
          ValueObj.AddPair('buckets', BucketsArray);
          ValueObj.AddPair('sum', TJSONNumber.Create(Histogram.Sum));
          ValueObj.AddPair('count', TJSONNumber.Create(Histogram.Count));
        end;

        mtSummary:
        begin
          Summary := TSummaryValue(Pair.Value);
          Summary.CalculateQuantiles;
          QuantilesArray := TJSONArray.Create;
          for I := 0 to Length(Summary.Quantiles) - 1 do
          begin
            QuantilesArray.Add(TJSONObject.Create
              .AddPair('quantile', TJSONNumber.Create(Summary.Quantiles[I].Quantile))
              .AddPair('value', TJSONNumber.Create(Summary.Quantiles[I].Value)));
          end;
          ValueObj.AddPair('quantiles', QuantilesArray);
          ValueObj.AddPair('sum', TJSONNumber.Create(Summary.Sum));
          ValueObj.AddPair('count', TJSONNumber.Create(Summary.Count));
        end;
      end;

      ValuesArray.Add(ValueObj);
    end;
  finally
    FLock.Leave;
  end;

  Result.AddPair('values', ValuesArray);
end;

procedure TMetricFamily.Clear;
begin
  FLock.Enter;
  try
    FValues.Clear;
  finally
    FLock.Leave;
  end;
end;

function TMetricFamily.ValueCount: Integer;
begin
  FLock.Enter;
  try
    Result := FValues.Count;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TDefaultBuckets
//------------------------------------------------------------------------------

class function TDefaultBuckets.Linear(AStart, AWidth: Double; ACount: Integer): TArray<Double>;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I] := AStart + (AWidth * I);
end;

class function TDefaultBuckets.Exponential(AStart, AFactor: Double; ACount: Integer): TArray<Double>;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  Result[0] := AStart;
  for I := 1 to ACount - 1 do
    Result[I] := Result[I - 1] * AFactor;
end;

class function TDefaultBuckets.Default: TArray<Double>;
begin
  Result := TArray<Double>.Create(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10);
end;

class function TDefaultBuckets.HTTPDuration: TArray<Double>;
begin
  // Milliseconds: 10ms to 30s
  Result := TArray<Double>.Create(10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000);
end;

class function TDefaultBuckets.LLMDuration: TArray<Double>;
begin
  // Milliseconds: 100ms to 120s (LLM can be slow)
  Result := TArray<Double>.Create(100, 250, 500, 1000, 2500, 5000, 10000, 30000, 60000, 120000);
end;

class function TDefaultBuckets.TokenCount: TArray<Double>;
begin
  // Token counts: 10 to 100000
  Result := TArray<Double>.Create(10, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 50000, 100000);
end;

//------------------------------------------------------------------------------
// TDefaultQuantiles
//------------------------------------------------------------------------------

class function TDefaultQuantiles.Default: TArray<Double>;
begin
  Result := TArray<Double>.Create(0.5, 0.9, 0.99);
end;

class function TDefaultQuantiles.Detailed: TArray<Double>;
begin
  Result := TArray<Double>.Create(0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99);
end;

//------------------------------------------------------------------------------
// TMetricSnapshot
//------------------------------------------------------------------------------

constructor TMetricSnapshot.Create(const AName, AHelp: string; AType: TMetricType);
begin
  inherited Create;
  FName := AName;
  FHelp := AHelp;
  FType := AType;
  FTimestamp := Now;
  FValues := TList<TPair<TMetricLabels, Double>>.Create;
  FBuckets := TList<TPair<TMetricLabels, TArray<THistogramBucket>>>.Create;
  FQuantiles := TList<TPair<TMetricLabels, TArray<TSummaryQuantile>>>.Create;
  FSums := TList<TPair<TMetricLabels, Double>>.Create;
  FCounts := TList<TPair<TMetricLabels, Int64>>.Create;
end;

destructor TMetricSnapshot.Destroy;
var
  I: Integer;
begin
  for I := 0 to FValues.Count - 1 do
    FValues[I].Key.Free;
  FValues.Free;
  for I := 0 to FBuckets.Count - 1 do
    FBuckets[I].Key.Free;
  FBuckets.Free;
  for I := 0 to FQuantiles.Count - 1 do
    FQuantiles[I].Key.Free;
  FQuantiles.Free;
  for I := 0 to FSums.Count - 1 do
    FSums[I].Key.Free;
  FSums.Free;
  for I := 0 to FCounts.Count - 1 do
    FCounts[I].Key.Free;
  FCounts.Free;
  inherited Destroy;
end;

procedure TMetricSnapshot.AddValue(ALabels: TMetricLabels; AValue: Double);
begin
  FValues.Add(TPair<TMetricLabels, Double>.Create(ALabels.Clone, AValue));
end;

procedure TMetricSnapshot.AddHistogram(ALabels: TMetricLabels;
  const ABuckets: TArray<THistogramBucket>; ASum: Double; ACount: Int64);
begin
  FBuckets.Add(TPair<TMetricLabels, TArray<THistogramBucket>>.Create(ALabels.Clone, ABuckets));
  FSums.Add(TPair<TMetricLabels, Double>.Create(ALabels.Clone, ASum));
  FCounts.Add(TPair<TMetricLabels, Int64>.Create(ALabels.Clone, ACount));
end;

procedure TMetricSnapshot.AddSummary(ALabels: TMetricLabels;
  const AQuantiles: TArray<TSummaryQuantile>; ASum: Double; ACount: Int64);
begin
  FQuantiles.Add(TPair<TMetricLabels, TArray<TSummaryQuantile>>.Create(ALabels.Clone, AQuantiles));
  FSums.Add(TPair<TMetricLabels, Double>.Create(ALabels.Clone, ASum));
  FCounts.Add(TPair<TMetricLabels, Int64>.Create(ALabels.Clone, ACount));
end;

function TMetricSnapshot.ToPrometheusText: string;
var
  SB: TStringBuilder;
  I, J: Integer;
  Labels: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('# HELP ').Append(FName).Append(' ').AppendLine(FHelp);
    SB.Append('# TYPE ').Append(FName).Append(' ').AppendLine(FType.ToString);

    case FType of
      mtCounter, mtGauge:
      begin
        for I := 0 to FValues.Count - 1 do
        begin
          Labels := FValues[I].Key.ToPrometheusString;
          SB.Append(FName).Append(Labels).Append(' ');
          SB.AppendLine(FormatFloat('0.######', FValues[I].Value));
        end;
      end;

      mtHistogram:
      begin
        for I := 0 to FBuckets.Count - 1 do
        begin
          Labels := FBuckets[I].Key.ToPrometheusString;
          for J := 0 to Length(FBuckets[I].Value) - 1 do
          begin
            if Labels <> '' then
              SB.Append(FName).Append('_bucket{le="')
                .Append(FormatFloat('0.######', FBuckets[I].Value[J].UpperBound))
                .Append('",').Append(Copy(Labels, 2, Length(Labels) - 2)).Append('}')
            else
              SB.Append(FName).Append('_bucket{le="')
                .Append(FormatFloat('0.######', FBuckets[I].Value[J].UpperBound))
                .Append('"}');
            SB.Append(' ').AppendLine(IntToStr(FBuckets[I].Value[J].Count));
          end;
        end;
        for I := 0 to FSums.Count - 1 do
        begin
          Labels := FSums[I].Key.ToPrometheusString;
          SB.Append(FName).Append('_sum').Append(Labels).Append(' ');
          SB.AppendLine(FormatFloat('0.######', FSums[I].Value));
        end;
        for I := 0 to FCounts.Count - 1 do
        begin
          Labels := FCounts[I].Key.ToPrometheusString;
          SB.Append(FName).Append('_count').Append(Labels).Append(' ');
          SB.AppendLine(IntToStr(FCounts[I].Value));
        end;
      end;

      mtSummary:
      begin
        for I := 0 to FQuantiles.Count - 1 do
        begin
          Labels := FQuantiles[I].Key.ToPrometheusString;
          for J := 0 to Length(FQuantiles[I].Value) - 1 do
          begin
            if Labels <> '' then
              SB.Append(FName).Append('{quantile="')
                .Append(FormatFloat('0.##', FQuantiles[I].Value[J].Quantile))
                .Append('",').Append(Copy(Labels, 2, Length(Labels) - 2)).Append('}')
            else
              SB.Append(FName).Append('{quantile="')
                .Append(FormatFloat('0.##', FQuantiles[I].Value[J].Quantile))
                .Append('"}');
            SB.Append(' ').AppendLine(FormatFloat('0.######', FQuantiles[I].Value[J].Value));
          end;
        end;
        for I := 0 to FSums.Count - 1 do
        begin
          Labels := FSums[I].Key.ToPrometheusString;
          SB.Append(FName).Append('_sum').Append(Labels).Append(' ');
          SB.AppendLine(FormatFloat('0.######', FSums[I].Value));
        end;
        for I := 0 to FCounts.Count - 1 do
        begin
          Labels := FCounts[I].Key.ToPrometheusString;
          SB.Append(FName).Append('_count').Append(Labels).Append(' ');
          SB.AppendLine(IntToStr(FCounts[I].Value));
        end;
      end;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMetricSnapshot.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('help', FHelp);
  Result.AddPair('type', FType.ToString);
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
  // Simplified - full implementation would serialize all values
end;

end.
