unit ArtifactOS.Core.Runtime.Engine;

interface

type
  TEngineConfig = record
    HostName: string;
    AppVersion: string;
    PollIntervalMs: Integer;
    HeartbeatIntervalMs: Integer;
    LeaseSeconds: Integer;
    IdleTimeoutMs: Integer;
    CleanupIntervalMs: Integer;
    MaxConsecutiveErrors: Integer;
  end;

  TEngineStatus = (esIdle, esRunning, esStopping);

  TEngineProc = reference to procedure(const ACommandId, ACommandType: string; const APayloadJson: string);

  TRuntimeEngine = class
  private
    FInstanceId: string;
    FConfig: TEngineConfig;
    FStatus: TEngineStatus;
    FCurrentCommandId: string;
    FLastActivity: TDateTime;
    FLastHeartbeat: TDateTime;
    FLastCleanup: TDateTime;
    FConsecutiveErrors: Integer;
    FCommandProc: TEngineProc;
    procedure DoHeartbeat;
    procedure DoPollAndProcess;
    procedure DoCleanup;
    function IdleMs: Int64;
    function IsRunning: Boolean;
  public
    constructor Create(const AConfig: TEngineConfig);
    destructor Destroy; override;
    procedure Run(ACommandProc: TEngineProc);
    procedure RequestStop;
    property InstanceId: string read FInstanceId;
    property Status: TEngineStatus read FStatus;
    property LastActivity: TDateTime read FLastActivity;
  end;

const
  DefaultEngineConfig: TEngineConfig = (
    HostName: '';
    AppVersion: '';
    PollIntervalMs: 5000;
    HeartbeatIntervalMs: 15000;
    LeaseSeconds: 300;
    IdleTimeoutMs: 600000;
    CleanupIntervalMs: 3600000;
    MaxConsecutiveErrors: 5;
  );

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.DateUtils,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Runtime.Repository,
  ArtifactOS.Core.Runtime.Types;

constructor TRuntimeEngine.Create(const AConfig: TEngineConfig);
begin
  FConfig := AConfig;
  if FConfig.HostName = '' then
    FConfig.HostName := GetEnvironmentVariable('COMPUTERNAME');
  if FConfig.AppVersion = '' then
    FConfig.AppVersion := '1.0';
  FStatus := esIdle;
end;

destructor TRuntimeEngine.Destroy;
begin
  RequestStop;
  inherited;
end;

function TRuntimeEngine.IdleMs: Int64;
begin
  Result := MilliSecondsBetween(Now, FLastActivity);
end;

function TRuntimeEngine.IsRunning: Boolean;
begin
  Result := FStatus <> esStopping;
end;

procedure TRuntimeEngine.RequestStop;
begin
  FStatus := esStopping;
end;

procedure TRuntimeEngine.DoHeartbeat;
var
  Elapsed: Int64;
begin
  Elapsed := MilliSecondsBetween(Now, FLastHeartbeat);
  if Elapsed < FConfig.HeartbeatIntervalMs then
    Exit;

  try
    TRuntimeRepository.HeartbeatInstance(FInstanceId, RuntimeInstanceStatusRunning);
    FLastHeartbeat := Now;
    FConsecutiveErrors := 0;
  except
    on E: Exception do
    begin
      Inc(FConsecutiveErrors);
      WriteLn(ErrOutput, 'heartbeat failed: ', E.ClassName, ' ', E.Message, ' (errors=', FConsecutiveErrors, ')');
    end;
  end;
end;

procedure TRuntimeEngine.DoCleanup;
var
  Elapsed: Int64;
  ExpiredCount: Integer;
begin
  Elapsed := MilliSecondsBetween(Now, FLastCleanup);
  if Elapsed < FConfig.CleanupIntervalMs then
    Exit;

  try
    ExpiredCount := TRuntimeRepository.MarkExpiredCommands;
    if ExpiredCount > 0 then
      WriteLn('cleanup: marked ', ExpiredCount, ' expired command(s)');

    FLastCleanup := Now;
  except
    on E: Exception do
      WriteLn(ErrOutput, 'cleanup failed: ', E.ClassName, ' ', E.Message);
  end;
end;

procedure TRuntimeEngine.DoPollAndProcess;
var
  Cmd: TRuntimeCommandInfo;
begin
  FCurrentCommandId := '';

  Cmd := TRuntimeRepository.ClaimNextCommand(FInstanceId, FConfig.LeaseSeconds);
  if not RuntimeHasCommand(Cmd) then
  begin
    FConsecutiveErrors := 0;
    Exit;
  end;

  FCurrentCommandId := Cmd.Id;
  FStatus := esRunning;
  FLastActivity := Now;
  WriteLn('claimed command: ', Cmd.CommandType, ' (', Cmd.Id, ')');

  try
    if TRuntimeRepository.MarkCommandRunning(Cmd.Id, FInstanceId, FConfig.LeaseSeconds) <> 1 then
    begin
      WriteLn(ErrOutput, 'failed to mark running: ', Cmd.Id);
      Exit;
    end;

    if Assigned(FCommandProc) then
    begin
      FCommandProc(Cmd.Id, Cmd.CommandType, Cmd.PayloadJson);
    end;

    TRuntimeRepository.MarkCommandSucceeded(Cmd.Id, FInstanceId, '{"engine":"' + FInstanceId + '"}');
    FConsecutiveErrors := 0;
    WriteLn('completed command: ', Cmd.CommandType, ' (', Cmd.Id, ')');
  except
    on E: Exception do
    begin
      Inc(FConsecutiveErrors);
      WriteLn(ErrOutput, 'command failed: ', Cmd.CommandType, ' (', Cmd.Id, ') - ', E.ClassName, ': ', E.Message);
      try
        TRuntimeRepository.MarkCommandFailed(Cmd.Id, FInstanceId, E.ClassName, E.Message,
          '{"engine":"' + FInstanceId + '","error":"' + E.Message + '"}');
      except
        on E2: Exception do
          WriteLn(ErrOutput, 'failed to mark failed: ', E2.ClassName, ' ', E2.Message);
      end;
    end;
  end;

  FLastActivity := Now;
  FCurrentCommandId := '';
  if FStatus = esRunning then
    FStatus := esIdle;
end;

procedure TRuntimeEngine.Run(ACommandProc: TEngineProc);
var
  StartTime: TDateTime;
begin
  FCommandProc := ACommandProc;
  StartTime := Now;

  WriteLn('ArtifactOS Engine starting');
  WriteLn('  host: ', FConfig.HostName);
  WriteLn('  pid:  ', GetCurrentProcessId);

  FInstanceId := TRuntimeRepository.RegisterInstance(
    RuntimeInstanceTypeEngine,
    'artifactos-engine-' + FConfig.HostName + '-' + IntToStr(GetCurrentProcessId),
    FConfig.HostName,
    GetCurrentProcessId,
    FConfig.AppVersion,
    '{"started":"' + DateTimeToStr(StartTime) + '"}');

  WriteLn('  instance: ', FInstanceId);

  FStatus := esIdle;
  FLastActivity := StartTime;
  FLastHeartbeat := StartTime;
  FLastCleanup := StartTime;

  try
    while IsRunning do
    begin
      try
        DoHeartbeat;
        DoPollAndProcess;
        DoCleanup;
      except
        on E: Exception do
        begin
          Inc(FConsecutiveErrors);
          WriteLn(ErrOutput, 'engine loop error: ', E.ClassName, ' ', E.Message,
            ' (errors=', FConsecutiveErrors, ')');
          if FConsecutiveErrors >= FConfig.MaxConsecutiveErrors then
          begin
            WriteLn(ErrOutput, 'too many consecutive errors, shutting down');
            FStatus := esStopping;
          end;
        end;
      end;

      if FStatus = esIdle then
      begin
        if IdleMs >= FConfig.IdleTimeoutMs then
        begin
          WriteLn('idle timeout reached (', FConfig.IdleTimeoutMs div 60000, ' min), shutting down');
          FStatus := esStopping;
          Break;
        end;
        Sleep(FConfig.PollIntervalMs);
      end;
    end;
  finally
    try
      if FInstanceId <> '' then
      begin
        WriteLn('stopping engine instance: ', FInstanceId);
        TRuntimeRepository.MarkInstanceStopped(FInstanceId);
      end;
    except
      on E: Exception do
        WriteLn(ErrOutput, 'failed to stop instance: ', E.ClassName, ' ', E.Message);
    end;
  end;

  WriteLn('ArtifactOS Engine stopped');
end;

end.