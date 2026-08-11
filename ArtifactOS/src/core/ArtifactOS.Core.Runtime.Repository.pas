unit ArtifactOS.Core.Runtime.Repository;

interface

uses
  ArtifactOS.Core.Runtime.Types;

type
  TRuntimeRepository = class
  public
    class function RegisterInstance(const AInstanceType, AInstanceName, AHostName: string;
      APid: Integer; const AAppVersion: string = ''; const AMetadataJson: string = '{}'): string;
    class function HeartbeatInstance(const AInstanceId: string;
      const AStatus: string = RuntimeInstanceStatusRunning): Integer;
    class function MarkInstanceStopped(const AInstanceId: string;
      const AStatus: string = RuntimeInstanceStatusStopped): Integer;
    class function CreateCommand(const ACommandType, ACommandLevel, ARequestedBy,
      ARequestedSource: string; const APayloadJson: string = '{}'; APriority: Integer = 100;
      const AIdempotencyKey: string = ''; AMaxRetries: Integer = 0;
      const AMetadataJson: string = '{}'): string;
    class function ClaimNextCommand(const AEngineInstanceId: string;
      ALeaseSeconds: Integer = 300): TRuntimeCommandInfo;
    // MarkCommandRunning: 中间态(claimed->running). 已带 status='claimed' guard, 竞态风险最低.
    // 059 complete_runtime_command 是终态专用, 中间态无 fencing 通道, 本函数仍为中间态主路径.
    class function MarkCommandRunning(const ACommandId, AEngineInstanceId: string;
      ALeaseSeconds: Integer = 300): Integer;
    class function ExtendCommandLease(const ACommandId, AEngineInstanceId: string;
      ALeaseSeconds: Integer = 300): Integer;
    // deprecated TD26-004-R: 终态回写应走 CompleteCommandWithFencing(带 fencing_token 强校验).
    // 本函数仅靠 claimed_by guard, lease 过期 re-claim 后旧 Worker 回写静默 0 行(不可观测).
    // 保留供回滚/降级, 新代码勿用. 下个迁移周期(migration 060)删除.
    class function MarkCommandSucceeded(const ACommandId, AEngineInstanceId: string;
      const AResultJson: string = '{}'): Integer;
    // deprecated TD26-004-R: 同 MarkCommandSucceeded, 走 CompleteCommandWithFencing(..'failed'..).
    class function MarkCommandFailed(const ACommandId, AEngineInstanceId, AErrorCode,
      AErrorMessage: string; const AResultJson: string = '{}'): Integer;
    // unused TD26-004-R: 无调用方. 已知缺陷: WHERE 只有 claimed_by 无 status guard,
    //   旧 Worker 持过期 lease 调用会成功覆盖新 Worker 的终态(语义破坏).
    //   未接线故无实际风险; 接线前必须先迁到带 fencing 的等价路径或补 status guard. 留 TD26-006.
    class function MarkCommandBlocked(const ACommandId, AEngineInstanceId, AErrorCode,
      AMessage: string; const AResultJson: string = '{}'): Integer;
    // unused TD26-004-R: 同 MarkCommandBlocked, 无 status guard 缺陷. 留 TD26-006.
    class function MarkCommandNeedsHuman(const ACommandId, AEngineInstanceId,
      AMessage: string; const AResultJson: string = '{}'): Integer;
    class function MarkExpiredCommands: Integer;
    class function GetCommand(const ACommandId: string): TRuntimeCommandInfo;
    // TD26-004: 带 fencing_token 强校验的统一完成函数(docs/29 §8).
    // 只有持有当前 fencing_token 的 Worker 能完成; 旧 Worker 持旧 token 被拒(防回写覆盖新结果).
    // 调用方应传 ClaimNextCommand 返回的 FencingToken. 旧 Mark* 系列为无 fencing 弱路径, 新代码应用本函数.
    class function CompleteCommandWithFencing(const ACommandId: string;
      AFencingToken: Int64; const ANewStatus: string;
      const AResultJson: string = '{}'; const AErrorCode: string = '';
      const AErrorMessage: string = ''): Integer;
  end;

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Common.JsonBuilder;

// JsonIntPair and JsonRawPair are Repository-specific helpers not in JsonBuilder:
// JsonIntPair produces "name":123 (unquoted integer)
// JsonRawPair produces "name":{...} (raw JSON, no quotes)

function JsonIntPair(const AName: string; AValue: Integer): string;
begin
  Result := '"' + AName + '":' + IntToStr(AValue);
end;

function JsonInt64Pair(const AName: string; AValue: Int64): string;
begin
  Result := '"' + AName + '":' + IntToStr(AValue);
end;

function JsonRawPair(const AName, AJson: string): string;
begin
  if AJson = '' then
    Result := '"' + AName + '":{}'
  else
    Result := '"' + AName + '":' + AJson;
end;

function FieldAsString(ATable: TFDMemTable; const AName: string): string;
begin
  if ATable.FindField(AName) = nil then
    Exit('');
  Result := ATable.FieldByName(AName).AsString;
end;

function FieldAsInteger(ATable: TFDMemTable; const AName: string): Integer;
begin
  if ATable.FindField(AName) = nil then
    Exit(0);
  Result := ATable.FieldByName(AName).AsInteger;
end;

function FieldAsInt64(ATable: TFDMemTable; const AName: string): Int64;
begin
  if ATable.FindField(AName) = nil then
    Exit(0);
  Result := ATable.FieldByName(AName).AsLargeInt;
end;

function MapCommand(ATable: TFDMemTable): TRuntimeCommandInfo;
begin
  Result.Id := FieldAsString(ATable, 'id');
  Result.CommandType := FieldAsString(ATable, 'command_type');
  Result.CommandLevel := FieldAsString(ATable, 'command_level');
  Result.RequestedBy := FieldAsString(ATable, 'requested_by');
  Result.RequestedSource := FieldAsString(ATable, 'requested_source');
  Result.Status := FieldAsString(ATable, 'status');
  Result.Priority := FieldAsInteger(ATable, 'priority');
  Result.PayloadJson := FieldAsString(ATable, 'payload');
  Result.IdempotencyKey := FieldAsString(ATable, 'idempotency_key');
  Result.ClaimedBy := FieldAsString(ATable, 'claimed_by');
  Result.ClaimedAt := FieldAsString(ATable, 'claimed_at');
  Result.LeaseUntil := FieldAsString(ATable, 'lease_until');
  Result.StartedAt := FieldAsString(ATable, 'started_at');
  Result.CompletedAt := FieldAsString(ATable, 'completed_at');
  Result.RetryCount := FieldAsInteger(ATable, 'retry_count');
  Result.MaxRetries := FieldAsInteger(ATable, 'max_retries');
  Result.ErrorCode := FieldAsString(ATable, 'error_code');
  Result.ErrorMessage := FieldAsString(ATable, 'error_message');
  Result.ResultJson := FieldAsString(ATable, 'result');
  Result.MetadataJson := FieldAsString(ATable, 'metadata');
  // TD26-004 统一信封字段
  Result.FencingToken := FieldAsInt64(ATable, 'fencing_token');
  Result.AttemptNo := FieldAsInteger(ATable, 'attempt_no');
  Result.CorrelationId := FieldAsString(ATable, 'correlation_id');
end;

function QueryFirstCommand(const ASQL, AParamsJson: string): TRuntimeCommandInfo;
var
  Table: TFDMemTable;
begin
  Result := Default(TRuntimeCommandInfo);
  Table := ArtifactOS_DB.QueryJson(ASQL, AParamsJson);
  try
    if not Table.IsEmpty then
    begin
      Table.First;
      Result := MapCommand(Table);
    end;
  finally
    Table.Free;
  end;
end;

class function TRuntimeRepository.RegisterInstance(const AInstanceType, AInstanceName,
  AHostName: string; APid: Integer; const AAppVersion, AMetadataJson: string): string;
const
  SQL = 'INSERT INTO artifactos.runtime_instance ' +
    '(instance_type, instance_name, host_name, pid, app_version, status, metadata) ' +
    'VALUES (:instance_type, :instance_name, :host_name, :pid, :app_version, ''running'', :metadata::jsonb) ' +
    'RETURNING id::text';
begin
  Result := ArtifactOS_DB.InsertAndReturnIdJson(SQL, MakeJsonObj([
    MakeJsonParam('instance_type', AInstanceType),
    MakeJsonParam('instance_name', AInstanceName),
    MakeJsonParam('host_name', AHostName),
    JsonIntPair('pid', APid),
    MakeJsonParam('app_version', AAppVersion),
    JsonRawPair('metadata', AMetadataJson)
  ]));
end;

class function TRuntimeRepository.HeartbeatInstance(const AInstanceId, AStatus: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_instance SET heartbeat_at=now(), status=:status ' +
    'WHERE id=:id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', AInstanceId),
    MakeJsonParam('status', AStatus)
  ]));
end;

class function TRuntimeRepository.MarkInstanceStopped(const AInstanceId, AStatus: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_instance SET status=:status, stopped_at=now(), heartbeat_at=now() ' +
    'WHERE id=:id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', AInstanceId),
    MakeJsonParam('status', AStatus)
  ]));
end;

class function TRuntimeRepository.CreateCommand(const ACommandType, ACommandLevel,
  ARequestedBy, ARequestedSource, APayloadJson: string; APriority: Integer;
  const AIdempotencyKey: string; AMaxRetries: Integer; const AMetadataJson: string): string;
const
  SQL = 'INSERT INTO artifactos.runtime_command ' +
    '(command_type, command_level, requested_by, requested_source, priority, payload, idempotency_key, max_retries, metadata) ' +
    'VALUES (:command_type, :command_level, :requested_by, :requested_source, :priority, :payload::jsonb, nullif(:idempotency_key, ''''), :max_retries, :metadata::jsonb) ' +
    'RETURNING id::text';
begin
  Result := ArtifactOS_DB.InsertAndReturnIdJson(SQL, MakeJsonObj([
    MakeJsonParam('command_type', ACommandType),
    MakeJsonParam('command_level', ACommandLevel),
    MakeJsonParam('requested_by', ARequestedBy),
    MakeJsonParam('requested_source', ARequestedSource),
    JsonIntPair('priority', APriority),
    JsonRawPair('payload', APayloadJson),
    MakeJsonParam('idempotency_key', AIdempotencyKey),
    JsonIntPair('max_retries', AMaxRetries),
    JsonRawPair('metadata', AMetadataJson)
  ]));
end;

class function TRuntimeRepository.ClaimNextCommand(const AEngineInstanceId: string;
  ALeaseSeconds: Integer): TRuntimeCommandInfo;
const
  SQL = 'SELECT * FROM artifactos.claim_next_runtime_command(:engine_instance_id::uuid, :lease_seconds)';
begin
  Result := QueryFirstCommand(SQL, MakeJsonObj([
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    JsonIntPair('lease_seconds', ALeaseSeconds)
  ]));
end;

class function TRuntimeRepository.MarkCommandRunning(const ACommandId,
  AEngineInstanceId: string; ALeaseSeconds: Integer): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET status=''running'', started_at=coalesce(started_at, now()), lease_until=now() + make_interval(secs => :lease_seconds) ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid AND status=''claimed''';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    JsonIntPair('lease_seconds', ALeaseSeconds)
  ]));
end;

class function TRuntimeRepository.ExtendCommandLease(const ACommandId,
  AEngineInstanceId: string; ALeaseSeconds: Integer): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET lease_until=now() + make_interval(secs => :lease_seconds) ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid AND status in (''claimed'', ''running'')';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    JsonIntPair('lease_seconds', ALeaseSeconds)
  ]));
end;

class function TRuntimeRepository.MarkCommandSucceeded(const ACommandId,
  AEngineInstanceId, AResultJson: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET status=''succeeded'', result=:result::jsonb, completed_at=now() ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    JsonRawPair('result', AResultJson)
  ]));
end;

class function TRuntimeRepository.MarkCommandFailed(const ACommandId, AEngineInstanceId,
  AErrorCode, AErrorMessage, AResultJson: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET status=''failed'', error_code=:error_code, error_message=:error_message, result=:result::jsonb, completed_at=now() ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    MakeJsonParam('error_code', AErrorCode),
    MakeJsonParam('error_message', AErrorMessage),
    JsonRawPair('result', AResultJson)
  ]));
end;

class function TRuntimeRepository.MarkCommandBlocked(const ACommandId, AEngineInstanceId,
  AErrorCode, AMessage, AResultJson: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET status=''blocked'', error_code=:error_code, error_message=:message, result=:result::jsonb, completed_at=now() ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    MakeJsonParam('error_code', AErrorCode),
    MakeJsonParam('message', AMessage),
    JsonRawPair('result', AResultJson)
  ]));
end;

class function TRuntimeRepository.MarkCommandNeedsHuman(const ACommandId,
  AEngineInstanceId, AMessage, AResultJson: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_command ' +
    'SET status=''needs_human'', error_message=:message, result=:result::jsonb, completed_at=now() ' +
    'WHERE id=:id::uuid AND claimed_by=:engine_instance_id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    MakeJsonParam('engine_instance_id', AEngineInstanceId),
    MakeJsonParam('message', AMessage),
    JsonRawPair('result', AResultJson)
  ]));
end;

class function TRuntimeRepository.MarkExpiredCommands: Integer;
const
  SQL = 'SELECT artifactos.mark_expired_runtime_commands()::text';
begin
  Result := StrToIntDef(ArtifactOS_DB.ExecuteScalarJson(SQL, ''), 0);
end;

class function TRuntimeRepository.GetCommand(const ACommandId: string): TRuntimeCommandInfo;
const
  SQL = 'SELECT * FROM artifactos.runtime_command WHERE id=:id::uuid LIMIT 1';
begin
  Result := QueryFirstCommand(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId)
  ]));
end;

class function TRuntimeRepository.CompleteCommandWithFencing(const ACommandId: string;
  AFencingToken: Int64; const ANewStatus: string;
  const AResultJson: string = '{}'; const AErrorCode: string = '';
  const AErrorMessage: string = ''): Integer;
const
  SQL = 'SELECT artifactos.complete_runtime_command(:id::uuid, :fencing_token, :new_status, :result::jsonb, :error_code, :error_message)::text';
begin
  Result := StrToIntDef(ArtifactOS_DB.ExecuteScalarJson(SQL, MakeJsonObj([
    MakeJsonParam('id', ACommandId),
    JsonInt64Pair('fencing_token', AFencingToken),
    MakeJsonParam('new_status', ANewStatus),
    MakeJsonParam('error_code', AErrorCode),
    MakeJsonParam('error_message', AErrorMessage),
    JsonRawPair('result', AResultJson)
  ])), 0);
end;

end.
