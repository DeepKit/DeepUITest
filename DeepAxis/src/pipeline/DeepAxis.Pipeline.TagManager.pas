unit DeepAxis.Pipeline.TagManager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.RegularExpressions, System.DateUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   L0 标签/备注管理 — 只读分析，不写回微信。
  ///   检测: 标签去重、格式不一致、备注信息提取（日期/金额/电话/渠道）
  /// </summary>
  TTagSuggestion = record
    ContactId: string;
    Action: string;      // merge/clean/extract
    Detail: string;      // 建议详情
    Confidence: Double;
  end;

  TTagManager = class
  private
    function ExtractPhone(const AText: string): TArray<string>;
    function ExtractAmount(const AText: string): TArray<string>;
    function ExtractDate(const AText: string): TArray<string>;
    function ExtractChannel(const AText: string): string;
  public
    /// <summary>检测相似标签（建议合并）</summary>
    function DetectSimilarLabels(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;

    /// <summary>检测备注中可提取的信息</summary>
    function AnalyzeRemarks(const AContact: TContact): TArray<TTagSuggestion>;

    /// <summary>检测空备注（建议补充）</summary>
    function DetectEmptyRemarks(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;

    /// <summary>生成标签整理建议报告</summary>
    function GenerateReport(const AContacts: TArray<TContact>): string;
  end;

  /// <summary>
  ///   产品事实卡 — 产品信息存储。
  ///   话术引擎从中提取 {产品名}、{价格}、{卖点} 等变量。
  /// </summary>
  TProductFact = record
    ProductId: string;
    Name: string;
    PriceRange: string;      // 价格区间
    Inventory: string;       // 库存/活动
    SellingPoints: string;   // 卖点
    ForbiddenClaims: string; // 禁用承诺
    FAQ: string;             // 常见问题
    Materials: string;       // 素材路径
  end;

  TProductFactCard = class
  private
    FProducts: TList<TProductFact>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddProduct(const AFact: TProductFact);
    function FindProduct(const AName: string): TProductFact;
    function GetAllProducts: TArray<TProductFact>;
    function GetProductNames: TArray<string>;
  end;

  /// <summary>
  ///   轻量订单信号 — 从备注和聊天元数据中提取订单状态。
  ///   P0: 从备注中正则提取日期/金额信号。
  ///   P2+: 从消息内容中提取。
  /// </summary>
  TOrderSignal = record
    ContactId: string;
    Status: string;         // 已买/待付款/待发货/已发货/售后中/复购
    Amount: Double;
    Date: TDateTime;
    ProductName: string;
    Source: string;         // 来源: remark/metadata
    Confidence: Double;
  end;

  TOrderTracker = class
  private
    FSignals: TList<TOrderSignal>;
    function ExtractOrderFromRemark(const AContact: TContact): TOrderSignal;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ScanContact(const AContact: TContact);
    procedure ScanContacts(const AContacts: TArray<TContact>);
    function GetSignals(const AContactId: string): TArray<TOrderSignal>;
    function GetAllSignals: TArray<TOrderSignal>;
    function GetRepurchaseAlerts(const ADaysThreshold: Integer): TArray<TOrderSignal>;
  end;

implementation

{ TTagManager }

function TTagManager.ExtractPhone(const AText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result := nil;
  LMatch := TRegEx.Match(AText, '\b1[3-9]\d{9}\b');
  while LMatch.Success do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LMatch.Value;
    LMatch := LMatch.NextMatch;
  end;
end;

function TTagManager.ExtractAmount(const AText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result := nil;
  LMatch := TRegEx.Match(AText, '\b\d+\.?\d*\s*[元块]\b');
  while LMatch.Success do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LMatch.Value;
    LMatch := LMatch.NextMatch;
  end;
end;

function TTagManager.ExtractDate(const AText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result := nil;
  LMatch := TRegEx.Match(AText, '\b(20\d{2}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2})\b');
  while LMatch.Success do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LMatch.Value;
    LMatch := LMatch.NextMatch;
  end;
end;

function TTagManager.ExtractChannel(const AText: string): string;
const
  CHANNELS: array[0..7] of string = (
    '小红书', '抖音', '快手', '转介绍', '微信群', '线下', '公众号', '视频号'
  );
var
  S: string;
begin
  Result := '';
  for S in CHANNELS do
    if Pos(S, AText) > 0 then Exit(S);
end;

function TTagManager.DetectSimilarLabels(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;
var
  I, J: Integer;
  LContact: TContact;
  LLabel1, LLabel2: string;
  LSugg: TTagSuggestion;
begin
  Result := nil;
  for LContact in AContacts do
  begin
    for I := 0 to Length(LContact.WeChatLabels) - 2 do
      for J := I + 1 to Length(LContact.WeChatLabels) - 1 do
      begin
        LLabel1 := LContact.WeChatLabels[I].ToLower;
        LLabel2 := LContact.WeChatLabels[J].ToLower;
        if (Pos(LLabel1, LLabel2) > 0) or (Pos(LLabel2, LLabel1) > 0) then
        begin
          LSugg.ContactId := LContact.ContactId;
          LSugg.Action := 'merge';
          LSugg.Detail := Format('标签"%s"和"%s"相似，建议合并', [LContact.WeChatLabels[I], LContact.WeChatLabels[J]]);
          LSugg.Confidence := 0.8;
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := LSugg;
        end;
      end;
  end;
end;

function TTagManager.AnalyzeRemarks(const AContact: TContact): TArray<TTagSuggestion>;
var
  LSugg: TTagSuggestion;
  LPhones, LAmounts, LDates: TArray<string>;
  LChannel: string;
  S: string;
begin
  Result := nil;
  if AContact.Remark = '' then Exit;

  LPhones := ExtractPhone(AContact.Remark);
  for S in LPhones do
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现电话: %s', [S]);
    LSugg.Confidence := 0.9;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LAmounts := ExtractAmount(AContact.Remark);
  for S in LAmounts do
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现金额: %s', [S]);
    LSugg.Confidence := 0.85;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LDates := ExtractDate(AContact.Remark);
  for S in LDates do
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现日期: %s', [S]);
    LSugg.Confidence := 0.85;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LChannel := ExtractChannel(AContact.Remark);
  if LChannel <> '' then
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现渠道: %s', [LChannel]);
    LSugg.Confidence := 0.8;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;
end;

function TTagManager.DetectEmptyRemarks(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;
var
  LContact: TContact;
  LSugg: TTagSuggestion;
begin
  Result := nil;
  for LContact in AContacts do
    if LContact.Remark = '' then
    begin
      LSugg.ContactId := LContact.ContactId;
      LSugg.Action := 'add';
      LSugg.Detail := Format('联系人"%s"备注为空，建议补充信息', [LContact.DisplayNameRedacted]);
      LSugg.Confidence := 0.9;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LSugg;
    end;
end;

function TTagManager.GenerateReport(const AContacts: TArray<TContact>): string;
var
  LSimilar, LEmpty: TArray<TTagSuggestion>;
  LTotalExtracts: Integer;
  LContact: TContact;
begin
  LSimilar := DetectSimilarLabels(AContacts);
  LEmpty := DetectEmptyRemarks(AContacts);
  LTotalExtracts := 0;
  for LContact in AContacts do
    LTotalExtracts := LTotalExtracts + Length(AnalyzeRemarks(LContact));

  Result := Format('标签/备注分析报告:'#13#10 +
    '  相似标签: %d 组建议合并'#13#10 +
    '  空备注: %d 个联系人'#13#10 +
    '  备注提取: %d 条信息'#13#10 +
    '  总联系人: %d',
    [Length(LSimilar), Length(LEmpty), LTotalExtracts, Length(AContacts)]);
end;

{ TProductFactCard }

constructor TProductFactCard.Create;
begin
  inherited;
  FProducts := TList<TProductFact>.Create;
end;

destructor TProductFactCard.Destroy;
begin
  FProducts.Free;
  inherited;
end;

procedure TProductFactCard.AddProduct(const AFact: TProductFact);
begin
  FProducts.Add(AFact);
end;

function TProductFactCard.FindProduct(const AName: string): TProductFact;
var
  LP: TProductFact;
begin
  for LP in FProducts do
    if Pos(LP.Name, AName) > 0 then Exit(LP);
  Result := Default(TProductFact);
end;

function TProductFactCard.GetAllProducts: TArray<TProductFact>;
begin
  Result := FProducts.ToArray;
end;

function TProductFactCard.GetProductNames: TArray<string>;
var
  LP: TProductFact;
begin
  Result := nil;
  for LP in FProducts do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LP.Name;
  end;
end;

{ TOrderTracker }

constructor TOrderTracker.Create;
begin
  inherited;
  FSignals := TList<TOrderSignal>.Create;
end;

destructor TOrderTracker.Destroy;
begin
  FSignals.Free;
  inherited;
end;

function TOrderTracker.ExtractOrderFromRemark(const AContact: TContact): TOrderSignal;
var
  LMatch: TMatch;
begin
  Result := Default(TOrderSignal);
  Result.ContactId := AContact.ContactId;
  Result.Source := 'remark';
  Result.Confidence := 0.5;

  // 检测成交信号
  LMatch := TRegEx.Match(AContact.Remark, '\b(成交|已买|付款|下单|购买)\b');
  if LMatch.Success then
  begin
    Result.Status := '已买';
    Result.Confidence := 0.7;
  end;

  // 提取金额
  LMatch := TRegEx.Match(AContact.Remark, '\b(\d+\.?\d*)\s*[元块]\b');
  if LMatch.Success then
    Result.Amount := StrToFloatDef(LMatch.Groups[1].Value, 0);

  // 提取日期
  LMatch := TRegEx.Match(AContact.Remark, '\b(20\d{2}[-/]\d{1,2}[-/]\d{1,2})\b');
  if LMatch.Success then
    Result.Date := StrToDateDef(LMatch.Value, 0);
end;

procedure TOrderTracker.ScanContact(const AContact: TContact);
var
  LSignal: TOrderSignal;
begin
  LSignal := ExtractOrderFromRemark(AContact);
  if LSignal.Confidence > 0.5 then
    FSignals.Add(LSignal);
end;

procedure TOrderTracker.ScanContacts(const AContacts: TArray<TContact>);
var
  LContact: TContact;
begin
  FSignals.Clear;
  for LContact in AContacts do
    ScanContact(LContact);
end;

function TOrderTracker.GetSignals(const AContactId: string): TArray<TOrderSignal>;
var
  LSig: TOrderSignal;
begin
  Result := nil;
  for LSig in FSignals do
    if LSig.ContactId = AContactId then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LSig;
    end;
end;

function TOrderTracker.GetAllSignals: TArray<TOrderSignal>;
begin
  Result := FSignals.ToArray;
end;

function TOrderTracker.GetRepurchaseAlerts(const ADaysThreshold: Integer): TArray<TOrderSignal>;
var
  LSig: TOrderSignal;
  LDays: Integer;
begin
  Result := nil;
  for LSig in FSignals do
  begin
    if LSig.Status <> '已买' then Continue;
    if LSig.Date = 0 then Continue;
    LDays := DaysBetween(Now, LSig.Date);
    if LDays >= ADaysThreshold then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LSig;
    end;
  end;
end;

end.