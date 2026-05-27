unit ArtifactOS.Services.LegacyImport;

interface

uses
  System.SysUtils, System.Generics.Collections, System.IOUtils,
  ArtifactOS.Core.DB.Connection;

type
  TLegacyImportResult = record
    BatchId: string;
    TotalFiles: Integer;
    ImportedRefs: Integer;
    Errors: TArray<string>;
  end;

  TLegacyImportService = class
  public
    class function CreateBatch(const ASourceSystem, ASourceRoot: string): string;
    class function ScanDirectory(const ABatchId, ADirectory: string;
      const ARefType: string): TLegacyImportResult;
    class function ScanPythonFiles(const ABatchId, ADirectory: string): TLegacyImportResult;
    class function CreateSnapshot(const ARefId, ASnapshotKind: string;
      const AContent: string): string;
    class function CreateDiffCard(const AArtifactOSRef, ALegacyRef: string;
      ADeviationType, ASeverity: string): string;
    class function FinalizeBatch(const ABatchId: string): string;
    class function GetBatchSummary(const ABatchId: string): string;
  end;

implementation

uses
  FireDAC.Comp.Client, System.DateUtils, System.Hash;

function InsertId(const DB: TArtifactDB; const SQL: string): string;
var
  Q: TFDQuery;
begin
  Q := DB.Query(SQL);
  try
    Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

function SafeStr(const S: string): string;
begin
  Result := StringReplace(S, '''', '''''', [rfReplaceAll]);
end;

class function TLegacyImportService.CreateBatch(const ASourceSystem, ASourceRoot: string): string;
var
  DB: TArtifactDB;
  BatchCode: string;
begin
  BatchCode := 'legacy_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '_' + ASourceSystem;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO legacy_bridge.legacy_import_batch (batch_code, source_system, source_root, import_scope, status) ' +
      'VALUES (''' + BatchCode + ''', ''' + ASourceSystem + ''', ''' + SafeStr(ASourceRoot) + ''', ''publication_record'', ''prepared'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TLegacyImportService.ScanDirectory(const ABatchId, ADirectory: string;
  const ARefType: string): TLegacyImportResult;
var
  DB: TArtifactDB;
  Files: TArray<string>;
  I: Integer;
  FPath, Hash: string;
  MTime: TDateTime;
  Size: Int64;
begin
  Result.BatchId := ABatchId;
  Result.TotalFiles := 0;
  Result.ImportedRefs := 0;
  SetLength(Result.Errors, 0);

  if not TDirectory.Exists(ADirectory) then
  begin
    SetLength(Result.Errors, 1);
    Result.Errors[0] := 'Directory not found: ' + ADirectory;
    Exit;
  end;

  Files := TDirectory.GetFiles(ADirectory, '*.*', TSearchOption.soAllDirectories);
  Result.TotalFiles := Length(Files);

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      for I := 0 to High(Files) do
      begin
        FPath := Files[I];
        if not TFile.Exists(FPath) then Continue;

        var Ext := TPath.GetExtension(FPath).ToLower;
        if not (Ext in ['.py', '.md', '.json', '.yaml', '.yml', '.txt', '.js', '.ts', '.html', '.css', '.csv', '.bat', '.ps1', '.sql']) then
          Continue;

        try
          Size := 0;
          try Size := TFile.GetSize(FPath); except end;
          try MTime := TFile.GetLastWriteTime(FPath); except MTime := 0; end;
          try
            Hash := THashSHA2.GetHashString(TFile.ReadAllText(FPath), THashSHA2.TSHA2Version.SHA256).Substring(0, 32);
          except
            Hash := 'unreadable';
          end;

          InsertId(DB,
            'INSERT INTO legacy_bridge.legacy_external_ref (import_batch_id, ref_type, ref_label, source_path, source_hash, source_mtime, status) ' +
            'VALUES (''' + ABatchId + ''', ''' + ARefType + ''', ''' + SafeStr(TPath.GetFileName(FPath)) + ''', ''' + SafeStr(FPath) + ''', ''' + Hash + ''', ''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', MTime) + ''', ''captured'') ' +
            'ON CONFLICT DO NOTHING');

          Inc(Result.ImportedRefs);
        except
          on E: Exception do
          begin
            SetLength(Result.Errors, Length(Result.Errors) + 1);
            Result.Errors[High(Result.Errors)] := FPath + ': ' + E.Message;
          end;
        end;
      end;

      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TLegacyImportService.ScanPythonFiles(const ABatchId, ADirectory: string): TLegacyImportResult;
begin
  Result := ScanDirectory(ABatchId, ADirectory, 'pipeline_output');
end;

class function TLegacyImportService.CreateSnapshot(const ARefId, ASnapshotKind: string;
  const AContent: string): string;
var
  DB: TArtifactDB;
  ContentHash: string;
begin
  ContentHash := THashSHA2.GetHashString(AContent, THashSHA2.TSHA2Version.SHA256).Substring(0, 32);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO legacy_bridge.legacy_snapshot (legacy_external_ref_id, snapshot_kind, content_hash, snapshot_payload) ' +
      'VALUES (''' + ARefId + ''', ''' + ASnapshotKind + ''', ''' + ContentHash + ''', ''{"content":"' + SafeStr(AContent) + '"}'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TLegacyImportService.CreateDiffCard(const AArtifactOSRef, ALegacyRef: string;
  ADeviationType, ASeverity: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO legacy_bridge.legacy_diff_card (artifactos_ref, legacy_ref, deviation_type, severity, status) ' +
      'VALUES (''' + AArtifactOSRef + ''', ''' + ALegacyRef + ''', ''' + ADeviationType + ''', ''' + ASeverity + ''', ''open'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TLegacyImportService.FinalizeBatch(const ABatchId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('UPDATE legacy_bridge.legacy_import_batch SET status=''imported'' WHERE id=''' + ABatchId + '''');
    Result := ABatchId;
  finally
    DB.Disconnect;
  end;
end;

class function TLegacyImportService.GetBatchSummary(const ABatchId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT ''batch='' || batch_code || '' files='' || ' +
      '(SELECT COUNT(*)::text FROM legacy_bridge.legacy_external_ref WHERE import_batch_id=''' + ABatchId + ''') ' +
      'FROM legacy_bridge.legacy_import_batch WHERE id=''' + ABatchId + '''');
  finally
    DB.Disconnect;
  end;
end;

end.