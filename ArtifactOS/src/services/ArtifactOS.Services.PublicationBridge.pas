unit ArtifactOS.Services.PublicationBridge;

// L3-68: PublicationBridge — bridges ArtifactOS auto-publish to media_publish.
// Creates a media_publish task contract in PG for the PublishingRuntime to pick up.
// ArtifactOS never calls media_publish directly; it writes intent to PG.

interface

uses
  System.SysUtils, System.JSON, System.DateUtils,
  ArtifactOS.Core.DB.Connection;

type
  TPublishContract = record
    TaskId: string;
    PackageId: string;
    Platform: string;
    AccountId: string;
    Mode: string;        // auto_publish | manual_review | draft_only | dry_run
    Status: string;      // pending | submitted | published | failed
  end;

  TPublicationBridge = class
  public
    /// <summary>
    /// Create a media_publish task contract from a publication package.
    /// Returns the task_id for tracking.
    /// </summary>
    class function CreatePublishTask(const APackageId: string;
      out AContract: TPublishContract): Boolean;

    /// <summary>
    /// Check the status of a publish task.
    /// Returns the current status string from media_publish contract.
    /// </summary>
    class function CheckTaskStatus(const ATaskId: string): string;

    /// <summary>
    /// Full auto-publish flow: build real package + create task.
    /// Called when StrategyRuling returns auto_publish.
    /// </summary>
    class function AutoPublish(const AArtifactId, AVersionId,
      ASnapshotId, APlatform, AAccountId: string;
      out AContract: TPublishContract): Boolean;
  end;

implementation

{ TPublicationBridge }

class function TPublicationBridge.CreatePublishTask(const APackageId: string;
  out AContract: TPublishContract): Boolean;
var
  DB: TArtifactDB;
  PackageInfo: string;
  JObj: TJSONObject;
  TaskId: string;
begin
  Result := False;
  AContract.TaskId := '';
  AContract.PackageId := APackageId;
  AContract.Status := 'error';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Read package info
    PackageInfo := DB.ExecuteScalarJson(
      'SELECT platform, account_id, run_mode, status FROM artifactos.publication_package WHERE id=:id',
      '{"id":"' + APackageId + '"}');

    if PackageInfo = '' then
    begin
      WriteLn(ErrOutput, '[PubBridge] Package not found: ', APackageId);
      Exit;
    end;

    JObj := TJSONObject.ParseJSONValue(PackageInfo) as TJSONObject;
    if JObj <> nil then
    try
      AContract.Platform := JObj.GetValue<string>('platform', '');
      AContract.AccountId := JObj.GetValue<string>('account_id', '');
      AContract.Mode := JObj.GetValue<string>('run_mode', 'auto_publish');
    finally
      JObj.Free;
    end;

    // Create media_publish task contract
    // media_publish reads from this table to pick up pending tasks
    TaskId := DB.InsertAndReturnId(
      'INSERT INTO media_publish.publish_task (' +
      '  id, publication_package_id, platform_id, account_id, ' +
      '  mode, idempotency_key, status, created_at' +
      ') VALUES (' +
      '  gen_random_uuid(), ''' + APackageId + ''', ''' + AContract.Platform + ''', ''' + AContract.AccountId + ''', ' +
      '  ''' + AContract.Mode + ''', ' +
      '  ''task_' + APackageId + '_' + AContract.Platform + ''', ' +
      '  ''pending'', now()' +
      ') RETURNING id::text');

    AContract.TaskId := TaskId;
    AContract.Status := 'pending';

    // Update publication_package status
    DB.ExecuteJson(
      'UPDATE artifactos.publication_package SET status=''submitted'', metadata=jsonb_set(' +
      '  COALESCE(metadata, ''{}''::jsonb), ''{publish_task_id}'', ''"' + TaskId + '"'') ' +
      'WHERE id=:id',
      '{"id":"' + APackageId + '"}');

    WriteLn(Format('[PubBridge] Task created: id=%s platform=%s mode=%s',
      [TaskId, AContract.Platform, AContract.Mode]));
    Result := True;

  finally
    DB.Disconnect;
  end;
end;

class function TPublicationBridge.CheckTaskStatus(const ATaskId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT status FROM media_publish.publish_task WHERE id=''' + ATaskId + '''');
    if Result = '' then
      Result := 'not_found';
  finally
    DB.Disconnect;
  end;
end;

class function TPublicationBridge.AutoPublish(const AArtifactId, AVersionId,
  ASnapshotId, APlatform, AAccountId: string;
  out AContract: TPublishContract): Boolean;
var
  PackageId: string;
begin
  Result := False;

  // Step 1: Build real (non-simulation) publication package
  WriteLn(Format('[PubBridge] Auto-publish: artifact=%s version=%s platform=%s',
    [AArtifactId, AVersionId, APlatform]));

  // Import PackageBuilder inline to avoid circular dependency
  // Use direct DB insert instead
  var DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Verify snapshot
    var SnapshotStatus := DB.ExecuteScalar(
      'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + ASnapshotId + '''');
    if SnapshotStatus <> 'qualified' then
    begin
      WriteLn(ErrOutput, '[PubBridge] Snapshot not qualified: ', ASnapshotId);
      Exit;
    end;

    // Read artifact content for publishing
    var VersionPayload := DB.ExecuteScalarJson(
      'SELECT assembled_payload::text FROM artifactos.artifact_version WHERE id=:id::uuid',
      '{"id":"' + AVersionId + '"}');

    var JObj := TJSONObject.ParseJSONValue(VersionPayload) as TJSONObject;
    var Title, Body: string;
    if JObj <> nil then
    try
      Title := JObj.GetValue<string>('title', '');
      Body := JObj.GetValue<string>('body', '');
    finally
      JObj.Free;
    end;

    // Create publication package (real, not simulated)
    var IdemKey := 'pub_' + AArtifactId + '_' + APlatform + '_' + IntToStr(DateTimeToUnix(Now));
    PackageId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, ' +
      'platform, account_id, idempotency_key, simulation_only, run_mode, status) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AVersionId + ''', ''' + ASnapshotId + ''', ' +
      '''' + APlatform + ''', ''' + AAccountId + ''', ''' + IdemKey + ''', false, ''auto_publish'', ''pending'') ' +
      'RETURNING id');

    WriteLn('[PubBridge] Package created: ', PackageId);

    // Create media_publish task
    var TaskId := DB.InsertAndReturnId(
      'INSERT INTO media_publish.publish_task (' +
      '  id, publication_package_id, platform_id, account_id, ' +
      '  mode, title, body_md, idempotency_key, status, created_at' +
      ') VALUES (' +
      '  gen_random_uuid(), ''' + PackageId + ''', ''' + APlatform + ''', ''' + AAccountId + ''', ' +
      '  ''auto_publish'', ' +
      '  $tag$' + Title + '$tag$, $tag$' + Body + '$tag$, ' +
      '  ''task_' + PackageId + '_' + APlatform + ''', ' +
      '  ''pending'', now()' +
      ') RETURNING id::text');

    // Update package with task reference
    DB.ExecuteJson(
      'UPDATE artifactos.publication_package SET status=''submitted'', metadata=jsonb_set(' +
      '  COALESCE(metadata, ''{}''::jsonb), ''{publish_task_id}'', ''"' + TaskId + '"'') ' +
      'WHERE id=:id',
      '{"id":"' + PackageId + '"}');

    AContract.TaskId := TaskId;
    AContract.PackageId := PackageId;
    AContract.Platform := APlatform;
    AContract.AccountId := AAccountId;
    AContract.Mode := 'auto_publish';
    AContract.Status := 'pending';

    WriteLn(Format('[PubBridge] Auto-publish complete: task=%s package=%s', [TaskId, PackageId]));
    Result := True;

  finally
    DB.Disconnect;
  end;
end;

end.
