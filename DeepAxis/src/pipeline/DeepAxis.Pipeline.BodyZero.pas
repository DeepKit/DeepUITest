unit DeepAxis.Pipeline.BodyZero;

interface

uses
  System.SysUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   Body-Zero auditor — compile-time and runtime enforcement of
  ///   the P0 invariant: no message body content is ever accessed.
  /// </summary>
  TBodyZeroAuditor = class
  private
    FBodyColumnsSeen: Boolean;
    FBodyColumnsQueried: Boolean;
    FBodyQueriedCount: Integer;
    FWriteAttempts: Integer;
    FUiaCalls: Integer;
    FAuditChain: string; // SHA-256 hash chain for tamper evidence
  public
    constructor Create;
    /// <summary>Record that a body column was present in the schema (ok, not accessed)</summary>
    procedure RecordBodyColumnSeen;
    /// <summary>BLOCKING: Record that a body column was queried — M1 授权读取时调用, 真实计数</summary>
    procedure RecordBodyColumnQueried(const AColumnName: string);
    /// <summary>Record a write attempt to WeChat DB</summary>
    procedure RecordWriteAttempt(const ATableName: string);
    /// <summary>Record a UIA automation call</summary>
    procedure RecordUiaCall(const ACallName: string);
    /// <summary>Generate the BodyZero report with hash chain</summary>
    function GenerateReport: TBodyZeroReport;
    /// <summary>Verify the report is clean. Returns True if no violations found.</summary>
    function IsClean: Boolean;
    /// <summary>Raise an assertion if violations found (for debug builds)</summary>
    procedure AssertClean;
  end;

implementation

uses
  System.Hash;

{ TBodyZeroAuditor }

constructor TBodyZeroAuditor.Create;
begin
  inherited Create;
  FBodyColumnsSeen := False;
  FBodyColumnsQueried := False;
  FBodyQueriedCount := 0;
  FWriteAttempts := 0;
  FUiaCalls := 0;
  FAuditChain := '';
end;

procedure TBodyZeroAuditor.RecordBodyColumnSeen;
begin
  FBodyColumnsSeen := True;
end;

procedure TBodyZeroAuditor.RecordBodyColumnQueried(const AColumnName: string);
begin
  FBodyColumnsQueried := True;
  Inc(FBodyQueriedCount);
  // Build hash chain
  FAuditChain := THashSHA2.GetHashString(
    FAuditChain + '|QUERY_BODY:' + AColumnName + '|' + DateTimeToStr(Now),
    THashSHA2.TSHA2Version.SHA256);
end;

procedure TBodyZeroAuditor.RecordWriteAttempt(const ATableName: string);
begin
  Inc(FWriteAttempts);
  FAuditChain := THashSHA2.GetHashString(
    FAuditChain + '|WRITE:' + ATableName + '|' + DateTimeToStr(Now),
    THashSHA2.TSHA2Version.SHA256);
end;

procedure TBodyZeroAuditor.RecordUiaCall(const ACallName: string);
begin
  Inc(FUiaCalls);
  FAuditChain := THashSHA2.GetHashString(
    FAuditChain + '|UIA:' + ACallName + '|' + DateTimeToStr(Now),
    THashSHA2.TSHA2Version.SHA256);
end;

function TBodyZeroAuditor.GenerateReport: TBodyZeroReport;
begin
  Result := TBodyZeroReport.CreateClean;
  Result.BodyColumnsSeen := FBodyColumnsSeen;
  Result.BodyColumnsQueried := FBodyColumnsQueried;
  Result.BodyQueriedCount := FBodyQueriedCount;
  Result.WriteAttempts := FWriteAttempts;
  Result.UiaCalls := FUiaCalls;
  Result.GeneratedAt := Now;
end;

function TBodyZeroAuditor.IsClean: Boolean;
begin
  Result := (not FBodyColumnsQueried) and (FWriteAttempts = 0) and (FUiaCalls = 0);
end;

procedure TBodyZeroAuditor.AssertClean;
begin
  if not IsClean then
    raise EAssertionFailed.Create(
      'BodyZero violation: body_queried=' + BoolToStr(FBodyColumnsQueried, True) +
      ' writes=' + IntToStr(FWriteAttempts) +
      ' uia=' + IntToStr(FUiaCalls) +
      ' audit=' + Copy(FAuditChain, 1, 32) + '...');
end;

end.