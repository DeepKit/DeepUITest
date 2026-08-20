unit DeepAxis.Pipeline.Boundary;

interface

uses
  System.SysUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   G×U/L 边界分类。框架层硬约束：每个行动必须先通过边界检查。
  ///   🟢 绿色: 可自动执行
  ///   🟡 黄色: 系统生成建议，人类确认后执行
  ///   🔴 红色: 架构层禁止，即使人类请求也不执行
  /// </summary>
  TBoundaryClass = (bcGreen, bcYellow, bcRed);

  /// <summary>
  ///   G/U/L 三个维度的变量档位
  /// </summary>
  TGULLevel = (gulLow, gulMedium, gulHigh);

  /// <summary>
  ///   边界检查结果
  /// </summary>
  TBoundaryResult = record
    Classification: TBoundaryClass;
    Reason: string;
    G: TGULLevel;
    U: TGULLevel;
    L: TGULLevel;
    function ToChinese: string;
    function ToEmoji: string;
    function IsAllowed: Boolean;
  end;

  /// <summary>
  ///   Boundary Engine — G×U/L 公式计算。
  ///   G: 行动生成率/影响规模 (受影响人数、涉及金额、不可逆程度)
  ///   U: 后果不确定度 (是否有先例、黑箱环节、二阶外溢)
  ///   L: 调节延迟 (从检测到错误到完成修复的时间)
  /// </summary>
  TBoundaryEngine = class
  private
    function Classify(const AG, AU, AL: TGULLevel): TBoundaryClass;
  public
    /// <summary>检查一条话术的边界</summary>
    function CheckScript(const AScript: string; const AContact: TContact): TBoundaryResult;

    /// <summary>检查发送动作的边界</summary>
    function CheckSend(const AContact: TContact; ARecipientCount: Integer): TBoundaryResult;

    /// <summary>检查删除动作的边界</summary>
    function CheckDelete(const AContact: TContact): TBoundaryResult;

    /// <summary>检查批量操作的边界</summary>
    function CheckBatch(const AAction: string; ACount: Integer): TBoundaryResult;

    /// <summary>检查话术内容是否包含禁用词</summary>
    function HasForbiddenContent(const AScript: string): Boolean;
  end;

implementation

{ TBoundaryResult }

function TBoundaryResult.ToChinese: string;
begin
  case Classification of
    bcGreen:  Result := '绿色 — 可自动执行';
    bcYellow: Result := '黄色 — 需人工确认';
    bcRed:    Result := '红色 — 架构禁止';
  end;
end;

function TBoundaryResult.ToEmoji: string;
begin
  case Classification of
    bcGreen:  Result := '🟢';
    bcYellow: Result := '🟡';
    bcRed:    Result := '🔴';
  end;
end;

function TBoundaryResult.IsAllowed: Boolean;
begin
  Result := Classification <> bcRed;
end;

{ TBoundaryEngine }

function TBoundaryEngine.Classify(const AG, AU, AL: TGULLevel): TBoundaryClass;
begin
  // G×U/L 公式
  // 🔴 红色: G=高 且 U=高 或 L=长
  // 🟡 黄色: G=中 或 U=中 或 L=中
  // 🟢 绿色: G=低 且 U=低 且 L=短

  if (AG = gulHigh) and (AU = gulHigh) then
    Exit(bcRed);
  if AL = gulHigh then
    Exit(bcRed);

  if (AG = gulMedium) or (AU = gulMedium) or (AL = gulMedium) then
    Exit(bcYellow);

  Result := bcGreen;
end;

function TBoundaryEngine.CheckScript(const AScript: string;
  const AContact: TContact): TBoundaryResult;
var
  LG, LU, LL: TGULLevel;
begin
  Result := Default(TBoundaryResult);

  if AContact.IsUnknown or AContact.IsPrivate then
  begin
    Result.Classification := bcRed;
    Result.G := gulLow;
    Result.U := gulHigh;
    Result.L := gulMedium;
    if AContact.IsPrivate then
      Result.Reason := '联系人标记为 PRIVATE，禁止自动生成或粘贴话术'
    else
      Result.Reason := '联系人身份为 UNKNOWN，禁止自动生成或粘贴话术';
    Exit;
  end;

  // 检查禁用词
  if HasForbiddenContent(AScript) then
  begin
    Result.Classification := bcRed;
    Result.Reason := '话术包含禁用承诺词';
    Result.G := gulLow;
    Result.U := gulHigh;
    Result.L := gulLow;
    Exit;
  end;

  // 单条话术: G=低, U=低, L=短
  LG := gulLow;
  LU := gulLow;
  LL := gulLow;

  // 如果是对 PRIVATE 联系人，U=中
  if AContact.IsPrivate then
    LU := gulMedium;

  // 如果话术包含价格/优惠，U=中
  if (Pos('价格', AScript) > 0) or (Pos('优惠', AScript) > 0) or
     (Pos('便宜', AScript) > 0) or (Pos('活动', AScript) > 0) then
    LU := gulMedium;

  Result.Classification := Classify(LG, LU, LL);
  Result.G := LG;
  Result.U := LU;
  Result.L := LL;

  case Result.Classification of
    bcGreen:  Result.Reason := '单条话术，低风险，可自动执行';
    bcYellow: Result.Reason := '话术涉及价格/优惠，建议人工确认';
    bcRed:    Result.Reason := '话术包含禁用内容';
  end;
end;

function TBoundaryEngine.CheckSend(const AContact: TContact;
  ARecipientCount: Integer): TBoundaryResult;
var
  LG, LU, LL: TGULLevel;
begin
  Result := Default(TBoundaryResult);

  if AContact.IsUnknown or AContact.IsPrivate then
  begin
    Result.Classification := bcRed;
    Result.G := gulLow;
    Result.U := gulHigh;
    Result.L := gulMedium;
    if AContact.IsPrivate then
      Result.Reason := Format('发送对象为 PRIVATE (%d 条)，禁止自动执行', [ARecipientCount])
    else
      Result.Reason := Format('发送对象身份不明 (%d 条)，禁止自动执行', [ARecipientCount]);
    Exit;
  end;

  // G: 单条=低, 批量=高
  if ARecipientCount <= 1 then
    LG := gulLow
  else if ARecipientCount <= 10 then
    LG := gulMedium
  else
    LG := gulHigh;

  // U: 未知联系人=高
  LU := gulLow;
  if AContact.IsUnknown then
    LU := gulHigh
  else if AContact.IsPrivate then
    LU := gulMedium;

  // L: 发送后无法撤回，L=中
  LL := gulMedium;

  Result.Classification := Classify(LG, LU, LL);
  Result.G := LG;
  Result.U := LU;
  Result.L := LL;

  case Result.Classification of
    bcGreen:  Result.Reason := '单条发送，低风险';
    bcYellow: Result.Reason := Format('批量发送 %d 条，建议确认', [ARecipientCount]);
    bcRed:    Result.Reason := Format('发送对象身份不明 (%d 条)，禁止自动执行', [ARecipientCount]);
  end;
end;

function TBoundaryEngine.CheckDelete(const AContact: TContact): TBoundaryResult;
begin
  Result := Default(TBoundaryResult);
  Result.Classification := bcYellow; // 安全优先: 删除始终需人工确认，即使公式规则允许
  Result.G := gulLow;
  Result.U := gulMedium;
  Result.L := gulHigh;
  Result.Reason := '删除操作不可逆，必须人工确认';
end;

function TBoundaryEngine.CheckBatch(const AAction: string;
  ACount: Integer): TBoundaryResult;
var
  LG, LU, LL: TGULLevel;
begin
  Result := Default(TBoundaryResult);

  if ACount <= 10 then
    LG := gulLow
  else if ACount <= 50 then
    LG := gulMedium
  else
    LG := gulHigh;

  LU := gulLow;
  LL := gulLow;

  if Pos('发送', AAction) > 0 then
    LL := gulMedium; // 发送后无法撤回

  Result.Classification := Classify(LG, LU, LL);
  Result.G := LG;
  Result.U := LU;
  Result.L := LL;

  case Result.Classification of
    bcGreen:  Result.Reason := Format('批量 %s (%d条)，低风险', [AAction, ACount]);
    bcYellow: Result.Reason := Format('批量 %s (%d条)，建议确认后执行', [AAction, ACount]);
    bcRed:    Result.Reason := Format('批量 %s (%d条) 超过安全阈值，禁止', [AAction, ACount]);
  end;
end;

function TBoundaryEngine.HasForbiddenContent(const AScript: string): Boolean;
const
  FORBIDDEN: array[0..7] of string = (
    '保证', '承诺', '一定有效', '100%', '包治', '绝对',
    '无效退款', '免费送'
  );
var
  S: string;
begin
  Result := False;
  for S in FORBIDDEN do
    if Pos(S, AScript) > 0 then
      Exit(True);
end;

end.
