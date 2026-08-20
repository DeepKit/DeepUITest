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
    Action: string;      // merge/clean/extract/add/product_match
    Detail: string;      // 建议详情 (自然语言, 展示用)
    Confidence: Double;
    Field: string;       // 标准备注字段名 (渠道/成交/产品/电话/金额/标签建议/备注补全), 供 L2a 写回
    Value: string;       // 字段值 (如 '小红书' / '0520' / '合并A到B'); add 类为空, 由 UI 补全
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

  TTagManager = class
  private
    FProductFactCard: TProductFactCard;
    function ExtractPhone(const AText: string): TArray<string>;
    function ExtractAmount(const AText: string): TArray<string>;
    function ExtractDate(const AText: string): TArray<string>;
    function ExtractChannel(const AText: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>检测相似标签（建议合并）</summary>
    function DetectSimilarLabels(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;

    /// <summary>检测备注中可提取的信息（电话/金额/日期/渠道 + 已知产品匹配）</summary>
    function AnalyzeRemarks(const AContact: TContact): TArray<TTagSuggestion>;

    /// <summary>检测空备注（建议补充）</summary>
    function DetectEmptyRemarks(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;

    /// <summary>生成标签整理建议报告（文本摘要）</summary>
    function GenerateReport(const AContacts: TArray<TContact>): string;

    /// <summary>生成 L0 只读分析报告 — 结构化建议列表（供 L1 面板展示）。
    ///  聚合 DetectSimilarLabels + DetectEmptyRemarks + AnalyzeRemarks 三类 L0 建议。
    ///  docs/08 §1 L0: 只分析本地数据, 不产生任何对微信的变更。</summary>
    function GenerateL0Report(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;

    /// <summary>产品事实卡 (话术引擎变量来源), 无产品库时为空</summary>
    property ProductFactCard: TProductFactCard read FProductFactCard;

    /// <summary>L2a 写回辅助: 在原备注末尾追加标准化字段 ┊{Field}:{Value}。
    ///  docs/08 §3.3 格式; §3.2 安全约束: 不改用户原文(只 append)、不覆盖写入(同字段已存在则原样返回)。
    ///  AValue 为空时原样返回 (add 类由 UI 弹框补全后再调)。</summary>
    class function BuildAppendRemark(const AOrigRemark, AField, AValue: string): string; static;
  end;

  /// <summary>
  ///   轻量订单信号 — 从备注和聊天元数据中提取订单状态。
  ///   P0: 从备注中正则提取日期/金额信号。
  ///   P2+: 从消息内容中提取。
  ///   TODO(P2): 无真实订单数据源, 现仅从备注正则提取; 接入订单 DB 后扩展 ExtractOrderFromRemark。
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

constructor TTagManager.Create;
begin
  inherited;
  FProductFactCard := TProductFactCard.Create;
  // 无产品库数据源, FProductFactCard 暂为空; FindProduct 对空库返回 Default(TProductFact), 安全。
  // TODO(P1+): 接入产品库后调用 FProductFactCard.AddProduct 加载真实产品。
end;

destructor TTagManager.Destroy;
begin
  FProductFactCard.Free;
  inherited;
end;

function TTagManager.ExtractPhone(const AText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result := nil;
  // 电话: 1[3-9] 开头 + 9 位数字. 中文环境 \b 不可靠, 用非数字边界限定, 取捕获组1
  LMatch := TRegEx.Match(AText, '(?:^|[^0-9])(1[3-9]\d{9})(?:[^0-9]|$)');
  while LMatch.Success do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LMatch.Groups[1].Value;
    LMatch := LMatch.NextMatch;
  end;
end;

function TTagManager.ExtractAmount(const AText: string): TArray<string>;
var
  LMatch: TMatch;
begin
  Result := nil;
  // 去掉末尾 \b — "元"是中文, 其后无 \w 词边界
  LMatch := TRegEx.Match(AText, '\d+\.?\d*\s*[元块]');
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
          LSugg.Field := '标签建议';
          LSugg.Value := Format('合并%s到%s', [LContact.WeChatLabels[I], LContact.WeChatLabels[J]]);
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
    LSugg.Field := '电话';
    LSugg.Value := S;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LAmounts := ExtractAmount(AContact.Remark);
  for S in LAmounts do
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现金额: %s', [S]);
    LSugg.Confidence := 0.85;
    LSugg.Field := '金额';
    LSugg.Value := S;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LDates := ExtractDate(AContact.Remark);
  for S in LDates do
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现日期: %s', [S]);
    LSugg.Confidence := 0.85;
    LSugg.Field := '成交';
    LSugg.Value := S;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  LChannel := ExtractChannel(AContact.Remark);
  if LChannel <> '' then
  begin
    LSugg.ContactId := AContact.ContactId;
    LSugg.Action := 'extract';
    LSugg.Detail := Format('备注中发现渠道: %s', [LChannel]);
    LSugg.Confidence := 0.8;
    LSugg.Field := '渠道';
    LSugg.Value := LChannel;
    SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
  end;

  // 产品事实卡匹配 — 若备注中出现已知产品名, 标注关联产品 (无产品库时跳过)
  for S in FProductFactCard.GetProductNames do
    if Pos(S, AContact.Remark) > 0 then
    begin
      LSugg.ContactId := AContact.ContactId;
      LSugg.Action := 'product_match';
      LSugg.Detail := Format('备注匹配已知产品: %s', [S]);
      LSugg.Confidence := 0.85;
      LSugg.Field := '产品';
      LSugg.Value := S;
      SetLength(Result, Length(Result) + 1); Result[High(Result)] := LSugg;
    end;
end;

function TTagManager.GenerateL0Report(const AContacts: TArray<TContact>): TArray<TTagSuggestion>;
var
  LSugg: TTagSuggestion;
  LContact: TContact;
  LRemarks: TArray<TTagSuggestion>;
begin
  Result := nil;
  // 1. 相似标签建议 (merge)
  for LSugg in DetectSimilarLabels(AContacts) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LSugg;
  end;
  // 2. 空备注建议 (add)
  for LSugg in DetectEmptyRemarks(AContacts) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LSugg;
  end;
  // 3. 逐个联系人备注提取 (extract + product_match)
  for LContact in AContacts do
  begin
    LRemarks := AnalyzeRemarks(LContact);
    for LSugg in LRemarks do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LSugg;
    end;
  end;
end;

class function TTagManager.BuildAppendRemark(const AOrigRemark, AField, AValue: string): string;
begin
  // docs/08 §3.2 安全约束: 不覆盖写入 — 同字段已存在则原样返回 (不重复加, 不改原值)
  if AValue = '' then
    Exit(AOrigRemark);
  if Pos('┊' + AField + ':', AOrigRemark) > 0 then
    Exit(AOrigRemark);
  Result := AOrigRemark + '┊' + AField + ':' + AValue;
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
      LSugg.Field := '备注补全';
      LSugg.Value := '';
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