unit TestHelperFiles;

interface

uses
  DUnitX.TestFramework, System.IOUtils, System.SysUtils, HelperFiles;

type
  [TestFixture]
  TTestHelperFiles = class
  private
    FTestDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Test_GetFileSize_Existing;
    [Test]
    procedure Test_GetFileSize_NonExisting;
    [Test]
    procedure Test_ReadFileContent_Valid;
    [Test]
    procedure Test_ReadFileContent_NonExisting;
    [Test]
    procedure Test_WriteFileContent_Valid;
    [Test]
    procedure Test_IsSourceFile_Py;
    [Test]
    procedure Test_IsSourceFile_Js;
    [Test]
    procedure Test_IsSourceFile_Txt;
    [Test]
    procedure Test_GetTempScriptPath;
    [Test]
    procedure Test_CleanTempFile;
    [Test]
    procedure Test_GetUniqueFileName;
  end;

implementation

uses
  uConstants;

procedure TTestHelperFiles.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'DeepDevLiteTests');
  if not TDirectory.Exists(FTestDir) then
    TDirectory.CreateDirectory(FTestDir);
end;

procedure TTestHelperFiles.TearDown;
begin
  if TDirectory.Exists(FTestDir) then
  begin
    try
      TDirectory.Delete(FTestDir, True);
    except
    end;
  end;
end;

procedure TTestHelperFiles.Test_GetFileSize_Existing;
var
  FilePath: string;
begin
  FilePath := TPath.Combine(FTestDir, 'test.txt');
  TFile.WriteAllText(FilePath, 'Hello World');
  
  Assert.AreEqual(Int64(11), GetFileSize(FilePath));
end;

procedure TTestHelperFiles.Test_GetFileSize_NonExisting;
begin
  Assert.AreEqual(Int64(0), GetFileSize('non_existing_file_xyz.txt'));
end;

procedure TTestHelperFiles.Test_ReadFileContent_Valid;
var
  FilePath, Content: string;
begin
  FilePath := TPath.Combine(FTestDir, 'read_test.txt');
  TFile.WriteAllText(FilePath, 'Test Content');
  
  Content := ReadFileContent(FilePath);
  Assert.IsTrue(Pos('Test Content', Content) > 0);
end;

procedure TTestHelperFiles.Test_ReadFileContent_NonExisting;
var
  Content: string;
begin
  Content := ReadFileContent('non_existing_file_xyz.txt');
  Assert.AreEqual('', Content);
end;

procedure TTestHelperFiles.Test_WriteFileContent_Valid;
var
  FilePath: string;
  Success: Boolean;
begin
  FilePath := TPath.Combine(FTestDir, 'write_test.txt');
  
  Success := WriteFileContent(FilePath, 'Written Content');
  
  Assert.IsTrue(Success);
  Assert.IsTrue(TFile.Exists(FilePath));
  Assert.IsTrue(Pos('Written Content', TFile.ReadAllText(FilePath)) > 0);
end;

procedure TTestHelperFiles.Test_IsSourceFile_Py;
begin
  Assert.IsTrue(IsSourceFile('test.py'));
  Assert.IsTrue(IsSourceFile('TEST.PY'));
end;

procedure TTestHelperFiles.Test_IsSourceFile_Js;
begin
  Assert.IsTrue(IsSourceFile('app.js'));
  Assert.IsTrue(IsSourceFile('APP.JS'));
end;

procedure TTestHelperFiles.Test_IsSourceFile_Txt;
begin
  Assert.IsFalse(IsSourceFile('readme.txt'));
  Assert.IsFalse(IsSourceFile('data.json'));
  Assert.IsFalse(IsSourceFile('noextension'));
end;

procedure TTestHelperFiles.Test_GetTempScriptPath;
var
  Path: string;
begin
  Path := GetTempScriptPath('.py');
  
  Assert.IsTrue(Path.EndsWith('.py'));
  Assert.IsFalse(Path.IsEmpty);
end;

procedure TTestHelperFiles.Test_CleanTempFile;
var
  FilePath: string;
  Success: Boolean;
begin
  FilePath := TPath.Combine(FTestDir, 'to_delete.txt');
  TFile.WriteAllText(FilePath, 'delete me');
  
  Assert.IsTrue(TFile.Exists(FilePath));
  
  Success := CleanTempFile(FilePath);
  
  Assert.IsTrue(Success);
  Assert.IsFalse(TFile.Exists(FilePath));
end;

procedure TTestHelperFiles.Test_GetUniqueFileName;
var
  Name1, Name2: string;
begin
  Name1 := GetUniqueFileName(FTestDir, 'test', '.txt');
  Name2 := GetUniqueFileName(FTestDir, 'test', '.txt');
  
  Assert.IsTrue(Name1.StartsWith(FTestDir));
  Assert.IsTrue(Name1.EndsWith('.txt'));
  Assert.AreNotEqual(Name1, Name2);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHelperFiles);

end.
