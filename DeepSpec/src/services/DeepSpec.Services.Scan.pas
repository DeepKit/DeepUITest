
{ ============================================================================
  DeepSpec.Services.Scan

  File scanner: recursively scans project directory, classifies files
  according to protocol §14.1 priority rules, generates scan-report.yaml.
  ============================================================================ }

unit DeepSpec.Services.Scan;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TFileCategory = (
    fcIgnored,
    fcAiRules,
    fcDocuments,
    fcUI,
    fcCode,
    fcConfig,
    fcUnknown
  );

  TScanResult = record
    Category: TFileCategory;
    RelativePath: string;
  end;

  TDeepSpecScanService = class(TInterfacedObject)
  private
    FResults: TList<TScanResult>;
    function ClassifyFile(const ARelPath, AFileName: string): TFileCategory;
    function IsIgnoredDir(const ADirName: string): Boolean;
    function IsAiRulesFile(const ARelPath, AFileName: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ScanDirectory(const ARootPath: string);
    function GetFilesByCategory(ACategory: TFileCategory): TArray<string>;
    function TotalFiles: Integer;
    function CategoryCount(ACategory: TFileCategory): Integer;
    property Results: TList<TScanResult> read FResults;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils;

const
  IGNORED_DIRS: array[0..15] of string = (
    'node_modules', '.git', '.svn', '.hg', '__pycache__',
    '.pytest_cache', 'build', 'bin', 'dist', 'out',
    'target', 'debug', 'release', '__history', '.next',
    '.deepspec'
  );

  AI_RULES_FILES: array[0..4] of string = (
    'claude.md', 'agents.md', '.cursorrules',
    'cursor-rules.md', '.windsurfrules'
  );

  DOC_EXTS: array[0..6] of string = (
    '.md', '.txt', '.rst', '.doc', '.docx', '.pdf', '.adoc'
  );

  UI_EXTS: array[0..10] of string = (
    '.dfm', '.fmx', '.html', '.htm', '.vue', '.jsx',
    '.tsx', '.svelte', '.astro', '.xaml', '.qml'
  );

  CODE_EXTS: array[0..17] of string = (
    '.pas', '.dpr', '.inc', '.py', '.ts', '.js', '.java',
    '.cs', '.go', '.rs', '.rb', '.php', '.swift', '.kt',
    '.c', '.cpp', '.h', '.hpp'
  );

  CONFIG_EXTS: array[0..11] of string = (
    '.yaml', '.yml', '.json', '.toml', '.ini', '.xml',
    '.env', '.properties', '.dproj', '.dpk', '.sln', '.csproj'
  );

constructor TDeepSpecScanService.Create;
begin
  inherited Create;
  FResults := TList<TScanResult>.Create;
end;

destructor TDeepSpecScanService.Destroy;
begin
  FResults.Free;
  inherited;
end;

function TDeepSpecScanService.IsIgnoredDir(const ADirName: string): Boolean;
begin
  var LLower := LowerCase(ADirName);
  for var LDir in IGNORED_DIRS do
    if LLower = LDir then
      Exit(True);
  Result := False;
end;

function TDeepSpecScanService.IsAiRulesFile(const ARelPath, AFileName: string): Boolean;
begin
  var LLower := LowerCase(AFileName);
  for var LName in AI_RULES_FILES do
    if LLower = LName then
      Exit(True);

  // Path-based rules
  var LRelLower := LowerCase(ARelPath);
  if LRelLower.Contains('.kiro/steering/') then
    Exit(True);
  if LRelLower.Contains('.github/copilot-instructions.md') then
    Exit(True);

  Result := False;
end;

function TDeepSpecScanService.ClassifyFile(const ARelPath, AFileName: string): TFileCategory;
begin
  var LExt := LowerCase(TPath.GetExtension(AFileName));

  // Priority 1: AI rules
  if IsAiRulesFile(ARelPath, AFileName) then
    Exit(fcAiRules);

  // Priority 2: Documents
  for var LDocExt in DOC_EXTS do
    if LExt = LDocExt then
      Exit(fcDocuments);

  // Priority 3: UI
  for var LUIExt in UI_EXTS do
    if LExt = LUIExt then
      Exit(fcUI);

  // Priority 4: Code
  for var LCodeExt in CODE_EXTS do
    if LExt = LCodeExt then
      Exit(fcCode);

  // Priority 5: Config
  for var LCfgExt in CONFIG_EXTS do
    if LExt = LCfgExt then
      Exit(fcConfig);

  Result := fcUnknown;
end;

procedure TDeepSpecScanService.ScanDirectory(const ARootPath: string);

  procedure ScanRecursive(const ADir, ARelBase: string);
  begin
    for var LFile in TDirectory.GetFiles(ADir) do
    begin
      var LFileName := TPath.GetFileName(LFile);
      var LRelPath: string;
      if ARelBase = '' then
        LRelPath := LFileName
      else
        LRelPath := ARelBase + '/' + LFileName;
      var LEntry: TScanResult;
      LEntry.RelativePath := LRelPath;
      LEntry.Category := ClassifyFile(LRelPath, LFileName);
      FResults.Add(LEntry);
    end;

    for var LSubDir in TDirectory.GetDirectories(ADir) do
    begin
      var LDirName := TPath.GetFileName(LSubDir);
      if IsIgnoredDir(LDirName) then
      begin
        var LEntry: TScanResult;
        if ARelBase = '' then
          LEntry.RelativePath := LDirName
        else
          LEntry.RelativePath := ARelBase + '/' + LDirName;
        LEntry.Category := fcIgnored;
        FResults.Add(LEntry);
        Continue;
      end;
      var LNewBase: string;
      if ARelBase = '' then
        LNewBase := LDirName
      else
        LNewBase := ARelBase + '/' + LDirName;
      ScanRecursive(LSubDir, LNewBase);
    end;
  end;

begin
  FResults.Clear;
  if not TDirectory.Exists(ARootPath) then
    Exit;
  ScanRecursive(ARootPath, '');
end;

function TDeepSpecScanService.GetFilesByCategory(ACategory: TFileCategory): TArray<string>;
begin
  var LList := TList<string>.Create;
  try
    for var LEntry in FResults do
      if LEntry.Category = ACategory then
        LList.Add(LEntry.RelativePath);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TDeepSpecScanService.TotalFiles: Integer;
begin
  Result := FResults.Count;
end;

function TDeepSpecScanService.CategoryCount(ACategory: TFileCategory): Integer;
begin
  Result := 0;
  for var LEntry in FResults do
    if LEntry.Category = ACategory then
      Inc(Result);
end;

end.
