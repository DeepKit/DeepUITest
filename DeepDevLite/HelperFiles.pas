unit HelperFiles;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes;

function GetFileSize(const FilePath: string): Int64;
function ReadFileContent(const FilePath: string): string;
function WriteFileContent(const FilePath, Content: string): Boolean;
function IsSourceFile(const FileName: string): Boolean;
function GetTempScriptPath(const Ext: string): string;
function CleanTempFile(const FilePath: string): Boolean;
function GetUniqueFileName(const BasePath, Prefix, Ext: string): string;

implementation

uses
  uConstants;

function GetFileSize(const FilePath: string): Int64;
begin
  if FileExists(FilePath) then
    Result := TFile.GetSize(FilePath)
  else
    Result := 0;
end;

function ReadFileContent(const FilePath: string): string;
var
  SL: TStringList;
begin
  Result := '';
  if not FileExists(FilePath) then Exit;
  
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FilePath, TEncoding.UTF8);
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

function WriteFileContent(const FilePath, Content: string): Boolean;
var
  SL: TStringList;
begin
  Result := False;
  try
    SL := TStringList.Create;
    try
      SL.Text := Content;
      SL.SaveToFile(FilePath, TEncoding.UTF8);
      Result := True;
    finally
      SL.Free;
    end;
  except
    Result := False;
  end;
end;

function IsSourceFile(const FileName: string): Boolean;
var
  Ext: string;
  E: string;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(FileName));
  
  for E in SUPPORTED_EXTENSIONS do
  begin
    if Ext = E then
      Exit(True);
  end;
end;

function GetTempScriptPath(const Ext: string): string;
begin
  Result := TPath.GetTempFileName + Ext;
end;

function CleanTempFile(const FilePath: string): Boolean;
begin
  Result := False;
  if FileExists(FilePath) then
  begin
    try
      TFile.Delete(FilePath);
      Result := True;
    except
      Result := False;
    end;
  end;
end;

function GetUniqueFileName(const BasePath, Prefix, Ext: string): string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := TPath.Combine(BasePath, Prefix + '_' + GUIDToString(GUID).Replace('{', '').Replace('}', '').Replace('-', '') + Ext);
end;

end.
