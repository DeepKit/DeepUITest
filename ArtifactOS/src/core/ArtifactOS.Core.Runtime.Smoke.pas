unit ArtifactOS.Core.Runtime.Smoke;

interface

type
  TRuntimeSmoke = class
  public
    class function Run(out AMessage: string): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  ArtifactOS.Core.Runtime.Repository,
  ArtifactOS.Core.Runtime.Types;

class function TRuntimeSmoke.Run(out AMessage: string): Boolean;
var
  InstanceId: string;
  CommandId: string;
  Claimed: TRuntimeCommandInfo;
  FinalCommand: TRuntimeCommandInfo;
begin
  Result := False;
  AMessage := '';
  InstanceId := '';
  try
    InstanceId := TRuntimeRepository.RegisterInstance(
      RuntimeInstanceTypeEngine,
      'artifactos-runtime-smoke-' + FormatDateTime('yyyymmddhhnnss', Now),
      GetEnvironmentVariable('COMPUTERNAME'),
      GetCurrentProcessId,
      'smoke',
      '{"smoke":true}');

    if InstanceId = '' then
    begin
      AMessage := 'runtime instance was not registered';
      Exit;
    end;

    TRuntimeRepository.HeartbeatInstance(InstanceId);
    CommandId := TRuntimeRepository.CreateCommand(
      'runtime.status.refresh',
      RuntimeCommandLevelL0,
      'runtime-smoke',
      RuntimeCommandSourceTest,
      '{"smoke":true}',
      10,
      'runtime-smoke-' + InstanceId,
      0,
      '{"smoke":true}');

    if CommandId = '' then
    begin
      AMessage := 'runtime command was not created';
      Exit;
    end;

    Claimed := TRuntimeRepository.ClaimNextCommand(InstanceId, 300);
    if not RuntimeHasCommand(Claimed) then
    begin
      AMessage := 'runtime command was not claimed';
      Exit;
    end;

    if Claimed.Id <> CommandId then
    begin
      AMessage := 'claimed command mismatch';
      Exit;
    end;

    if TRuntimeRepository.MarkCommandRunning(CommandId, InstanceId, 300) <> 1 then
    begin
      AMessage := 'runtime command was not marked running';
      Exit;
    end;

    if TRuntimeRepository.ExtendCommandLease(CommandId, InstanceId, 300) <> 1 then
    begin
      AMessage := 'runtime command lease was not extended';
      Exit;
    end;

    // TD26-004-R: 冒烟终态回写走 fencing 强校验, 与 Engine 主循环一致.
    // token 取自 ClaimNextCommand 返回的 Claimed.FencingToken(claim 时由 PG 递增).
    if TRuntimeRepository.CompleteCommandWithFencing(CommandId, Claimed.FencingToken, 'succeeded', '{"smoke":"passed"}') <> 1 then
    begin
      AMessage := 'runtime command was not marked succeeded';
      Exit;
    end;

    FinalCommand := TRuntimeRepository.GetCommand(CommandId);
    if not RuntimeCommandIsTerminal(FinalCommand.Status) then
    begin
      AMessage := 'runtime command did not reach terminal status';
      Exit;
    end;

    TRuntimeRepository.MarkInstanceStopped(InstanceId);
    Result := True;
    AMessage := 'runtime smoke passed: ' + CommandId;
  except
    on E: Exception do
    begin
      if InstanceId <> '' then
      begin
        try
          TRuntimeRepository.MarkInstanceStopped(InstanceId, RuntimeInstanceStatusFailed);
        except
          on E2: Exception do
            WriteLn(ErrOutput, 'runtime smoke cleanup failed: ', E2.ClassName, ' ', E2.Message);
        end;
      end;
      AMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

end.
