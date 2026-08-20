unit ArtifactOS.Core.Runtime.Types;

interface

const
  RuntimeInstanceTypeDesk = 'desk';
  RuntimeInstanceTypeEngine = 'engine';
  RuntimeInstanceTypePublishingRuntime = 'publishing_runtime';
  RuntimeInstanceTypeDiagnostic = 'diagnostic';

  RuntimeInstanceStatusStarting = 'starting';
  RuntimeInstanceStatusRunning = 'running';
  RuntimeInstanceStatusIdle = 'idle';
  RuntimeInstanceStatusStopping = 'stopping';
  RuntimeInstanceStatusStopped = 'stopped';
  RuntimeInstanceStatusFailed = 'failed';

  RuntimeCommandStatusPending = 'pending';
  RuntimeCommandStatusClaimed = 'claimed';
  RuntimeCommandStatusRunning = 'running';
  RuntimeCommandStatusSucceeded = 'succeeded';
  RuntimeCommandStatusFailed = 'failed';
  RuntimeCommandStatusCancelled = 'cancelled';
  RuntimeCommandStatusLeaseExpired = 'lease_expired';
  RuntimeCommandStatusNeedsHuman = 'needs_human';
  RuntimeCommandStatusBlocked = 'blocked';

  RuntimeCommandLevelL0 = 'L0';
  RuntimeCommandLevelL1 = 'L1';
  RuntimeCommandLevelL2 = 'L2';
  RuntimeCommandLevelL3 = 'L3';

  RuntimeCommandSourceDesk = 'desk';
  RuntimeCommandSourceAmy = 'amy';
  RuntimeCommandSourceTest = 'test';
  RuntimeCommandSourceDiagnostic = 'diagnostic';
  RuntimeCommandSourceSystem = 'system';

type
  TRuntimeInstanceInfo = record
    Id: string;
    InstanceType: string;
    InstanceName: string;
    HostName: string;
    Pid: Integer;
    AppVersion: string;
    Status: string;
    StartedAt: string;
    HeartbeatAt: string;
    StoppedAt: string;
    MetadataJson: string;
  end;

  TRuntimeCommandInfo = record
    Id: string;
    CommandType: string;
    CommandLevel: string;
    RequestedBy: string;
    RequestedSource: string;
    Status: string;
    Priority: Integer;
    PayloadJson: string;
    IdempotencyKey: string;
    ClaimedBy: string;
    ClaimedAt: string;
    LeaseUntil: string;
    StartedAt: string;
    CompletedAt: string;
    RetryCount: Integer;
    MaxRetries: Integer;
    ErrorCode: string;
    ErrorMessage: string;
    ResultJson: string;
    MetadataJson: string;
    // TD26-004 统一信封字段 (docs/29 §5): fencing_token 防旧Worker回写, attempt_no 尝试计数, correlation_id 链路追踪
    FencingToken: Int64;
    AttemptNo: Integer;
    CorrelationId: string;
  end;

function RuntimeHasCommand(const ACommand: TRuntimeCommandInfo): Boolean;
function RuntimeCommandIsTerminal(const AStatus: string): Boolean;

implementation

uses
  System.SysUtils;

function RuntimeHasCommand(const ACommand: TRuntimeCommandInfo): Boolean;
begin
  Result := ACommand.Id <> '';
end;

function RuntimeCommandIsTerminal(const AStatus: string): Boolean;
begin
  Result := SameText(AStatus, RuntimeCommandStatusSucceeded)
    or SameText(AStatus, RuntimeCommandStatusFailed)
    or SameText(AStatus, RuntimeCommandStatusCancelled)
    or SameText(AStatus, RuntimeCommandStatusNeedsHuman)
    or SameText(AStatus, RuntimeCommandStatusBlocked);
end;

end.
