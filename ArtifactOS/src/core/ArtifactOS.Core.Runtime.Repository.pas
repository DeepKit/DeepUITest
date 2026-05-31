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
    class function MarkCommandRunning(const ACommandId, AEngineInstanceId: string;
      ALeaseSeconds: Integer = 300): Integer;
    class function ExtendCommandLease(const ACommandId, AEngineInstanceId: string;
      ALeaseSeconds: Integer = 300): Integer;
    class function MarkCommandSucceeded(const ACommandId, AEngineInstanceId: string;
      const AResultJson: string = '{}'): Integer;
    class function MarkCommandFailed(const ACommandId, AEngineInstanceId, AErrorCode,
      AErrorMessage: string; const AResultJson: string = '{}'): Integer;
    class function MarkCommandBlocked(const ACommandId, AEngineInstanceId, AErrorCode,
      AMessage: string; const AResultJson: string = '{}'): Integer;
    class function MarkCommandNeedsHuman(const ACommandId, AEngineInstanceId,
      AMessage: string; const AResultJson: string = '{}'): Integer;
    class function MarkExpiredCommands: Integer;
    class function GetCommand(const ACommandId: string): TRuntimeCommandInfo;
  end;

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  ArtifactOS.Core.DB.Connection;

function JsonEscape(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n');
end;

function JsonPair(const AName, AValue: string): string;
begin
  Result := '"' + AName + '":"' + JsonEscape(AValue) + '"';
end;

function JsonIntPair(const AName: string; AValue: Integer): string;
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

function JsonObject(const APairs: array of string): string;
var
  I: Integer;
begin
  Result := '{';
  for I := Low(APairs) to High(APairs) do
  begin
    if I > Low(APairs) then
      Result := Result + ',';
    Result := Result + APairs[I];
  end;
  Result := Result + '}';
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
  Result := ArtifactOS_DB.InsertAndReturnIdJson(SQL, JsonObject([
    JsonPair('instance_type', AInstanceType),
    JsonPair('instance_name', AInstanceName),
    JsonPair('host_name', AHostName),
    JsonIntPair('pid', APid),
    JsonPair('app_version', AAppVersion),
    JsonRawPair('metadata', AMetadataJson)
  ]));
end;

class function TRuntimeRepository.HeartbeatInstance(const AInstanceId, AStatus: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_instance SET heartbeat_at=now(), status=:status ' +
    'WHERE id=:id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', AInstanceId),
    JsonPair('status', AStatus)
  ]));
end;

class function TRuntimeRepository.MarkInstanceStopped(const AInstanceId, AStatus: string): Integer;
const
  SQL = 'UPDATE artifactos.runtime_instance SET status=:status, stopped_at=now(), heartbeat_at=now() ' +
    'WHERE id=:id::uuid';
begin
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', AInstanceId),
    JsonPair('status', AStatus)
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
  Result := ArtifactOS_DB.InsertAndReturnIdJson(SQL, JsonObject([
    JsonPair('command_type', ACommandType),
    JsonPair('command_level', ACommandLevel),
    JsonPair('requested_by', ARequestedBy),
    JsonPair('requested_source', ARequestedSource),
    JsonIntPair('priority', APriority),
    JsonRawPair('payload', APayloadJson),
    JsonPair('idempotency_key', AIdempotencyKey),
    JsonIntPair('max_retries', AMaxRetries),
    JsonRawPair('metadata', AMetadataJson)
  ]));
end;

class function TRuntimeRepository.ClaimNextCommand(const AEngineInstanceId: string;
  ALeaseSeconds: Integer): TRuntimeCommandInfo;
const
  SQL = 'SELECT * FROM artifactos.claim_next_runtime_command(:engine_instance_id::uuid, :lease_seconds)';
begin
  Result := QueryFirstCommand(SQL, JsonObject([
    JsonPair('engine_instance_id', AEngineInstanceId),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
    JsonPair('error_code', AErrorCode),
    JsonPair('error_message', AErrorMessage),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
    JsonPair('error_code', AErrorCode),
    JsonPair('message', AMessage),
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
  Result := ArtifactOS_DB.ExecuteJson(SQL, JsonObject([
    JsonPair('id', ACommandId),
    JsonPair('engine_instance_id', AEngineInstanceId),
    JsonPair('message', AMessage),
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
  Result := QueryFirstCommand(SQL, JsonObject([
    JsonPair('id', ACommandId)
  ]));
end;

end.
