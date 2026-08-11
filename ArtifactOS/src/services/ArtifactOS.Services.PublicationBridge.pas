unit ArtifactOS.Services.PublicationBridge;

// L3-68 + N9.4 + N10.1b: PublicationBridge — bridges ArtifactOS auto-publish to media_publish.
// Creates a media_publish task contract in PG for the PublishingRuntime to pick up.
// ArtifactOS never calls media_publish directly; it writes intent to PG.
//
// N9.4: Uses PlatformAdapter for per-platform content validation and formatting.
// N10.1b: All SQL rewritten to parameterized ExecuteJson/InsertAndReturnIdJson.
//         $tag$ dollar-quoting replaced with proper parameter binding.
// N10.2d: Multi-statement sequences wrapped in transactions.

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.PlatformAdapter;

type
  TPublishContract = record
    TaskId: string;
    PackageId: string;
    Platform: string;
    AccountId: string;
    Mode: string;
    Status: string;
    Warnings: TArray<string>;
  end;

  { AP-P0: Publish-scope runtime parameters. The platform whitelist is the
    hard gate: any platform not in AllowedPlatforms is refused at task
    creation time — no package row, no browser, no credential access.
    Default production whitelist is xiaohongshu only; other built-in
    adapters (zhihu/weibo/wechat_public) stay disabled until verified. }
  TPublishRunMode = (prmBrowserAssisted, prmSimulation);
  TPublishRunConfig = record
    AllowedPlatforms: TArray<string>;
    RunMode: TPublishRunMode;
    AccountStage: string;          // 'new' | 'mature'
    MaxPostsPerRun: Integer;       // 0 = unlimited
    RequireHumanOnChallenge: Boolean;
    class function Default: TPublishRunConfig; static;
    function IsPlatformAllowed(const APlatform: string): Boolean;
  end;

  TPublicationBridge = class
  private
    class var FConfig: TPublishRunConfig;
    class var FConfigLock: TObject;
    class constructor Create;
    class destructor Destroy;
  public
    class function GetRunConfig: TPublishRunConfig; static;
    class procedure SetRunConfig(const AConfig: TPublishRunConfig); static;
    class function ConfigureFromArgs(const AArgv: TArray<string>): TPublishRunConfig; static;
    class function CreatePublishTask(const APackageId: string;
      out AContract: TPublishContract): Boolean;
    class function CheckTaskStatus(const ATaskId: string): string;
    class function AutoPublish(const AArtifactId, AVersionId,
      ASnapshotId, APlatform, AAccountId: string;
      out AContract: TPublishContract): Boolean;
    class function AutoPublishAll(const AArtifactId, AVersionId,
      ASnapshotId, AAccountId: string;
      out AContracts: TArray<TPublishContract>): Boolean;
    class function ValidateForPlatform(const ATitle, ABody,
      APlatform: string; out AWarnings: TArray<string>): Boolean;
    class function FormatForPlatform(const ATitle, ABody,
      APlatform: string; out AFormattedTitle, AFormattedBody: string): Boolean;
  end;

implementation

uses
  System.JSON, System.SyncObjs,
  ArtifactOS.Core.Common.JsonBuilder;

{ TPublicationBridge — public API }

{ TPublishRunConfig }

class function TPublishRunConfig.Default: TPublishRunConfig;
begin
  // AP-P0: production default whitelist is xiaohongshu only.
  // zhihu/weibo/wechat_public adapters remain disabled until verified.
  SetLength(Result.AllowedPlatforms, 1);
  Result.AllowedPlatforms[0] := 'xiaohongshu';
  Result.RunMode := prmBrowserAssisted;
  Result.AccountStage := 'new';
  Result.MaxPostsPerRun := 1;
  Result.RequireHumanOnChallenge := True;
end;

function TPublishRunConfig.IsPlatformAllowed(const APlatform: string): Boolean;
var
  P: string;
begin
  Result := False;
  for P in AllowedPlatforms do
    if SameText(P, APlatform) then Exit(True);
end;

{ TPublicationBridge config lifecycle }

class constructor TPublicationBridge.Create;
begin
  FConfig := TPublishRunConfig.Default;
  FConfigLock := TObject.Create;
end;

class destructor TPublicationBridge.Destroy;
begin
  FConfigLock.Free;
end;

class function TPublicationBridge.GetRunConfig: TPublishRunConfig;
begin
  TMonitor.Enter(FConfigLock);
  try
    Result := FConfig;
  finally
    TMonitor.Exit(FConfigLock);
  end;
end;

class procedure TPublicationBridge.SetRunConfig(const AConfig: TPublishRunConfig);
begin
  TMonitor.Enter(FConfigLock);
  try
    FConfig := AConfig;
  finally
    TMonitor.Exit(FConfigLock);
  end;
end;

class function TPublicationBridge.ConfigureFromArgs(
  const AArgv: TArray<string>): TPublishRunConfig;
var
  I: Integer;
  Arg, Key, Val: string;
  EqPos: Integer;
  List: TArray<string>;
  P: string;
begin
  Result := TPublishRunConfig.Default;
  for I := 0 to High(AArgv) do
  begin
    Arg := Trim(AArgv[I]);
    if (Arg = '') or (Arg[1] <> '-') then Continue;
    EqPos := Pos('=', Arg);
    if EqPos = 0 then Continue;
    Key := LowerCase(Trim(Copy(Arg, 1, EqPos - 1)));
    Val := Trim(Copy(Arg, EqPos + 1, MaxInt));

    if Key = '--platforms' then
    begin
      SetLength(List, 0);
      for P in Val.Split([',']) do
      begin
        var T := Trim(P);
        if T <> '' then
        begin
          SetLength(List, Length(List) + 1);
          List[High(List)] := T;
        end;
      end;
      if Length(List) > 0 then
        Result.AllowedPlatforms := List
      else
        Result.AllowedPlatforms := TPublishRunConfig.Default.AllowedPlatforms;
    end
    else if Key = '--publish-mode' then
    begin
      if SameText(Val, 'simulation') then
        Result.RunMode := prmSimulation
      else
        Result.RunMode := prmBrowserAssisted;
    end
    else if Key = '--account-stage' then
      Result.AccountStage := Val
    else if Key = '--max-posts-per-run' then
      Result.MaxPostsPerRun := StrToIntDef(Val, 1)
    else if Key = '--require-human-on-challenge' then
      Result.RequireHumanOnChallenge := SameText(Val, 'true') or (Val = '1');
  end;
end;

class function TPublicationBridge.CreatePublishTask(const APackageId: string;
  out AContract: TPublishContract): Boolean;
var
  DB: TArtifactDB;
  PackageInfo: string;
  JObj: TJSONObject;
  TaskId: string;
  Adapter: IPlatformAdapter;
  Title, Body, FormattedTitle, FormattedBody: string;
  WarningsJson: string;
begin
  Result := False;
  AContract.TaskId := '';
  AContract.PackageId := APackageId;
  AContract.Status := 'error';
  SetLength(AContract.Warnings, 0);

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // N10.1b: parameterized query
    PackageInfo := DB.ExecuteScalarJson(
      'SELECT pp.platform, pp.account_id, pp.run_mode, pp.status, ' +
      'av.assembled_payload::text ' +
      'FROM artifactos.publication_package pp ' +
      'JOIN artifactos.artifact_version av ON av.id = pp.artifact_version_id ' +
      'WHERE pp.id=:id::uuid',
      MakeJsonObj([MakeJsonParam('id', APackageId)]));

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
      Title := JObj.GetValue<string>('assembled_payload.title', '');
      Body := JObj.GetValue<string>('assembled_payload.body', '');
    finally
      JObj.Free;
    end;

    // N9.4: Use platform adapter to format content
    Adapter := TPlatformAdapterRegistry.Get(AContract.Platform);
    if Adapter <> nil then
    begin
      FormattedTitle := Adapter.FormatTitle(Title);
      FormattedBody := Adapter.FormatBody(Body);

      var VTitle := Adapter.ValidateTitle(FormattedTitle);
      var VBody := Adapter.ValidateBody(FormattedBody);
      var AllIssues: TList<string> := TList<string>.Create;
      try
        for var S in VTitle.Issues do AllIssues.Add(S);
        for var S in VBody.Issues do AllIssues.Add(S);
        for var S in VTitle.SuggestedFixes do AllIssues.Add('[fix] ' + S);
        for var S in VBody.SuggestedFixes do AllIssues.Add('[fix] ' + S);
        AContract.Warnings := AllIssues.ToArray;
      finally
        AllIssues.Free;
      end;
    end
    else
    begin
      FormattedTitle := Title;
      FormattedBody := Body;
      SetLength(AContract.Warnings, 1);
      AContract.Warnings[0] := 'No PlatformAdapter for: ' + AContract.Platform;
    end;

    // Build warnings JSON array
    WarningsJson := '[]';
    if Length(AContract.Warnings) > 0 then
    begin
      WarningsJson := '[';
      for var I := 0 to High(AContract.Warnings) do
      begin
        if I > 0 then WarningsJson := WarningsJson + ',';
        WarningsJson := WarningsJson + '"' + AContract.Warnings[I].Replace('"', '\"') + '"';
      end;
      WarningsJson := WarningsJson + ']';
    end;

    // N10.1b + N10.2d: parameterized INSERT + UPDATE in transaction
    DB.Connect; // ensure connected for transaction
    var Conn := DB.Connection;
    Conn.StartTransaction;
    try
      var IdemKey := 'task_' + APackageId + '_' + AContract.Platform;

      TaskId := DB.InsertAndReturnIdJson(
        'INSERT INTO media_publish.publish_task (' +
        '  id, publication_package_id, platform_id, account_id, ' +
        '  mode, title, body_md, idempotency_key, status, created_at' +
        ') VALUES (' +
        '  gen_random_uuid(), :pid::uuid, :platform, :aid, ' +
        '  :mode, :title, :body, :ikey, ''pending'', now()' +
        ') RETURNING id::text',
        MakeJsonObj([
          MakeJsonParam('pid', APackageId),
          MakeJsonParam('platform', AContract.Platform),
          MakeJsonParam('aid', AContract.AccountId),
          MakeJsonParam('mode', AContract.Mode),
          MakeJsonParam('title', FormattedTitle),
          MakeJsonParam('body', FormattedBody),
          MakeJsonParam('ikey', IdemKey)
        ]));

      DB.ExecuteJson(
        'UPDATE artifactos.publication_package SET status=''submitted'', ' +
        'metadata = COALESCE(metadata, ''{}''::jsonb) || ' +
        'jsonb_build_object(''publish_task_id'', :tid, ' +
        '  ''platform_warnings'', :warnings::jsonb) ' +
        'WHERE id=:pid::uuid',
        MakeJsonObj([
          MakeJsonParam('tid', TaskId),
          MakeJsonParam('warnings', WarningsJson),
          MakeJsonParam('pid', APackageId)
        ]));

      Conn.Commit;

      AContract.TaskId := TaskId;
      AContract.Status := 'pending';

      WriteLn(Format('[PubBridge] Task %s -> platform=%s mode=%s warnings=%d',
        [TaskId, AContract.Platform, AContract.Mode, Length(AContract.Warnings)]));

      if Length(AContract.Warnings) > 0 then
        for var I := 0 to High(AContract.Warnings) do
          WriteLn(Format('[PubBridge]   W %s', [AContract.Warnings[I]]));

      Result := True;
    except
      Conn.Rollback;
      raise;
    end;

  finally
    DB.Disconnect;
  end;
end;

class function TPublicationBridge.CheckTaskStatus(const ATaskId: string): string;
begin
  Result := ArtifactOS_DB.ExecuteScalarJson(
    'SELECT status FROM media_publish.publish_task WHERE id=:id::uuid',
    MakeJsonObj([MakeJsonParam('id', ATaskId)]));
  if Result = '' then
    Result := 'not_found';
end;

class function TPublicationBridge.AutoPublish(const AArtifactId, AVersionId,
  ASnapshotId, APlatform, AAccountId: string;
  out AContract: TPublishContract): Boolean;
var
  DB: TArtifactDB;
  Adapter: IPlatformAdapter;
  Title, Body, FormattedTitle, FormattedBody: string;
  JObj: TJSONObject;
  PackageId, TaskId: string;
  WarnList: TList<string>;
begin
  Result := False;

  WriteLn(Format('[PubBridge] Auto-publish: artifact=%s version=%s platform=%s',
    [AArtifactId, AVersionId, APlatform]));

  Adapter := TPlatformAdapterRegistry.Get(APlatform);
  if Adapter = nil then
  begin
    WriteLn(ErrOutput, Format('[PubBridge] Unknown platform: %s. Available: %s',
      [APlatform, string.Join(', ', TPlatformAdapterRegistry.GetPlatformIds)]));
    Exit;
  end;

  // AP-P0: hard platform whitelist gate. A platform not in the active
  // run config may NOT create a publication task, launch a browser, or
  // touch account credentials — refuse before any DB write here.
  if not GetRunConfig.IsPlatformAllowed(APlatform) then
  begin
    WriteLn(ErrOutput, Format('[PubBridge] Platform %s not in allowed whitelist ' +
      '(%s). No task created, no browser/credential access.',
      [APlatform, string.Join(', ', GetRunConfig.AllowedPlatforms)]));
    Exit;
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // N10.1b: parameterized
    var SnapshotStatus := DB.ExecuteScalarJson(
      'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=:id::uuid',
      MakeJsonObj([MakeJsonParam('id', ASnapshotId)]));
    if SnapshotStatus <> 'qualified' then
    begin
      WriteLn(ErrOutput, '[PubBridge] Snapshot not qualified: ', ASnapshotId);
      Exit;
    end;

    var VersionPayload := DB.ExecuteScalarJson(
      'SELECT assembled_payload::text FROM artifactos.artifact_version WHERE id=:id::uuid',
      MakeJsonObj([MakeJsonParam('id', AVersionId)]));

    JObj := TJSONObject.ParseJSONValue(VersionPayload) as TJSONObject;
    if JObj <> nil then
    try
      Title := JObj.GetValue<string>('title', '');
      Body := JObj.GetValue<string>('body', '');
    finally
      JObj.Free;
    end;

    FormattedTitle := Adapter.FormatTitle(Title);
    FormattedBody := Adapter.FormatBody(Body);

    var VTitle := Adapter.ValidateTitle(FormattedTitle);
    var VBody := Adapter.ValidateBody(FormattedBody);
    WarnList := TList<string>.Create;
    try
      for var S in VTitle.Issues do WarnList.Add(S);
      for var S in VBody.Issues do WarnList.Add(S);

      var IdemKey := Adapter.MakeIdempotencyKey(AArtifactId);

      // N10.2d: transaction wrapper
      var Conn := DB.Connection;
      Conn.StartTransaction;
      try
        // Create publication package
        PackageId := DB.InsertAndReturnIdJson(
          'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, ' +
          'quality_snapshot_id, platform, account_id, idempotency_key, ' +
          'simulation_only, run_mode, status) ' +
          'VALUES (:aid::uuid, :vid::uuid, :sid::uuid, :platform, :acct, :ikey, ' +
          'false, ''auto_publish'', ''pending'') RETURNING id::text',
          MakeJsonObj([
            MakeJsonParam('aid', AArtifactId),
            MakeJsonParam('vid', AVersionId),
            MakeJsonParam('sid', ASnapshotId),
            MakeJsonParam('platform', APlatform),
            MakeJsonParam('acct', AAccountId),
            MakeJsonParam('ikey', IdemKey)
          ]));

        WriteLn('[PubBridge] Package created: ', PackageId);

        // Build warnings JSON
        var WarningsJson: string := '[]';
        if WarnList.Count > 0 then
        begin
          WarningsJson := '[';
          for var I := 0 to WarnList.Count - 1 do
          begin
            if I > 0 then WarningsJson := WarningsJson + ',';
            WarningsJson := WarningsJson + '"' + WarnList[I].Replace('"', '\"') + '"';
          end;
          WarningsJson := WarningsJson + ']';
        end;

        // Create media_publish task
        var TaskIKey := 'task_' + PackageId + '_' + APlatform;
        TaskId := DB.InsertAndReturnIdJson(
          'INSERT INTO media_publish.publish_task (' +
          '  id, publication_package_id, platform_id, account_id, ' +
          '  mode, title, body_md, idempotency_key, status, created_at' +
          ') VALUES (' +
          '  gen_random_uuid(), :pid::uuid, :platform, :acct, ' +
          '  ''auto_publish'', :title, :body, :ikey, ''pending'', now()' +
          ') RETURNING id::text',
          MakeJsonObj([
            MakeJsonParam('pid', PackageId),
            MakeJsonParam('platform', APlatform),
            MakeJsonParam('acct', AAccountId),
            MakeJsonParam('title', FormattedTitle),
            MakeJsonParam('body', FormattedBody),
            MakeJsonParam('ikey', TaskIKey)
          ]));

        // Update package with task reference
        DB.ExecuteJson(
          'UPDATE artifactos.publication_package SET status=''submitted'', ' +
          'metadata = COALESCE(metadata, ''{}''::jsonb) || ' +
          'jsonb_build_object(''publish_task_id'', :tid, ' +
          '  ''platform_warnings'', :warnings::jsonb) ' +
          'WHERE id=:pid::uuid',
          MakeJsonObj([
            MakeJsonParam('tid', TaskId),
            MakeJsonParam('warnings', WarningsJson),
            MakeJsonParam('pid', PackageId)
          ]));

        Conn.Commit;

        AContract.TaskId := TaskId;
        AContract.PackageId := PackageId;
        AContract.Platform := APlatform;
        AContract.AccountId := AAccountId;
        AContract.Mode := 'auto_publish';
        AContract.Status := 'pending';
        AContract.Warnings := WarnList.ToArray;

        WriteLn(Format('[PubBridge] Auto-publish: task=%s package=%s warnings=%d',
          [TaskId, PackageId, Length(AContract.Warnings)]));

        if Length(AContract.Warnings) > 0 then
          for var I := 0 to High(AContract.Warnings) do
            WriteLn(Format('[PubBridge]   W %s', [AContract.Warnings[I]]));

        Result := True;

      except
        Conn.Rollback;
        raise;
      end;

    finally
      WarnList.Free;
    end;

  finally
    DB.Disconnect;
  end;
end;

class function TPublicationBridge.AutoPublishAll(const AArtifactId, AVersionId,
  ASnapshotId, AAccountId: string;
  out AContracts: TArray<TPublishContract>): Boolean;
var
  Registered, Allowed: TArray<string>;
  ContractList: TList<TPublishContract>;
  Contract: TPublishContract;
  AllOk: Boolean;
  Cfg: TPublishRunConfig;
  Published: Integer;
  P, AP: string;
  IsAllowed: Boolean;
begin
  // AP-P0: iterate the registered adapters (keeps multi-platform
  // extensibility — not hardcoded to xiaohongshu), but only create
  // tasks for platforms in the active whitelist. Skipped platforms get
  // zero side effects (no task row, no browser, no credentials).
  Registered := TPlatformAdapterRegistry.GetPlatformIds;
  Cfg := GetRunConfig;
  SetLength(Allowed, 0);
  for P in Registered do
  begin
    IsAllowed := False;
    for AP in Cfg.AllowedPlatforms do
      if SameText(AP, P) then begin IsAllowed := True; Break; end;
    if IsAllowed then
    begin
      SetLength(Allowed, Length(Allowed) + 1);
      Allowed[High(Allowed)] := P;
    end
    else
      WriteLn(Format('[PubBridge] AutoPublishAll: skipping %s (not in whitelist %s)',
        [P, string.Join(', ', Cfg.AllowedPlatforms)]));
  end;

  ContractList := TList<TPublishContract>.Create;
  AllOk := True;
  Published := 0;
  try
    for P in Allowed do
    begin
      // AP-P0: respect MaxPostsPerRun cap (0 = unlimited)
      if (Cfg.MaxPostsPerRun > 0) and (Published >= Cfg.MaxPostsPerRun) then
      begin
        WriteLn(Format('[PubBridge] AutoPublishAll: MaxPostsPerRun=%d reached, stopping',
          [Cfg.MaxPostsPerRun]));
        Break;
      end;
      try
        if AutoPublish(AArtifactId, AVersionId, ASnapshotId, P, AAccountId, Contract) then
        begin
          ContractList.Add(Contract);
          Inc(Published);
        end
        else
        begin
          AllOk := False;
          WriteLn(ErrOutput, Format('[PubBridge] AutoPublishAll: failed for platform=%s', [P]));
        end;
      except
        on E: Exception do
        begin
          AllOk := False;
          WriteLn(ErrOutput, Format('[PubBridge] AutoPublishAll: exception for %s: %s', [P, E.Message]));
        end;
      end;
    end;
    AContracts := ContractList.ToArray;
    Result := AllOk and (Length(AContracts) > 0);
    WriteLn(Format('[PubBridge] AutoPublishAll: %d/%d allowed platforms published (%d registered)',
      [Length(AContracts), Length(Allowed), Length(Registered)]));
  finally
    ContractList.Free;
  end;
end;

class function TPublicationBridge.ValidateForPlatform(const ATitle, ABody,
  APlatform: string; out AWarnings: TArray<string>): Boolean;
var
  Adapter: IPlatformAdapter;
  WarnList: TList<string>;
begin
  SetLength(AWarnings, 0);
  Adapter := TPlatformAdapterRegistry.Get(APlatform);
  if Adapter = nil then
  begin
    SetLength(AWarnings, 1);
    AWarnings[0] := 'Unknown platform: ' + APlatform;
    Exit(False);
  end;

  var VTitle := Adapter.ValidateTitle(ATitle);
  var VBody := Adapter.ValidateBody(ABody);

  WarnList := TList<string>.Create;
  try
    for var S in VTitle.Issues do WarnList.Add(S);
    for var S in VBody.Issues do WarnList.Add(S);
    for var S in VTitle.SuggestedFixes do WarnList.Add('[suggest] ' + S);
    for var S in VBody.SuggestedFixes do WarnList.Add('[suggest] ' + S);
    AWarnings := WarnList.ToArray;
    Result := VTitle.IsValid and VBody.IsValid;
  finally
    WarnList.Free;
  end;
end;

class function TPublicationBridge.FormatForPlatform(const ATitle, ABody,
  APlatform: string; out AFormattedTitle, AFormattedBody: string): Boolean;
var
  Adapter: IPlatformAdapter;
begin
  Adapter := TPlatformAdapterRegistry.Get(APlatform);
  if Adapter = nil then
  begin
    AFormattedTitle := ATitle;
    AFormattedBody := ABody;
    Exit(False);
  end;

  AFormattedTitle := Adapter.FormatTitle(ATitle);
  AFormattedBody := Adapter.FormatBody(ABody);
  Result := True;
end;

end.