unit ArtifactOS.Tests.LegacyImport;

interface

uses
  DUnitX.TestFramework,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.LegacyImport;

type
  [TestFixture]
  TLegacyImportTests = class
  public
    [Test]
    procedure ImportBatch_CreateAndFinalize;

    [Test]
    procedure ImportDirectory_ScansAndImports;

    [Test]
    procedure Snapshot_CreateAndVerify;

    [Test]
    procedure DiffCard_CreateMultipleTypes;
  end;

implementation

uses
  System.SysUtils;

procedure TLegacyImportTests.ImportBatch_CreateAndFinalize;
var
  DB: TArtifactDB;
  BatchId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    BatchId := TLegacyImportService.CreateBatch('test_system', 'D:\_Progs\.BetterCiv\tools');
    Assert.IsNotEmpty(BatchId);

    var Status := DB.ExecuteScalar('SELECT status FROM legacy_bridge.legacy_import_batch WHERE id=''' + BatchId + '''');
    Assert.AreEqual('prepared', Status);

    TLegacyImportService.FinalizeBatch(BatchId);
    Status := DB.ExecuteScalar('SELECT status FROM legacy_bridge.legacy_import_batch WHERE id=''' + BatchId + '''');
    Assert.AreEqual('imported', Status);

    DB.Execute('DELETE FROM legacy_bridge.legacy_import_batch WHERE id=''' + BatchId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TLegacyImportTests.ImportDirectory_ScansAndImports;
var
  DB: TArtifactDB;
  BatchId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    BatchId := TLegacyImportService.CreateBatch('dir_test', 'D:\_Progs\.BetterCiv\tools\media_publish\media_publish');
    var Result := TLegacyImportService.ScanPythonFiles(BatchId, 'D:\_Progs\.BetterCiv\tools\media_publish\media_publish');

    // The media_publish directory should have Python files
    Assert.IsTrue(Result.TotalFiles > 0, 'Total files should be > 0');
    Assert.IsTrue(Result.ImportedRefs > 0, 'Imported refs should be > 0');

    var Count := DB.ExecuteScalar('SELECT COUNT(*)::text FROM legacy_bridge.legacy_external_ref WHERE import_batch_id=''' + BatchId + '''');
    Assert.IsTrue(StrToInt(Count) > 0, 'External refs should exist');

    DB.Execute('DELETE FROM legacy_bridge.legacy_external_ref WHERE import_batch_id=''' + BatchId + '''');
    DB.Execute('DELETE FROM legacy_bridge.legacy_import_batch WHERE id=''' + BatchId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TLegacyImportTests.Snapshot_CreateAndVerify;
var
  DB: TArtifactDB;
  BatchId, RefId, SnapId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    BatchId := TLegacyImportService.CreateBatch('snap_test', 'test');
    DB.Execute(
      'INSERT INTO legacy_bridge.legacy_external_ref (import_batch_id, ref_type, ref_label, source_path, status) ' +
      'VALUES (''' + BatchId + ''', ''publication_record'', ''test_ref'', ''test/path.md'', ''captured'')');
    RefId := DB.ExecuteScalar('SELECT id::text FROM legacy_bridge.legacy_external_ref WHERE import_batch_id=''' + BatchId + ''' LIMIT 1');

    SnapId := TLegacyImportService.CreateSnapshot(RefId, 'publication', 'Test content for snapshot');
    Assert.IsNotEmpty(SnapId);

    var Content := DB.ExecuteScalar('SELECT snapshot_payload->>''content'' FROM legacy_bridge.legacy_snapshot WHERE id=''' + SnapId + '''');
    Assert.AreEqual('Test content for snapshot', Content);

    DB.Execute('DELETE FROM legacy_bridge.legacy_snapshot WHERE id=''' + SnapId + '''');
    DB.Execute('DELETE FROM legacy_bridge.legacy_external_ref WHERE id=''' + RefId + '''');
    DB.Execute('DELETE FROM legacy_bridge.legacy_import_batch WHERE id=''' + BatchId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TLegacyImportTests.DiffCard_CreateMultipleTypes;
var
  DB: TArtifactDB;
  CardId1, CardId2, CardId3: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    CardId1 := TLegacyImportService.CreateDiffCard('{"artifactos":"topic_choice_A"}', '{"legacy":"topic_choice_B"}', 'topic_deviation', 'medium');
    Assert.IsNotEmpty(CardId1);

    CardId2 := TLegacyImportService.CreateDiffCard('{"artifactos":"schedule_A"}', '{"legacy":"schedule_B"}', 'schedule_deviation', 'low');
    Assert.IsNotEmpty(CardId2);

    CardId3 := TLegacyImportService.CreateDiffCard('{"artifactos":"same"}', '{"legacy":"same"}', 'no_material_deviation', 'none');
    Assert.IsNotEmpty(CardId3);

    var Count := DB.ExecuteScalar('SELECT COUNT(*)::text FROM legacy_bridge.legacy_diff_card WHERE id IN (' + CardId1 + ',' + CardId2 + ',' + CardId3 + ')');
    Assert.AreEqual('3', Count);

    DB.Execute('DELETE FROM legacy_bridge.legacy_diff_card WHERE id IN (' + CardId1 + ',' + CardId2 + ',' + CardId3 + ')');
  finally
    DB.Disconnect;
  end;
end;

initialization

end.