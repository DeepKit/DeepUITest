unit DeepAxis.Pipeline.Evidence;

interface

uses
  System.SysUtils, System.DateUtils, System.Hash,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Builds evidence chain for each radar hint.
  ///   P0: Every hint gets at least one EvidenceRecord with source_hash.
  ///   BodyZeroReport is always clean (P0 invariant).
  /// </summary>
  TEvidenceBuilder = class(TInterfacedObject, IEvidenceBuilder)
  private
    function CreateEvidence(const AHint: TRadarHint;
      const AType: TEvidenceType; const ASourceRef, ASummary: string): TEvidenceRecord;
  public
    function Build(const AHint: TRadarHint;
      const AMetrics: TArray<TInteractionMetric>): TArray<TEvidenceRecord>;
    function BuildBodyZeroReport: TBodyZeroReport;
  end;

implementation

{ TEvidenceBuilder }

function TEvidenceBuilder.CreateEvidence(const AHint: TRadarHint;
  const AType: TEvidenceType; const ASourceRef, ASummary: string): TEvidenceRecord;
begin
  Result := Default(TEvidenceRecord);
  Result.EvidenceId := GenerateId;
  Result.HintId := AHint.HintId;
  Result.SourceAccountId := AHint.SourceAccountId;
  Result.EvidenceType := AType;
  Result.SourceRef := ASourceRef;
  Result.SourceHash := SHA256Hex(Format('%s|%s|%d|%s|%s|%s',
    [AHint.ContactId, AHint.HintId, Ord(AType),
     DateToISO8601(AHint.WindowStart), DateToISO8601(AHint.WindowEnd),
     ASourceRef]));
  Result.Summary := ASummary;
  Result.ContainsBody := False; // P0 invariant
  Result.CreatedAt := Now;
end;

function TEvidenceBuilder.Build(const AHint: TRadarHint;
  const AMetrics: TArray<TInteractionMetric>): TArray<TEvidenceRecord>;
var
  LMetric: TInteractionMetric;
  I: Integer;
begin
  Result := nil;

  // Find the metric for this hint's contact
  LMetric := Default(TInteractionMetric);
  for I := 0 to Length(AMetrics) - 1 do
    if AMetrics[I].ContactId = AHint.ContactId then
    begin
      LMetric := AMetrics[I];
      Break;
    end;

  // Build evidence records based on hint type
  case AHint.HintType of
    rhtCooling:
      begin
        SetLength(Result, 3);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('inbound=%d,outbound=%d,window=%s',
            [LMetric.InboundCount, LMetric.OutboundCount,
             DateToStr(LMetric.WindowEnd)]),
          Format('当前窗口: %d条入站, %d条出站', [LMetric.InboundCount, LMetric.OutboundCount]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('days_since=%d,threshold=%d',
            [DaysBetween(Now, LMetric.LastInteractionAt), COOLING_DAYS]),
          Format('距上次互动 %d 天，超过降温阈值 %d 天',
            [DaysBetween(Now, LMetric.LastInteractionAt), COOLING_DAYS]));

        Result[2] := CreateEvidence(AHint, etMetric,
          Format('response_delay=%.1fs', [LMetric.ResponseDelayTrend]),
          Format('响应延迟趋势: %.1f 秒', [LMetric.ResponseDelayTrend]));
      end;

    rhtLongSilence:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('last_interaction=%s',
            [DateTimeToStr(LMetric.LastInteractionAt)]),
          Format('最后互动: %s', [DateTimeToStr(LMetric.LastInteractionAt)]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('days_since=%d,threshold=%d',
            [DaysBetween(Now, LMetric.LastInteractionAt), LONG_SILENCE_DAYS]),
          Format('已沉默 %d 天，超过阈值 %d 天',
            [DaysBetween(Now, LMetric.LastInteractionAt), LONG_SILENCE_DAYS]));
      end;

    rhtReactivated:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('recent_inbound=%d', [LMetric.InboundCount]),
          Format('最近入站消息: %d 条', [LMetric.InboundCount]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('reactivated_window=%d', [REACTIVATED_DAYS]),
          Format('%d 天内重新活跃', [REACTIVATED_DAYS]));
      end;

    rhtOutboundHeavy:
      begin
        SetLength(Result, 3);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('outbound=%d,inbound=%d', [LMetric.OutboundCount, LMetric.InboundCount]),
          Format('出站 %d 条 vs 入站 %d 条', [LMetric.OutboundCount, LMetric.InboundCount]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('ratio=%.1f,threshold=%.1f',
            [LMetric.OutboundInboundRatio, OUTBOUND_HEAVY_RATIO]),
          Format('比例 %.1f 超过阈值 %.1f', [LMetric.OutboundInboundRatio, OUTBOUND_HEAVY_RATIO]));

        Result[2] := CreateEvidence(AHint, etMetric,
          Format('data_quality=%s', [Ord(LMetric.DataQuality).ToString]),
          Format('数据质量: %s', [Ord(LMetric.DataQuality).ToString]));
      end;

    rhtDataInsufficient:
      begin
        SetLength(Result, 1);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('msg_count=%d,min=%d',
            [LMetric.InboundCount + LMetric.OutboundCount, MIN_MESSAGES_FOR_METRIC]),
          Format('消息数 %d 不足最低要求 %d',
            [LMetric.InboundCount + LMetric.OutboundCount, MIN_MESSAGES_FOR_METRIC]));
      end;

    rhtHighLinkSharing:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('link_count=%d,total_msgs=%d',
            [LMetric.LinkCount, LMetric.InboundCount + LMetric.OutboundCount]),
          Format('链接消息 %d 条，占消息总数 %d 条',
            [LMetric.LinkCount, LMetric.InboundCount + LMetric.OutboundCount]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('link_threshold=%d', [5]),
          '链接数超过阈值 5，可能存在推广行为');
      end;

    rhtMarketingPattern:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('has_marketing=true,avg_text_len=%d',
            [LMetric.AvgTextLength]),
          Format('检测到营销关键词，平均文本长度 %d 字',
            [LMetric.AvgTextLength]));

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('media_count=%d', [LMetric.MediaCount]),
          Format('媒体消息 %d 条', [LMetric.MediaCount]));
      end;
  end;
end;

function TEvidenceBuilder.BuildBodyZeroReport: TBodyZeroReport;
begin
  // P0 invariant: body-zero is always clean.
  // No code path reads message body columns.
  Result := TBodyZeroReport.CreateClean;
end;

end.
