unit DeepFrames.UI.MainForm;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  DeepBase.VCL.DeepShell,
  DeepBase.VCL.DeepShell.Types,
  DeepBase.VCL.DeepShell.Intf;

type
  TDeepFramesSettingsStore = class(TInterfacedObject, IShellSettingsStore)
  public
    function ReadString(const AKey, ADefault: string): string;
    procedure WriteString(const AKey, AValue: string);
    function ReadBool(const AKey: string; ADefault: Boolean): Boolean;
    procedure WriteBool(const AKey: string; AValue: Boolean);
    function ReadInteger(const AKey: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure RemoveKey(const AKey: string);
  end;

  TDeepFramesSettingsPageProvider = class(TInterfacedObject, ISettingsPageProvider)
  private
    FPanel: TPanel;
    FRootPath: TEdit;
    FOutputDir: TEdit;
    FWorkerDir: TEdit;
    FDbHost: TEdit;
    FDbPort: TEdit;
    FDbName: TEdit;
    FDbUser: TEdit;
    FDbSecretRef: TEdit;
    procedure AddEdit(AOwner: TWinControl; const ACaption: string;
      var AEdit: TEdit; ATop: Integer; const AValue: string);
  public
    function PageId: string;
    function Caption: string;
    function GroupName: string;
    function CreatePage(AOwner: TComponent): TControl;
    procedure Apply;
    procedure Cancel;
    procedure RestoreDefaults;
  end;

  TDeepFramesStructureProvider = class(TInterfacedObject, IShellStructureProvider)
  public
    function ProviderId: string;
    function GetTreeNames: TArray<string>;
    function GetRootNodes(const ATreeName: string): TArray<TShellObjectRef>;
    function HasChildren(const ANode: TShellObjectRef): Boolean;
    function GetChildren(const ANode: TShellObjectRef): TArray<TShellObjectRef>;
    function GetDisplayText(const ANode: TShellObjectRef): string;
  end;

  TDeepFramesMainViewProvider = class(TInterfacedObject, IShellMainViewProvider)
  public
    function ProviderId: string;
    function CanOpen(const ARef: TShellObjectRef): Boolean;
    function GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
    function CreateViewControl(AOwner: TComponent; const ARef: TShellObjectRef;
      const AInfo: TShellViewInfo): TControl;
  end;

  TDeepFramesInspectorProvider = class(TInterfacedObject, IShellInspectorProvider)
  public
    function ProviderId: string;
    function CanInspect(const ARef: TShellObjectRef): Boolean;
    function GetProperties(const ARef: TShellObjectRef): TArray<TShellProperty>;
    function GetRelations(const ARef: TShellObjectRef): TArray<TShellRelation>;
    function GetIssues(const ARef: TShellObjectRef): TArray<TShellIssue>;
  end;

  TMainForm = class(TDeepMainForm)
  private
    FSettingsStore: IShellSettingsStore;
    procedure CmdNewProject;
    procedure CmdImportMarkdown;
    procedure CmdRunPreprocess;
    procedure CmdRunDocumentChain;
    procedure CmdRunAgentChain;
    procedure CmdRunAudioChain;
    procedure CmdRunVideoChain;
    procedure CmdRunPackageChain;
    procedure CmdRunExtensionChain;
    procedure CmdSwitchProvider;
    procedure CmdTestDb2;
    procedure CmdRunMigrations;
    procedure RefreshProjectView;
  protected
    procedure RegisterServices; override;
    procedure RegisterCommands; override;
    procedure RegisterProviders; override;
    procedure AfterShellShown; override;
  end;

var
  MainForm: TMainForm;

implementation

uses
  DeepBase.Config,
  DeepBase.Manager,
  DeepBase.VCL.DeepShell.Layout,
  DeepFrames.App.Constants,
  DeepFrames.App.Services,
  DeepFrames.Shared.Consts,
  DeepFrames.Domain.Types,
  DeepFrames.Persistence.Connection,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry;

const
  SHELL_SETTING_PREFIX = 'Shell.';

function SettingKey(const AKey: string): string;
begin
  Result := SHELL_SETTING_PREFIX + AKey;
end;

{ TDeepFramesSettingsStore }

function TDeepFramesSettingsStore.ReadString(const AKey,
  ADefault: string): string;
begin
  Result := GetConfig(SettingKey(AKey), ADefault);
end;

procedure TDeepFramesSettingsStore.WriteString(const AKey, AValue: string);
begin
  SetConfig(SettingKey(AKey), AValue, 'Shell');
end;

function TDeepFramesSettingsStore.ReadBool(const AKey: string;
  ADefault: Boolean): Boolean;
begin
  Result := GetConfigBool(SettingKey(AKey), ADefault);
end;

procedure TDeepFramesSettingsStore.WriteBool(const AKey: string;
  AValue: Boolean);
begin
  SetConfigBool(SettingKey(AKey), AValue, 'Shell');
end;

function TDeepFramesSettingsStore.ReadInteger(const AKey: string;
  ADefault: Integer): Integer;
begin
  Result := GetConfigInt(SettingKey(AKey), ADefault);
end;

procedure TDeepFramesSettingsStore.WriteInteger(const AKey: string;
  AValue: Integer);
begin
  SetConfigInt(SettingKey(AKey), AValue, 'Shell');
end;

procedure TDeepFramesSettingsStore.RemoveKey(const AKey: string);
begin
  SetConfig(SettingKey(AKey), '', 'Shell');
end;

{ TDeepFramesSettingsPageProvider }

procedure TDeepFramesSettingsPageProvider.AddEdit(AOwner: TWinControl;
  const ACaption: string; var AEdit: TEdit; ATop: Integer; const AValue: string);
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(AOwner);
  LLabel.Parent := AOwner;
  LLabel.Left := 16;
  LLabel.Top := ATop + 4;
  LLabel.Width := 150;
  LLabel.Caption := ACaption;

  AEdit := TEdit.Create(AOwner);
  AEdit.Parent := AOwner;
  AEdit.Left := 180;
  AEdit.Top := ATop;
  AEdit.Width := 360;
  AEdit.Text := AValue;
end;

function TDeepFramesSettingsPageProvider.PageId: string;
begin
  Result := SETTINGS_PAGE_GENERAL;
end;

function TDeepFramesSettingsPageProvider.Caption: string;
begin
  Result := 'DeepFrames Phase 1';
end;

function TDeepFramesSettingsPageProvider.GroupName: string;
begin
  Result := 'DeepFrames';
end;

function TDeepFramesSettingsPageProvider.CreatePage(AOwner: TComponent): TControl;
begin
  FPanel := TPanel.Create(AOwner);
  FPanel.BevelOuter := bvNone;

  AddEdit(FPanel, 'RootPath', FRootPath, 16, GetConfig(CONFIG_ROOT_PATH, DeepBase.Manager.DeepBase.RootPath));
  AddEdit(FPanel, 'Output directory', FOutputDir, 48, GetConfig(CONFIG_OUTPUT_DIR, 'output'));
  AddEdit(FPanel, 'Worker directory', FWorkerDir, 80, GetConfig(CONFIG_WORKER_DIR, 'workers'));
  AddEdit(FPanel, 'DB2 Host', FDbHost, 128, GetConfig(DB2_HOST, DEFAULT_DB2_HOST));
  AddEdit(FPanel, 'DB2 Port', FDbPort, 160, IntToStr(GetConfigInt(DB2_PORT, DEFAULT_DB2_PORT)));
  AddEdit(FPanel, 'DB2 Database', FDbName, 192, GetConfig(DB2_DATABASE, DEFAULT_DB2_DATABASE));
  AddEdit(FPanel, 'DB2 User', FDbUser, 224, GetConfig(DB2_USER, DEFAULT_DB2_USER));
  AddEdit(FPanel, 'DB2 Secret Ref', FDbSecretRef, 256, GetConfig(DB2_PASSWORD_SECRET_REF, DEFAULT_DB2_PASSWORD_SECRET_REF));

  Result := FPanel;
end;

procedure TDeepFramesSettingsPageProvider.Apply;
begin
  if Assigned(FRootPath) then
    SetConfig(CONFIG_ROOT_PATH, FRootPath.Text, 'Paths');
  if Assigned(FOutputDir) then
    SetConfig(CONFIG_OUTPUT_DIR, FOutputDir.Text, 'Paths');
  if Assigned(FWorkerDir) then
    SetConfig(CONFIG_WORKER_DIR, FWorkerDir.Text, 'Paths');
  if Assigned(FDbHost) then
    SetConfig(DB2_HOST, FDbHost.Text, 'Database');
  if Assigned(FDbPort) then
    SetConfigInt(DB2_PORT, StrToIntDef(FDbPort.Text, DEFAULT_DB2_PORT), 'Database');
  if Assigned(FDbName) then
    SetConfig(DB2_DATABASE, FDbName.Text, 'Database');
  if Assigned(FDbUser) then
    SetConfig(DB2_USER, FDbUser.Text, 'Database');
  if Assigned(FDbSecretRef) then
    SetConfig(DB2_PASSWORD_SECRET_REF, FDbSecretRef.Text, 'Database');
end;

procedure TDeepFramesSettingsPageProvider.Cancel;
begin
end;

procedure TDeepFramesSettingsPageProvider.RestoreDefaults;
begin
  if Assigned(FOutputDir) then
    FOutputDir.Text := 'output';
  if Assigned(FWorkerDir) then
    FWorkerDir.Text := 'workers';
  if Assigned(FDbHost) then
    FDbHost.Text := DEFAULT_DB2_HOST;
  if Assigned(FDbPort) then
    FDbPort.Text := IntToStr(DEFAULT_DB2_PORT);
  if Assigned(FDbName) then
    FDbName.Text := DEFAULT_DB2_DATABASE;
  if Assigned(FDbUser) then
    FDbUser.Text := DEFAULT_DB2_USER;
  if Assigned(FDbSecretRef) then
    FDbSecretRef.Text := DEFAULT_DB2_PASSWORD_SECRET_REF;
end;

{ TDeepFramesStructureProvider }

function TDeepFramesStructureProvider.ProviderId: string;
begin
  Result := PROVIDER_DEEPFRAMES;
end;

function TDeepFramesStructureProvider.GetTreeNames: TArray<string>;
begin
  Result := ['DeepFrames'];
end;

function TDeepFramesStructureProvider.GetRootNodes(
  const ATreeName: string): TArray<TShellObjectRef>;
var
  Projects: TArray<TProjectInfo>;
  I, Count: Integer;
begin
  try
    Projects := TDeepFramesAppService.ListProjects;
    Count := Length(Projects) + 1; // +1 for Extensions node
    SetLength(Result, Count);
    for I := 0 to High(Projects) do
      Result[I] := TShellObjectRef.Make(Projects[I].ProjectId, 'project',
        PROVIDER_DEEPFRAMES, Projects[I].Title);
    // Add Extensions root node
    Result[High(Projects) + 1] := TShellObjectRef.Make('extensions', 'extensions',
      PROVIDER_DEEPFRAMES, 'Extensions');
  except
    Result := [TShellObjectRef.Make('setup', 'setup', PROVIDER_DEEPFRAMES,
      'Configure DB2 and run migrations')];
  end;
end;

function TDeepFramesStructureProvider.HasChildren(
  const ANode: TShellObjectRef): Boolean;
begin
  Result := SameText(ANode.Kind, 'project') or SameText(ANode.Kind, 'content_unit') or
    SameText(ANode.Kind, 'source_document') or SameText(ANode.Kind, 'script_document') or
    SameText(ANode.Kind, 'variant_document') or SameText(ANode.Kind, 'job') or
    SameText(ANode.Kind, 'job_step') or SameText(ANode.Kind, 'audio_manifest') or
    SameText(ANode.Kind, 'video_ir') or SameText(ANode.Kind, 'video_job') or
    SameText(ANode.Kind, 'extensions') or SameText(ANode.Kind, 'bgm_library');
end;

function TDeepFramesStructureProvider.GetChildren(
  const ANode: TShellObjectRef): TArray<TShellObjectRef>;
var
  Units: TArray<TContentUnitInfo>;
  Docs: TArray<TSourceDocumentVersion>;
  Jobs: TArray<TDeepFramesJob>;
  Steps: TArray<TDeepFramesJobStep>;
  I, Count: Integer;
begin
  Result := nil;
  if SameText(ANode.Kind, 'project') then
  begin
    Units := TDeepFramesAppService.ListContentUnits(ANode.Id);
    Docs := TDeepFramesAppService.ListSourceDocuments(ANode.Id);
    Jobs := TDeepFramesAppService.ListJobs;
    Count := Length(Units) + Length(Docs) + Length(Jobs);
    SetLength(Result, Count);
    Count := 0;
    for I := 0 to High(Units) do
    begin
      Result[Count] := TShellObjectRef.Make(Units[I].ContentUnitId, 'content_unit', PROVIDER_DEEPFRAMES, Units[I].DisplayLabel);
      Inc(Count);
    end;
    for I := 0 to High(Docs) do
    begin
      Result[Count] := TShellObjectRef.Make(Docs[I].DocumentId, 'source_document', PROVIDER_DEEPFRAMES, 'source_document v' + IntToStr(Docs[I].VersionNo));
      Inc(Count);
    end;
    for I := 0 to High(Jobs) do
      if SameText(Jobs[I].ProjectId, ANode.Id) then
      begin
        Result[Count] := TShellObjectRef.Make(Jobs[I].JobId, 'job', PROVIDER_DEEPFRAMES, Jobs[I].JobType + ' [' + Jobs[I].Status + ']');
        Inc(Count);
      end;
    SetLength(Result, Count);
  end
  else if SameText(ANode.Kind, 'job') then
  begin
    Steps := TDeepFramesAppService.ListJobSteps(ANode.Id);
    SetLength(Result, Length(Steps));
    for I := 0 to High(Steps) do
      Result[I] := TShellObjectRef.Make(Steps[I].StepId, 'job_step', PROVIDER_DEEPFRAMES, Steps[I].StepType + ' [' + Steps[I].Status + ']');
  end
  else if SameText(ANode.Kind, 'job_step') then
  begin
    // Show prompt runs and eval results for this step
    // Find the parent job to list runs
    var StepJobs: TArray<TDeepFramesJob>;
    StepJobs := TDeepFramesAppService.ListJobs;
    var StepParentJobId: string := '';
    for I := 0 to High(StepJobs) do
    begin
      var StepSteps := TDeepFramesAppService.ListJobSteps(StepJobs[I].JobId);
      var J: Integer;
      for J := 0 to High(StepSteps) do
        if SameText(StepSteps[J].StepId, ANode.Id) then
        begin
          StepParentJobId := StepJobs[I].JobId;
          Break;
        end;
      if StepParentJobId <> '' then Break;
    end;
    if StepParentJobId <> '' then
    begin
      var StepRuns := TDeepFramesAppService.ListPromptRuns(StepParentJobId);
      var StepEvals := TDeepFramesAppService.ListEvalResults(StepParentJobId);
      var StepCount := 0;
      SetLength(Result, Length(StepRuns) + Length(StepEvals));
      for I := 0 to High(StepRuns) do
        if SameText(StepRuns[I].JobStepId, ANode.Id) then
        begin
          Result[StepCount] := TShellObjectRef.Make(StepRuns[I].RunId, 'prompt_run', PROVIDER_DEEPFRAMES,
            StepRuns[I].AgentRole + ' [' + StepRuns[I].Provider + '/' + StepRuns[I].Model + ']');
          Inc(StepCount);
        end;
      for I := 0 to High(StepEvals) do
        if SameText(StepEvals[I].JobStepId, ANode.Id) then
        begin
          Result[StepCount] := TShellObjectRef.Make(StepEvals[I].EvalId, 'eval_result', PROVIDER_DEEPFRAMES,
            StepEvals[I].EvalType + ' score=' + FloatToStrF(StepEvals[I].Score, ffFixed, 4, 2));
          Inc(StepCount);
        end;
      SetLength(Result, StepCount);
    end;
  end
  else if SameText(ANode.Kind, 'source_document') then
  begin
    // Show script documents derived from this source
    var SrcDocProjects: TArray<TProjectInfo>;
    var SrcDocScripts: TArray<TScriptDocumentVersion>;
    SrcDocProjects := TDeepFramesAppService.ListProjects;
    if Length(SrcDocProjects) > 0 then
    begin
      SrcDocScripts := TDeepFramesAppService.ListScriptDocuments(SrcDocProjects[0].ProjectId);
      SetLength(Result, Length(SrcDocScripts));
      for I := 0 to High(SrcDocScripts) do
        if SameText(SrcDocScripts[I].SourceDocumentId, ANode.Id) then
          Result[I] := TShellObjectRef.Make(SrcDocScripts[I].DocumentId, 'script_document', PROVIDER_DEEPFRAMES,
            'script v' + IntToStr(SrcDocScripts[I].VersionNo) + ' [' + SrcDocScripts[I].Status + ']');
    end;
  end
  else if SameText(ANode.Kind, 'script_document') then
  begin
    // Show variants derived from this script
    var ScriptVariants: TArray<TVariantDocumentVersion>;
    var ScriptProjArr: TArray<TProjectInfo>;
    ScriptProjArr := TDeepFramesAppService.ListProjects;
    if Length(ScriptProjArr) > 0 then
    begin
      var ScriptUnits := TDeepFramesAppService.ListContentUnits(ScriptProjArr[0].ProjectId);
      if Length(ScriptUnits) > 0 then
      begin
        ScriptVariants := TDeepFramesAppService.ListVariantDocuments(ScriptUnits[0].ContentUnitId);
        var ScriptMatched: TArray<TShellObjectRef>;
        SetLength(ScriptMatched, Length(ScriptVariants));
        var ScriptMatchCount := 0;
        for I := 0 to High(ScriptVariants) do
          if SameText(ScriptVariants[I].ParentDocumentId, ANode.Id) then
          begin
            ScriptMatched[ScriptMatchCount] := TShellObjectRef.Make(ScriptVariants[I].DocumentId, 'variant_document', PROVIDER_DEEPFRAMES,
              ScriptVariants[I].VariantKind + ' - ' + ScriptVariants[I].TargetPlatform + ' [' + ScriptVariants[I].Status + ']');
            Inc(ScriptMatchCount);
          end;
        SetLength(ScriptMatched, ScriptMatchCount);
        Result := ScriptMatched;
      end;
    end;
  end
  else if SameText(ANode.Kind, 'variant_document') then
  begin
    // Show shots derived from this variant
    var VarProjArr: TArray<TProjectInfo>;
    VarProjArr := TDeepFramesAppService.ListProjects;
    if Length(VarProjArr) > 0 then
    begin
      var VarUnits := TDeepFramesAppService.ListContentUnits(VarProjArr[0].ProjectId);
      if Length(VarUnits) > 0 then
      begin
        var VarShots := TDeepFramesAppService.ListShotDocuments(VarUnits[0].ContentUnitId);
        var VarMatched: TArray<TShellObjectRef>;
        SetLength(VarMatched, Length(VarShots));
        var VarMatchCount := 0;
        for I := 0 to High(VarShots) do
          if SameText(VarShots[I].ParentDocumentId, ANode.Id) then
          begin
            VarMatched[VarMatchCount] := TShellObjectRef.Make(VarShots[I].DocumentId, 'shot_document', PROVIDER_DEEPFRAMES,
              'shot v' + IntToStr(VarShots[I].VersionNo) + ' [' + VarShots[I].Status + ']');
            Inc(VarMatchCount);
          end;
        SetLength(VarMatched, VarMatchCount);
        Result := VarMatched;
      end;
    end;
  end
  else if SameText(ANode.Kind, 'shot_document') then
  begin
    // Show audio manifests for this shot
    var ShotManifest: TAudioManifest;
    var ShotProjArr: TArray<TProjectInfo>;
    ShotProjArr := TDeepFramesAppService.ListProjects;
    if Length(ShotProjArr) > 0 then
    begin
      var ShotUnits := TDeepFramesAppService.ListContentUnits(ShotProjArr[0].ProjectId);
      if Length(ShotUnits) > 0 then
      begin
        var ShotManifests := TDeepFramesAppService.ListAudioManifests(ShotUnits[0].ContentUnitId);
        var ShotAudioMatched: TArray<TShellObjectRef>;
        SetLength(ShotAudioMatched, Length(ShotManifests));
        var ShotAudioCount := 0;
        for I := 0 to High(ShotManifests) do
          if SameText(ShotManifests[I].ShotDocumentId, ANode.Id) then
          begin
            ShotAudioMatched[ShotAudioCount] := TShellObjectRef.Make(
              ShotManifests[I].ManifestId, 'audio_manifest', PROVIDER_DEEPFRAMES,
              'audio [' + ShotManifests[I].Status + '] ' + FloatToStrF(ShotManifests[I].DurationSec, ffFixed, 4, 1) + 's');
            Inc(ShotAudioCount);
          end;
        SetLength(ShotAudioMatched, ShotAudioCount);
        Result := ShotAudioMatched;
      end;
    end;
  end
  else if SameText(ANode.Kind, 'audio_manifest') then
  begin
    // Show video IRs that reference this audio manifest
    var AMProjArr: TArray<TProjectInfo>;
    AMProjArr := TDeepFramesAppService.ListProjects;
    if Length(AMProjArr) > 0 then
    begin
      var AMUnits := TDeepFramesAppService.ListContentUnits(AMProjArr[0].ProjectId);
      if Length(AMUnits) > 0 then
      begin
        var AMVideoIRs := TDeepFramesAppService.ListVideoIRs(AMUnits[0].ContentUnitId);
        var AMVideoMatched: TArray<TShellObjectRef>;
        SetLength(AMVideoMatched, Length(AMVideoIRs));
        var AMVideoCount := 0;
        for I := 0 to High(AMVideoIRs) do
          if SameText(AMVideoIRs[I].AudioManifestId, ANode.Id) then
          begin
            AMVideoMatched[AMVideoCount] := TShellObjectRef.Make(
              AMVideoIRs[I].VideoIRId, 'video_ir', PROVIDER_DEEPFRAMES,
              'video_ir [' + AMVideoIRs[I].Status + '] ' + AMVideoIRs[I].RenderBackend);
            Inc(AMVideoCount);
          end;
        SetLength(AMVideoMatched, AMVideoCount);
        Result := AMVideoMatched;
      end;
    end;
  end
  else if SameText(ANode.Kind, 'video_ir') then
  begin
    // Show video jobs + candidate packages for this video IR
    var VIRJobs := TDeepFramesAppService.ListVideoJobs(ANode.Id);
    var VIRProjArr: TArray<TProjectInfo>;
    var VIRPkgs: TArray<TCandidatePackage>;
    VIRProjArr := TDeepFramesAppService.ListProjects;
    if Length(VIRProjArr) > 0 then
      VIRPkgs := TDeepFramesAppService.ListCandidatePackages(VIRProjArr[0].ProjectId);
    var VIRCount := 0;
    SetLength(Result, Length(VIRJobs) + Length(VIRPkgs));
    for I := 0 to High(VIRJobs) do
    begin
      Result[VIRCount] := TShellObjectRef.Make(
        VIRJobs[I].VideoJobId, 'video_job', PROVIDER_DEEPFRAMES,
        VIRJobs[I].RunMode + ' [' + VIRJobs[I].Status + ']');
      Inc(VIRCount);
    end;
    for I := 0 to High(VIRPkgs) do
      if SameText(VIRPkgs[I].VideoIRId, ANode.Id) then
      begin
        Result[VIRCount] := TShellObjectRef.Make(
          VIRPkgs[I].PackageId, 'candidate_package', PROVIDER_DEEPFRAMES,
          VIRPkgs[I].&Label + ' [' + VIRPkgs[I].Status + ']');
        Inc(VIRCount);
      end;
    SetLength(Result, VIRCount);
  end
  else if SameText(ANode.Kind, 'video_job') then
  begin
    // Show video steps for this video job
    var VSteps := TDeepFramesAppService.ListVideoSteps(ANode.Id);
    SetLength(Result, Length(VSteps));
    for I := 0 to High(VSteps) do
      Result[I] := TShellObjectRef.Make(
        VSteps[I].VideoStepId, 'video_step', PROVIDER_DEEPFRAMES,
        VSteps[I].StepType + ' [' + VSteps[I].Status + ']');
  end
  else if SameText(ANode.Kind, 'extensions') then
  begin
    // Show BGM libraries and content type adapters
    var ExtLibraries := TDeepFramesAppService.ListBgmLibraries;
    var ExtAdapters := TDeepFramesAppService.ListContentTypeAdapters;
    var ExtCount := 0;
    SetLength(Result, Length(ExtLibraries) + Length(ExtAdapters));
    for I := 0 to High(ExtLibraries) do
    begin
      Result[ExtCount] := TShellObjectRef.Make(
        ExtLibraries[I].LibraryId, 'bgm_library', PROVIDER_DEEPFRAMES,
        'BGM: ' + ExtLibraries[I].Name + ' [' + ExtLibraries[I].Status + ']');
      Inc(ExtCount);
    end;
    for I := 0 to High(ExtAdapters) do
    begin
      Result[ExtCount] := TShellObjectRef.Make(
        ExtAdapters[I].AdapterId, 'content_type_adapter', PROVIDER_DEEPFRAMES,
        ExtAdapters[I].ContentType + ' [' + ExtAdapters[I].Status + ']');
      Inc(ExtCount);
    end;
    SetLength(Result, ExtCount);
  end
  else if SameText(ANode.Kind, 'bgm_library') then
  begin
    // Show tracks in this library
    var BgmTracks := TDeepFramesAppService.ListBgmTracks(ANode.Id);
    SetLength(Result, Length(BgmTracks));
    for I := 0 to High(BgmTracks) do
      Result[I] := TShellObjectRef.Make(
        BgmTracks[I].TrackId, 'bgm_track', PROVIDER_DEEPFRAMES,
        BgmTracks[I].Title + ' - ' + BgmTracks[I].Artist);
  end;
end;

function TDeepFramesStructureProvider.GetDisplayText(
  const ANode: TShellObjectRef): string;
begin
  Result := ANode.DisplayName;
end;

{ TDeepFramesMainViewProvider }

function TDeepFramesMainViewProvider.ProviderId: string;
begin
  Result := PROVIDER_DEEPFRAMES;
end;

function TDeepFramesMainViewProvider.CanOpen(const ARef: TShellObjectRef): Boolean;
begin
  Result := SameText(ARef.ProviderId, PROVIDER_DEEPFRAMES);
end;

function TDeepFramesMainViewProvider.GetViewForObject(
  const ARef: TShellObjectRef): TShellViewInfo;
begin
  Result := TShellViewInfo.Make('deepframes.' + ARef.Kind + '.' + ARef.Id,
    svkText, ARef.DisplayName,
    Format('DeepFrames object' + sLineBreak + sLineBreak + 'Kind: %s' + sLineBreak + 'Id: %s',
      [ARef.Kind, ARef.Id]));
end;

function TDeepFramesMainViewProvider.CreateViewControl(AOwner: TComponent;
  const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
begin
  Result := nil;
end;

{ TDeepFramesInspectorProvider }

function TDeepFramesInspectorProvider.ProviderId: string;
begin
  Result := PROVIDER_DEEPFRAMES;
end;

function TDeepFramesInspectorProvider.CanInspect(
  const ARef: TShellObjectRef): Boolean;
begin
  Result := SameText(ARef.ProviderId, PROVIDER_DEEPFRAMES);
end;

function TDeepFramesInspectorProvider.GetProperties(
  const ARef: TShellObjectRef): TArray<TShellProperty>;
var
  Projects: TArray<TProjectInfo>;
  ScriptDocs: TArray<TScriptDocumentVersion>;
  GateResults: TArray<TQualityGateResult>;
  I: Integer;
begin
  SetLength(Result, 4);
  Result[0].Name := 'Id'; Result[0].Value := ARef.Id; Result[0].Group := 'Identity'; Result[0].ReadOnly := True;
  Result[1].Name := 'Kind'; Result[1].Value := ARef.Kind; Result[1].Group := 'Identity'; Result[1].ReadOnly := True;
  Result[2].Name := 'Provider'; Result[2].Value := ARef.ProviderId; Result[2].Group := 'Identity'; Result[2].ReadOnly := True;
  Result[3].Name := 'Display'; Result[3].Value := ARef.DisplayName; Result[3].Group := 'Identity'; Result[3].ReadOnly := True;

  // Enrich inspector based on kind
  if SameText(ARef.Kind, 'script_document') then
  begin
    Projects := TDeepFramesAppService.ListProjects;
    for I := 0 to High(Projects) do
    begin
      ScriptDocs := TDeepFramesAppService.ListScriptDocuments(Projects[I].ProjectId);
      var J: Integer;
      for J := 0 to High(ScriptDocs) do
        if SameText(ScriptDocs[J].DocumentId, ARef.Id) then
        begin
          SetLength(Result, Length(Result) + 4);
          Result[Length(Result)-4].Name := 'version_no'; Result[Length(Result)-4].Value := IntToStr(ScriptDocs[J].VersionNo); Result[Length(Result)-4].Group := 'Document'; Result[Length(Result)-4].ReadOnly := True;
          Result[Length(Result)-3].Name := 'content_hash'; Result[Length(Result)-3].Value := Copy(ScriptDocs[J].ContentHash, 1, 16) + '...'; Result[Length(Result)-3].Group := 'Document'; Result[Length(Result)-3].ReadOnly := True;
          Result[Length(Result)-2].Name := 'source_document_id'; Result[Length(Result)-2].Value := Copy(ScriptDocs[J].SourceDocumentId, 1, 8) + '...'; Result[Length(Result)-2].Group := 'Relations'; Result[Length(Result)-2].ReadOnly := True;
          Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := ScriptDocs[J].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
          Break;
        end;
    end;
  end
  else if SameText(ARef.Kind, 'accuracy_report') then
  begin
    // Accuracy reports shown under script_document in the tree
    // We'll show the report_id based properties
    SetLength(Result, Length(Result) + 2);
    Result[Length(Result)-2].Name := 'coverage'; Result[Length(Result)-2].Value := '1.00'; Result[Length(Result)-2].Group := 'Quality'; Result[Length(Result)-2].ReadOnly := True;
    Result[Length(Result)-1].Name := 'distortion'; Result[Length(Result)-1].Value := '0.00'; Result[Length(Result)-1].Group := 'Quality'; Result[Length(Result)-1].ReadOnly := True;
  end
  else if SameText(ARef.Kind, 'variant_document') then
  begin
    SetLength(Result, Length(Result) + 2);
    Result[Length(Result)-2].Name := 'variant_kind'; Result[Length(Result)-2].Value := '(from tree)'; Result[Length(Result)-2].Group := 'Variant'; Result[Length(Result)-2].ReadOnly := True;
    Result[Length(Result)-1].Name := 'target_platform'; Result[Length(Result)-1].Value := '(from tree)'; Result[Length(Result)-1].Group := 'Variant'; Result[Length(Result)-1].ReadOnly := True;
  end
  else if SameText(ARef.Kind, 'shot_document') then
  begin
    SetLength(Result, Length(Result) + 2);
    Result[Length(Result)-2].Name := 'version_no'; Result[Length(Result)-2].Value := '1'; Result[Length(Result)-2].Group := 'Document'; Result[Length(Result)-2].ReadOnly := True;
    Result[Length(Result)-1].Name := 'parent'; Result[Length(Result)-1].Value := '(variant_document)'; Result[Length(Result)-1].Group := 'Relations'; Result[Length(Result)-1].ReadOnly := True;
  end
  else if SameText(ARef.Kind, 'job') then
  begin
    GateResults := TDeepFramesAppService.ListQualityGateResults(ARef.Id);
    if Length(GateResults) > 0 then
    begin
      SetLength(Result, Length(Result) + Length(GateResults));
      for I := 0 to High(GateResults) do
      begin
        Result[Length(Result) - Length(GateResults) + I].Name := GateResults[I].Gate;
        Result[Length(Result) - Length(GateResults) + I].Value := GateResults[I].GateResult + ' (score=' + FloatToStr(GateResults[I].Score) + ')';
        Result[Length(Result) - Length(GateResults) + I].Group := 'Quality Gates';
        Result[Length(Result) - Length(GateResults) + I].ReadOnly := True;
      end;
    end;
  end
  else if SameText(ARef.Kind, 'prompt_run') then
  begin
    // Find the prompt run by searching across all jobs
    var PRJobs: TArray<TDeepFramesJob>;
    PRJobs := TDeepFramesAppService.ListJobs;
    for I := 0 to High(PRJobs) do
    begin
      var PRs := TDeepFramesAppService.ListPromptRuns(PRJobs[I].JobId);
      var J: Integer;
      for J := 0 to High(PRs) do
        if SameText(PRs[J].RunId, ARef.Id) then
        begin
          SetLength(Result, Length(Result) + 6);
          Result[Length(Result)-6].Name := 'agent_role'; Result[Length(Result)-6].Value := PRs[J].AgentRole; Result[Length(Result)-6].Group := 'Agent'; Result[Length(Result)-6].ReadOnly := True;
          Result[Length(Result)-5].Name := 'provider'; Result[Length(Result)-5].Value := PRs[J].Provider; Result[Length(Result)-5].Group := 'Agent'; Result[Length(Result)-5].ReadOnly := True;
          Result[Length(Result)-4].Name := 'model'; Result[Length(Result)-4].Value := PRs[J].Model; Result[Length(Result)-4].Group := 'Agent'; Result[Length(Result)-4].ReadOnly := True;
          Result[Length(Result)-3].Name := 'tokens_in'; Result[Length(Result)-3].Value := IntToStr(PRs[J].TokenInput); Result[Length(Result)-3].Group := 'Metrics'; Result[Length(Result)-3].ReadOnly := True;
          Result[Length(Result)-2].Name := 'tokens_out'; Result[Length(Result)-2].Value := IntToStr(PRs[J].TokenOutput); Result[Length(Result)-2].Group := 'Metrics'; Result[Length(Result)-2].ReadOnly := True;
          Result[Length(Result)-1].Name := 'latency_ms'; Result[Length(Result)-1].Value := IntToStr(PRs[J].LatencyMs); Result[Length(Result)-1].Group := 'Metrics'; Result[Length(Result)-1].ReadOnly := True;
          Break;
        end;
    end;
  end
  else if SameText(ARef.Kind, 'eval_result') then
  begin
    var ERJobs: TArray<TDeepFramesJob>;
    ERJobs := TDeepFramesAppService.ListJobs;
    for I := 0 to High(ERJobs) do
    begin
      var Evals := TDeepFramesAppService.ListEvalResults(ERJobs[I].JobId);
      var J: Integer;
      for J := 0 to High(Evals) do
        if SameText(Evals[J].EvalId, ARef.Id) then
        begin
          SetLength(Result, Length(Result) + 4);
          Result[Length(Result)-4].Name := 'eval_type'; Result[Length(Result)-4].Value := Evals[J].EvalType; Result[Length(Result)-4].Group := 'Eval'; Result[Length(Result)-4].ReadOnly := True;
          Result[Length(Result)-3].Name := 'score'; Result[Length(Result)-3].Value := FloatToStrF(Evals[J].Score, ffFixed, 4, 2); Result[Length(Result)-3].Group := 'Eval'; Result[Length(Result)-3].ReadOnly := True;
          Result[Length(Result)-2].Name := 'gate'; Result[Length(Result)-2].Value := Evals[J].Gate; Result[Length(Result)-2].Group := 'Eval'; Result[Length(Result)-2].ReadOnly := True;
          Result[Length(Result)-1].Name := 'gate_result'; Result[Length(Result)-1].Value := Evals[J].GateResult; Result[Length(Result)-1].Group := 'Eval'; Result[Length(Result)-1].ReadOnly := True;
          Break;
        end;
    end;
  end
  else if SameText(ARef.Kind, 'audio_manifest') then
  begin
    // Find audio manifest by searching content units
    var AMProjects: TArray<TProjectInfo>;
    AMProjects := TDeepFramesAppService.ListProjects;
    for I := 0 to High(AMProjects) do
    begin
      var AMUnits := TDeepFramesAppService.ListContentUnits(AMProjects[I].ProjectId);
      var J: Integer;
      for J := 0 to High(AMUnits) do
      begin
        var AMs := TDeepFramesAppService.ListAudioManifests(AMUnits[J].ContentUnitId);
        var K: Integer;
        for K := 0 to High(AMs) do
          if SameText(AMs[K].ManifestId, ARef.Id) then
          begin
            SetLength(Result, Length(Result) + 8);
            Result[Length(Result)-8].Name := 'duration_sec'; Result[Length(Result)-8].Value := FloatToStrF(AMs[K].DurationSec, ffFixed, 4, 2); Result[Length(Result)-8].Group := 'Audio'; Result[Length(Result)-8].ReadOnly := True;
            Result[Length(Result)-7].Name := 'sample_rate'; Result[Length(Result)-7].Value := IntToStr(AMs[K].SampleRate); Result[Length(Result)-7].Group := 'Audio'; Result[Length(Result)-7].ReadOnly := True;
            Result[Length(Result)-6].Name := 'channels'; Result[Length(Result)-6].Value := IntToStr(AMs[K].Channels); Result[Length(Result)-6].Group := 'Audio'; Result[Length(Result)-6].ReadOnly := True;
            Result[Length(Result)-5].Name := 'codec'; Result[Length(Result)-5].Value := AMs[K].Codec; Result[Length(Result)-5].Group := 'Audio'; Result[Length(Result)-5].ReadOnly := True;
            Result[Length(Result)-4].Name := 'target_lufs'; Result[Length(Result)-4].Value := FloatToStrF(AMs[K].TargetLufs, ffFixed, 4, 1); Result[Length(Result)-4].Group := 'Loudnorm'; Result[Length(Result)-4].ReadOnly := True;
            Result[Length(Result)-3].Name := 'measured_lufs'; Result[Length(Result)-3].Value := FloatToStrF(AMs[K].MeasuredLufs, ffFixed, 4, 2); Result[Length(Result)-3].Group := 'Loudnorm'; Result[Length(Result)-3].ReadOnly := True;
            Result[Length(Result)-2].Name := 'concat_delta_ms'; Result[Length(Result)-2].Value := FloatToStrF(AMs[K].ConcatDurationDeltaMs, ffFixed, 4, 2); Result[Length(Result)-2].Group := 'Quality'; Result[Length(Result)-2].ReadOnly := True;
            Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := AMs[K].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
            Break;
          end;
      end;
    end;
  end
  else if SameText(ARef.Kind, 'video_ir') then
  begin
    // Find video IR by content unit
    var VIRProjArr: TArray<TProjectInfo>;
    VIRProjArr := TDeepFramesAppService.ListProjects;
    for I := 0 to High(VIRProjArr) do
    begin
      var VIRUnits := TDeepFramesAppService.ListContentUnits(VIRProjArr[I].ProjectId);
      var J: Integer;
      for J := 0 to High(VIRUnits) do
      begin
        var VIRs := TDeepFramesAppService.ListVideoIRs(VIRUnits[J].ContentUnitId);
        var K: Integer;
        for K := 0 to High(VIRs) do
          if SameText(VIRs[K].VideoIRId, ARef.Id) then
          begin
            SetLength(Result, Length(Result) + 7);
            Result[Length(Result)-7].Name := 'render_backend'; Result[Length(Result)-7].Value := VIRs[K].RenderBackend; Result[Length(Result)-7].Group := 'Video IR'; Result[Length(Result)-7].ReadOnly := True;
            Result[Length(Result)-6].Name := 'scene_count'; Result[Length(Result)-6].Value := IntToStr(VIRs[K].SceneCount); Result[Length(Result)-6].Group := 'Video IR'; Result[Length(Result)-6].ReadOnly := True;
            Result[Length(Result)-5].Name := 'duration_source'; Result[Length(Result)-5].Value := VIRs[K].DurationSource; Result[Length(Result)-5].Group := 'Duration'; Result[Length(Result)-5].ReadOnly := True;
            Result[Length(Result)-4].Name := 'estimated_sec'; Result[Length(Result)-4].Value := FloatToStrF(VIRs[K].EstimatedDurationSec, ffFixed, 4, 2); Result[Length(Result)-4].Group := 'Duration'; Result[Length(Result)-4].ReadOnly := True;
            Result[Length(Result)-3].Name := 'actual_sec'; Result[Length(Result)-3].Value := FloatToStrF(VIRs[K].ActualDurationSec, ffFixed, 4, 2); Result[Length(Result)-3].Group := 'Duration'; Result[Length(Result)-3].ReadOnly := True;
            Result[Length(Result)-2].Name := 'version_no'; Result[Length(Result)-2].Value := IntToStr(VIRs[K].VersionNo); Result[Length(Result)-2].Group := 'Version'; Result[Length(Result)-2].ReadOnly := True;
            Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := VIRs[K].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
            Break;
          end;
      end;
    end;
  end
  else if SameText(ARef.Kind, 'video_job') then
  begin
    // Find video job by video IR
    var VJProjArr: TArray<TProjectInfo>;
    VJProjArr := TDeepFramesAppService.ListProjects;
    for I := 0 to High(VJProjArr) do
    begin
      var VJUnits := TDeepFramesAppService.ListContentUnits(VJProjArr[I].ProjectId);
      var J: Integer;
      for J := 0 to High(VJUnits) do
      begin
        var VJIRs := TDeepFramesAppService.ListVideoIRs(VJUnits[J].ContentUnitId);
        var K: Integer;
        for K := 0 to High(VJIRs) do
        begin
          var VJobs := TDeepFramesAppService.ListVideoJobs(VJIRs[K].VideoIRId);
          var L: Integer;
          for L := 0 to High(VJobs) do
            if SameText(VJobs[L].VideoJobId, ARef.Id) then
            begin
              SetLength(Result, Length(Result) + 5);
              Result[Length(Result)-5].Name := 'render_backend'; Result[Length(Result)-5].Value := VJobs[L].RenderBackend; Result[Length(Result)-5].Group := 'Video'; Result[Length(Result)-5].ReadOnly := True;
              Result[Length(Result)-4].Name := 'run_mode'; Result[Length(Result)-4].Value := VJobs[L].RunMode; Result[Length(Result)-4].Group := 'Video'; Result[Length(Result)-4].ReadOnly := True;
              Result[Length(Result)-3].Name := 'template_id'; Result[Length(Result)-3].Value := VJobs[L].TemplateId; Result[Length(Result)-3].Group := 'Video'; Result[Length(Result)-3].ReadOnly := True;
              Result[Length(Result)-2].Name := 'output_dir'; Result[Length(Result)-2].Value := VJobs[L].OutputDir; Result[Length(Result)-2].Group := 'Output'; Result[Length(Result)-2].ReadOnly := True;
              Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := VJobs[L].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
              Break;
            end;
        end;
      end;
    end;
  end
  else if SameText(ARef.Kind, 'video_step') then
  begin
    // Find video step by searching video jobs
    var VSProjArr: TArray<TProjectInfo>;
    VSProjArr := TDeepFramesAppService.ListProjects;
    for I := 0 to High(VSProjArr) do
    begin
      var VSUnits := TDeepFramesAppService.ListContentUnits(VSProjArr[I].ProjectId);
      var J: Integer;
      for J := 0 to High(VSUnits) do
      begin
        var VSIRs := TDeepFramesAppService.ListVideoIRs(VSUnits[J].ContentUnitId);
        var K: Integer;
        for K := 0 to High(VSIRs) do
        begin
          var VSJobs := TDeepFramesAppService.ListVideoJobs(VSIRs[K].VideoIRId);
          var L: Integer;
          for L := 0 to High(VSJobs) do
          begin
            var VSteps := TDeepFramesAppService.ListVideoSteps(VSJobs[L].VideoJobId);
            var M: Integer;
            for M := 0 to High(VSteps) do
              if SameText(VSteps[M].VideoStepId, ARef.Id) then
              begin
                SetLength(Result, Length(Result) + 5);
                Result[Length(Result)-5].Name := 'step_type'; Result[Length(Result)-5].Value := VSteps[M].StepType; Result[Length(Result)-5].Group := 'Step'; Result[Length(Result)-5].ReadOnly := True;
                Result[Length(Result)-4].Name := 'step_key'; Result[Length(Result)-4].Value := Copy(VSteps[M].StepKey, 1, 40) + '...'; Result[Length(Result)-4].Group := 'Step'; Result[Length(Result)-4].ReadOnly := True;
                Result[Length(Result)-3].Name := 'error_message'; Result[Length(Result)-3].Value := VSteps[M].ErrorMessage; Result[Length(Result)-3].Group := 'Error'; Result[Length(Result)-3].ReadOnly := True;
                Result[Length(Result)-2].Name := 'metrics'; Result[Length(Result)-2].Value := Copy(VSteps[M].MetricsJson, 1, 60) + '...'; Result[Length(Result)-2].Group := 'Metrics'; Result[Length(Result)-2].ReadOnly := True;
                Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := VSteps[M].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
                Break;
              end;
          end;
        end;
      end;
    end;
  end
  else if SameText(ARef.Kind, 'candidate_package') then
  begin
    // Find candidate package
    var CPPkgProjArr: TArray<TProjectInfo>;
    CPPkgProjArr := TDeepFramesAppService.ListProjects;
    for I := 0 to High(CPPkgProjArr) do
    begin
      var CPPkgs := TDeepFramesAppService.ListCandidatePackages(CPPkgProjArr[I].ProjectId);
      var J: Integer;
      for J := 0 to High(CPPkgs) do
        if SameText(CPPkgs[J].PackageId, ARef.Id) then
        begin
          SetLength(Result, Length(Result) + 8);
          Result[Length(Result)-8].Name := 'label'; Result[Length(Result)-8].Value := CPPkgs[J].&Label; Result[Length(Result)-8].Group := 'Package'; Result[Length(Result)-8].ReadOnly := True;
          Result[Length(Result)-7].Name := 'target_platform'; Result[Length(Result)-7].Value := CPPkgs[J].TargetPlatform; Result[Length(Result)-7].Group := 'Package'; Result[Length(Result)-7].ReadOnly := True;
          Result[Length(Result)-6].Name := 'delivery_type'; Result[Length(Result)-6].Value := CPPkgs[J].DeliveryType; Result[Length(Result)-6].Group := 'Package'; Result[Length(Result)-6].ReadOnly := True;
          Result[Length(Result)-5].Name := 'output_root'; Result[Length(Result)-5].Value := CPPkgs[J].OutputRootUri; Result[Length(Result)-5].Group := 'Output'; Result[Length(Result)-5].ReadOnly := True;
          Result[Length(Result)-4].Name := 'version_no'; Result[Length(Result)-4].Value := IntToStr(CPPkgs[J].VersionNo); Result[Length(Result)-4].Group := 'Version'; Result[Length(Result)-4].ReadOnly := True;
          Result[Length(Result)-3].Name := 'variant_doc'; Result[Length(Result)-3].Value := Copy(CPPkgs[J].VariantDocumentId, 1, 8) + '...'; Result[Length(Result)-3].Group := 'Sources'; Result[Length(Result)-3].ReadOnly := True;
          Result[Length(Result)-2].Name := 'video_ir'; Result[Length(Result)-2].Value := Copy(CPPkgs[J].VideoIRId, 1, 8) + '...'; Result[Length(Result)-2].Group := 'Sources'; Result[Length(Result)-2].ReadOnly := True;
          Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := CPPkgs[J].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
          Break;
        end;
    end;
  end
  else if SameText(ARef.Kind, 'bgm_library') then
  begin
    var BgmLibs := TDeepFramesAppService.ListBgmLibraries;
    for I := 0 to High(BgmLibs) do
      if SameText(BgmLibs[I].LibraryId, ARef.Id) then
      begin
        SetLength(Result, Length(Result) + 3);
        Result[Length(Result)-3].Name := 'name'; Result[Length(Result)-3].Value := BgmLibs[I].Name; Result[Length(Result)-3].Group := 'Library'; Result[Length(Result)-3].ReadOnly := True;
        Result[Length(Result)-2].Name := 'is_default'; Result[Length(Result)-2].Value := BoolToStr(BgmLibs[I].IsDefault, True); Result[Length(Result)-2].Group := 'Library'; Result[Length(Result)-2].ReadOnly := True;
        Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := BgmLibs[I].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
        Break;
      end;
  end
  else if SameText(ARef.Kind, 'bgm_track') then
  begin
    // Find BGM track by searching libraries
    var BTLibs := TDeepFramesAppService.ListBgmLibraries;
    for I := 0 to High(BTLibs) do
    begin
      var BTTracks := TDeepFramesAppService.ListBgmTracks(BTLibs[I].LibraryId);
      var J: Integer;
      for J := 0 to High(BTTracks) do
        if SameText(BTTracks[J].TrackId, ARef.Id) then
        begin
          SetLength(Result, Length(Result) + 8);
          Result[Length(Result)-8].Name := 'title'; Result[Length(Result)-8].Value := BTTracks[J].Title; Result[Length(Result)-8].Group := 'Track'; Result[Length(Result)-8].ReadOnly := True;
          Result[Length(Result)-7].Name := 'artist'; Result[Length(Result)-7].Value := BTTracks[J].Artist; Result[Length(Result)-7].Group := 'Track'; Result[Length(Result)-7].ReadOnly := True;
          Result[Length(Result)-6].Name := 'genre'; Result[Length(Result)-6].Value := BTTracks[J].Genre; Result[Length(Result)-6].Group := 'Track'; Result[Length(Result)-6].ReadOnly := True;
          Result[Length(Result)-5].Name := 'duration_sec'; Result[Length(Result)-5].Value := FloatToStrF(BTTracks[J].DurationSec, ffFixed, 4, 1); Result[Length(Result)-5].Group := 'Audio'; Result[Length(Result)-5].ReadOnly := True;
          Result[Length(Result)-4].Name := 'bpm'; Result[Length(Result)-4].Value := IntToStr(BTTracks[J].Bpm); Result[Length(Result)-4].Group := 'Audio'; Result[Length(Result)-4].ReadOnly := True;
          Result[Length(Result)-3].Name := 'key_signature'; Result[Length(Result)-3].Value := BTTracks[J].KeySignature; Result[Length(Result)-3].Group := 'Audio'; Result[Length(Result)-3].ReadOnly := True;
          Result[Length(Result)-2].Name := 'license'; Result[Length(Result)-2].Value := BTTracks[J].LicenseType; Result[Length(Result)-2].Group := 'License'; Result[Length(Result)-2].ReadOnly := True;
          Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := BTTracks[J].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
          Break;
        end;
    end;
  end
  else if SameText(ARef.Kind, 'content_type_adapter') then
  begin
    var CTAdapters := TDeepFramesAppService.ListContentTypeAdapters;
    for I := 0 to High(CTAdapters) do
      if SameText(CTAdapters[I].AdapterId, ARef.Id) then
      begin
        SetLength(Result, Length(Result) + 5);
        Result[Length(Result)-5].Name := 'content_type'; Result[Length(Result)-5].Value := CTAdapters[I].ContentType; Result[Length(Result)-5].Group := 'Adapter'; Result[Length(Result)-5].ReadOnly := True;
        Result[Length(Result)-4].Name := 'display_name'; Result[Length(Result)-4].Value := CTAdapters[I].DisplayName; Result[Length(Result)-4].Group := 'Adapter'; Result[Length(Result)-4].ReadOnly := True;
        Result[Length(Result)-3].Name := 'adapter_class'; Result[Length(Result)-3].Value := CTAdapters[I].AdapterClass; Result[Length(Result)-3].Group := 'Adapter'; Result[Length(Result)-3].ReadOnly := True;
        Result[Length(Result)-2].Name := 'version_no'; Result[Length(Result)-2].Value := IntToStr(CTAdapters[I].VersionNo); Result[Length(Result)-2].Group := 'Version'; Result[Length(Result)-2].ReadOnly := True;
        Result[Length(Result)-1].Name := 'status'; Result[Length(Result)-1].Value := CTAdapters[I].Status; Result[Length(Result)-1].Group := 'Status'; Result[Length(Result)-1].ReadOnly := True;
        Break;
      end;
  end;
end;

function TDeepFramesInspectorProvider.GetRelations(
  const ARef: TShellObjectRef): TArray<TShellRelation>;
begin
  Result := nil;
end;

function TDeepFramesInspectorProvider.GetIssues(
  const ARef: TShellObjectRef): TArray<TShellIssue>;
begin
  Result := nil;
end;

{ TMainForm }

procedure TMainForm.RegisterServices;
begin
  inherited;
  FSettingsStore := TDeepFramesSettingsStore.Create;
  Services.RegisterService(CAP_SHELL_SETTINGS, FSettingsStore);
  Services.RegisterService(CAP_SHELL_LAYOUT,
    TShellSettingsBackedLayoutService.Create(FSettingsStore, 'DeepFrames') as IInterface);
end;

procedure TMainForm.RegisterCommands;
begin
  inherited;
  Commands.RegisterCommand(ShellCommand(CMD_PROJECT_NEW, 'New Project')
    .Category('DeepFrames').Hint('Create a Phase 1 DeepFrames project').RiskLevel(rlLow).OnExecute(CmdNewProject));
  Commands.RegisterCommand(ShellCommand(CMD_PROJECT_IMPORT, 'Import Markdown')
    .Category('DeepFrames').Hint('Import markdown as source_document').RiskLevel(rlLow).OnExecute(CmdImportMarkdown));
  Commands.RegisterCommand(ShellCommand(CMD_PREPROCESS_RUN, 'Run Preprocess')
    .Category('DeepFrames').Hint('Create and complete a local preprocess job').RiskLevel(rlLow).OnExecute(CmdRunPreprocess));
  Commands.RegisterCommand(ShellCommand(CMD_DOCUMENT_CHAIN_RUN, 'Run Document Chain')
    .Category('DeepFrames').Hint('Run the Phase 2 document chain workflow (stub data)').RiskLevel(rlLow).OnExecute(CmdRunDocumentChain));
  Commands.RegisterCommand(ShellCommand(CMD_AGENT_CHAIN_RUN, 'Run Agent Chain')
    .Category('DeepFrames').Hint('Run the Phase 3 agent chain workflow (fake provider)').RiskLevel(rlLow).OnExecute(CmdRunAgentChain));
  Commands.RegisterCommand(ShellCommand(CMD_AUDIO_CHAIN_RUN, 'Run Audio Chain')
    .Category('DeepFrames').Hint('Run the Phase 4 audio chain workflow (fake TTS/ASR)').RiskLevel(rlLow).OnExecute(CmdRunAudioChain));
  Commands.RegisterCommand(ShellCommand(CMD_VIDEO_CHAIN_RUN, 'Run Video Chain')
    .Category('DeepFrames').Hint('Run the Phase 5 video chain workflow (fake HyperFrames)').RiskLevel(rlLow).OnExecute(CmdRunVideoChain));
  Commands.RegisterCommand(ShellCommand(CMD_PACKAGE_CHAIN_RUN, 'Run Package Chain')
    .Category('DeepFrames').Hint('Run the Phase 6 candidate package workflow').RiskLevel(rlLow).OnExecute(CmdRunPackageChain));
  Commands.RegisterCommand(ShellCommand(CMD_EXTENSION_CHAIN_RUN, 'Run Extension Chain')
    .Category('DeepFrames').Hint('Run the Phase 7 extension chain (adapters, BGM, readiness)').RiskLevel(rlLow).OnExecute(CmdRunExtensionChain));
  Commands.RegisterCommand(ShellCommand(CMD_PROVIDER_SWITCH, 'Switch AI Provider')
    .Category('DeepFrames').Hint('Toggle between fake and stepfun providers').RiskLevel(rlMedium).OnExecute(CmdSwitchProvider));
  Commands.RegisterCommand(ShellCommand(CMD_DB2_TEST, 'Test DB2 Connection')
    .Category('DeepFrames').Hint('Open the configured PostgreSQL connection').RiskLevel(rlReadOnly).OnExecute(CmdTestDb2));
  Commands.RegisterCommand(ShellCommand(CMD_DB2_MIGRATE, 'Run DB2 Migration')
    .Category('DeepFrames').Hint('Apply PostgreSQL migrations').RiskLevel(rlMedium).OnExecute(CmdRunMigrations));
end;

procedure TMainForm.RegisterProviders;
begin
  inherited;
  RegisterStructureProvider(TDeepFramesStructureProvider.Create);
  RegisterMainViewProvider(TDeepFramesMainViewProvider.Create);
  RegisterInspectorProvider(TDeepFramesInspectorProvider.Create);
  RegisterSettingsPageProvider(TDeepFramesSettingsPageProvider.Create);
end;

procedure TMainForm.AfterShellShown;
begin
  inherited;
  Caption := 'DeepFrames';
  Status.Info('deepframes.boot',
    'DeepFrames Phase 1-7 shell is ready. Provider: ' +
    TProviderRegistry.Instance.ActiveProviderName +
    '. Configure DB2, run migrations, then create a project and run workflows.');
  OpenView(TShellObjectRef.Make('welcome', 'setup', PROVIDER_DEEPFRAMES, 'DeepFrames'));
end;

procedure TMainForm.CmdNewProject;
var
  Title: string;
  Project: TProjectInfo;
begin
  Title := 'DeepFrames Project';
  if not InputQuery('New Project', 'Project title', Title) then
    Exit;

  Project := TDeepFramesAppService.CreateProject(Title);

  Status.Info('deepframes.project', 'Created project: ' + Project.Title);
  OpenProject(Project.ProjectId, Project.Title);
  RefreshProjectView;
end;

procedure TMainForm.CmdImportMarkdown;
var
  FileName: string;
  Doc: TSourceDocumentVersion;
begin
  FileName := '';
  if not PromptForFileName(FileName, 'Markdown files (*.md)|*.md|Text files (*.txt)|*.txt|All files (*.*)|*.*', '',
    'Import Markdown', '', False) then
    Exit;

  Doc := TDeepFramesAppService.ImportMarkdown(FileName);

  Status.Info('deepframes.import', 'Imported source_document: ' + ExtractFileName(FileName));
  RefreshProjectView;
end;

procedure TMainForm.CmdRunPreprocess;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('preprocess', 'deepframes.workflow', 'Running local Phase 1 preprocess');
  Job := TDeepFramesAppService.RunPreprocess;
  Status.TaskFinish('preprocess', 'Preprocess completed: ' + Job.Status);
  RefreshProjectView;
end;

procedure TMainForm.CmdRunDocumentChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('docchain', 'deepframes.workflow', 'Running Phase 2 document chain (stub data)');
  try
    Job := TDeepFramesAppService.RunDocumentChain;
    Status.TaskFinish('docchain', 'Document chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.docchain', 'Document chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdRunAgentChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('agentchain', 'deepframes.workflow', 'Running Phase 3 agent chain (fake provider)');
  try
    Job := TDeepFramesAppService.RunAgentChain;
    Status.TaskFinish('agentchain', 'Agent chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.agentchain', 'Agent chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdRunAudioChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('audiochain', 'deepframes.workflow', 'Running Phase 4 audio chain (fake TTS/ASR)');
  try
    Job := TDeepFramesAppService.RunAudioChain;
    Status.TaskFinish('audiochain', 'Audio chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.audiochain', 'Audio chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdRunVideoChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('videochain', 'deepframes.workflow', 'Running Phase 5 video chain (fake HyperFrames)');
  try
    Job := TDeepFramesAppService.RunVideoChain;
    Status.TaskFinish('videochain', 'Video chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.videochain', 'Video chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdRunPackageChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('packagechain', 'deepframes.workflow', 'Running Phase 6 candidate package workflow');
  try
    Job := TDeepFramesAppService.RunPackageChain;
    Status.TaskFinish('packagechain', 'Package chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.packagechain', 'Package chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdRunExtensionChain;
var
  Job: TDeepFramesJob;
begin
  Status.TaskStart('extensionchain', 'deepframes.workflow', 'Running Phase 7 extension chain');
  try
    Job := TDeepFramesAppService.RunExtensionChain;
    Status.TaskFinish('extensionchain', 'Extension chain completed: ' + Job.JobType + ' [' + Job.Status + ']');
  except
    on E: Exception do
    begin
      Status.LogError('deepframes.extensionchain', 'Extension chain failed', E.Message);
      Exit;
    end;
  end;
  RefreshProjectView;
end;

procedure TMainForm.CmdSwitchProvider;
var
  CurrentName, TargetName: string;
begin
  CurrentName := TProviderRegistry.Instance.ActiveProviderName;
  if SameText(CurrentName, PROVIDER_FAKE) then
    TargetName := PROVIDER_STEPFUN
  else
    TargetName := PROVIDER_FAKE;

  try
    TProviderRegistry.Instance.SwitchTo(TargetName);
    Status.Info('deepframes.provider',
      'Switched AI provider: ' + CurrentName + ' → ' + TargetName);
  except
    on E: Exception do
      Status.LogError('deepframes.provider', 'Provider switch failed', E.Message);
  end;
end;

procedure TMainForm.CmdTestDb2;
var
  Error: string;
begin
  if TDeepFramesAppService.TestDb2Connection(Error) then
    Status.Info('deepframes.db2', 'DB2 PostgreSQL connection OK')
  else
    Status.LogError('deepframes.db2', 'DB2 PostgreSQL connection failed', Error);
end;

procedure TMainForm.CmdRunMigrations;
var
  Applied, Skipped: Integer;
  Error: string;
begin
  if TDeepFramesAppService.RunDb2Migrations(Applied, Skipped, Error) then
    Status.Info('deepframes.db2', Format('Migrations complete. Applied=%d Skipped=%d',
      [Applied, Skipped]))
  else
    Status.LogError('deepframes.db2', 'Migration failed', Error);
end;

procedure TMainForm.RefreshProjectView;
begin
  OpenView(TShellObjectRef.Make('refresh', 'setup', PROVIDER_DEEPFRAMES,
    'Refresh structure from View / Structure Window'));
end;

end.
