program DeepFrames;

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  FireDAC.VCLUI.Wait,
  DeepBase.AutoFix,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.Persistence.Manager.FireDAC,
  DeepBase.Security,
  DeepBase.AutoFix.ErrorRecorder,
  DeepBase.AutoFix.VclHook,
  DeepFrames.App.Bootstrap in 'App\DeepFrames.App.Bootstrap.pas',
  DeepFrames.App.Constants in 'App\DeepFrames.App.Constants.pas',
  DeepFrames.App.Services in 'App\DeepFrames.App.Services.pas',
  DeepFrames.Shared.Consts in 'Shared\DeepFrames.Shared.Consts.pas',
  DeepFrames.Shared.JsonSchema in 'Shared\DeepFrames.Shared.JsonSchema.pas',
  DeepFrames.Shared.Tools in 'Shared\DeepFrames.Shared.Tools.pas',
  DeepFrames.Domain.Types in 'Domain\DeepFrames.Domain.Types.pas',
  DeepFrames.Domain.Project in 'Domain\DeepFrames.Domain.Project.pas',
  DeepFrames.Domain.VoiceProfile in 'Domain\DeepFrames.Domain.VoiceProfile.pas',
  DeepFrames.Persistence.Connection in 'Persistence\DeepFrames.Persistence.Connection.pas',
  DeepFrames.Persistence.Migrations in 'Persistence\DeepFrames.Persistence.Migrations.pas',
  DeepFrames.Persistence.Repository in 'Persistence\DeepFrames.Persistence.Repository.pas',
  DeepFrames.Persistence.Repository.Base in 'Persistence\DeepFrames.Persistence.Repository.Base.pas',
  DeepFrames.Persistence.Repository.Shared in 'Persistence\DeepFrames.Persistence.Repository.Shared.pas',
  DeepFrames.Persistence.Repository.Job in 'Persistence\DeepFrames.Persistence.Repository.Job.pas',
  DeepFrames.Persistence.Repository.Project in 'Persistence\DeepFrames.Persistence.Repository.Project.pas',
  DeepFrames.Persistence.Repository.ContentUnit in 'Persistence\DeepFrames.Persistence.Repository.ContentUnit.pas',
  DeepFrames.Persistence.Repository.SourceDocument in 'Persistence\DeepFrames.Persistence.Repository.SourceDocument.pas',
  DeepFrames.Persistence.Repository.ScriptDocument in 'Persistence\DeepFrames.Persistence.Repository.ScriptDocument.pas',
  DeepFrames.Persistence.Repository.AccuracyReport in 'Persistence\DeepFrames.Persistence.Repository.AccuracyReport.pas',
  DeepFrames.Workflow.Preprocess in 'Workflow\DeepFrames.Workflow.Preprocess.pas',
  DeepFrames.Workflow.DocumentChain in 'Workflow\DeepFrames.Workflow.DocumentChain.pas',
  DeepFrames.Workflow.AgentChain in 'Workflow\DeepFrames.Workflow.AgentChain.pas',
  DeepFrames.Workflow.AudioChain in 'Workflow\DeepFrames.Workflow.AudioChain.pas',
  DeepFrames.Workflow.VideoChain in 'Workflow\DeepFrames.Workflow.VideoChain.pas',
  DeepFrames.Workflow.PackageChain in 'Workflow\DeepFrames.Workflow.PackageChain.pas',
  DeepFrames.Workflow.ExtensionChain in 'Workflow\DeepFrames.Workflow.ExtensionChain.pas',
  DeepFrames.Provider.Types in 'Provider\DeepFrames.Provider.Types.pas',
  DeepFrames.Provider.Intf in 'Provider\DeepFrames.Provider.Intf.pas',
  DeepFrames.Provider.Registry in 'Provider\DeepFrames.Provider.Registry.pas',
  DeepFrames.Provider.Fake in 'Provider\DeepFrames.Provider.Fake.pas',
  DeepFrames.Provider.StepFun in 'Provider\DeepFrames.Provider.StepFun.pas',
  DeepFrames.Provider.StepFun.Shared in 'Provider\DeepFrames.Provider.StepFun.Shared.pas',
  DeepFrames.Provider.StepFun.LLM in 'Provider\DeepFrames.Provider.StepFun.LLM.pas',
  DeepFrames.Provider.StepFun.TTS in 'Provider\DeepFrames.Provider.StepFun.TTS.pas',
  DeepFrames.Provider.StepFun.ASR in 'Provider\DeepFrames.Provider.StepFun.ASR.pas',
  DeepFrames.Provider.StepFun.Image in 'Provider\DeepFrames.Provider.StepFun.Image.pas',
  DeepFrames.Provider.Agnes in 'Provider\DeepFrames.Provider.Agnes.pas',
  DeepFrames.Provider.Agnes.Shared in 'Provider\DeepFrames.Provider.Agnes.Shared.pas',
  DeepFrames.Provider.Agnes.LLM in 'Provider\DeepFrames.Provider.Agnes.LLM.pas',
  DeepFrames.Provider.Agnes.Image in 'Provider\DeepFrames.Provider.Agnes.Image.pas',
  DeepFrames.Provider.Agnes.Video in 'Provider\DeepFrames.Provider.Agnes.Video.pas',
  DeepFrames.Provider.Baidu in 'Provider\DeepFrames.Provider.Baidu.pas',
  DeepFrames.Provider.Gemini in 'Provider\DeepFrames.Provider.Gemini.pas',
  DeepFrames.Provider.Gemini.Shared in 'Provider\DeepFrames.Provider.Gemini.Shared.pas',
  DeepFrames.Provider.Gemini.LLM in 'Provider\DeepFrames.Provider.Gemini.LLM.pas',
  DeepFrames.Provider.Gemini.TTS in 'Provider\DeepFrames.Provider.Gemini.TTS.pas',
  DeepFrames.Provider.Gemini.ASR in 'Provider\DeepFrames.Provider.Gemini.ASR.pas',
  DeepFrames.Provider.Failover in 'Provider\DeepFrames.Provider.Failover.pas',
  DeepFrames.Workflow.VideoCompiler in 'Workflow\DeepFrames.Workflow.VideoCompiler.pas',
  DeepFrames.Workflow.GateEvaluator in 'Workflow\DeepFrames.Workflow.GateEvaluator.pas',
  DeepFrames.Workflow.BudgetGuard in 'Workflow\DeepFrames.Workflow.BudgetGuard.pas',
  DeepFrames.Workflow.StyleKeeper in 'Workflow\DeepFrames.Workflow.StyleKeeper.pas',
  DeepFrames.Workflow.Resume in 'Workflow\DeepFrames.Workflow.Resume.pas',
  DeepFrames.Workflow.PromptVersion in 'Workflow\DeepFrames.Workflow.PromptVersion.pas',
  DeepFrames.Workflow.AudioProcessor in 'Workflow\DeepFrames.Workflow.AudioProcessor.pas',
  DeepFrames.Workflow.YtDlpDownloader in 'Workflow\DeepFrames.Workflow.YtDlpDownloader.pas',
  DeepFrames.Workflow.ExternalVideoImportChain in 'Workflow\DeepFrames.Workflow.ExternalVideoImportChain.pas',
  DeepFrames.Workflow.SubtitleEngine in 'Workflow\DeepFrames.Workflow.SubtitleEngine.pas',
  DeepFrames.Workflow.AssetRetention in 'Workflow\DeepFrames.Workflow.AssetRetention.pas',
  DeepFrames.Workflow.PackageExporter in 'Workflow\DeepFrames.Workflow.PackageExporter.pas',
  DeepFrames.Workflow.WorkerProtocol in 'Workflow\DeepFrames.Workflow.WorkerProtocol.pas',
  DeepFrames.Workflow.ReadinessChecker in 'Workflow\DeepFrames.Workflow.ReadinessChecker.pas',
  DeepFrames.Workflow.DocumentExport in 'Workflow\DeepFrames.Workflow.DocumentExport.pas',
  DeepFrames.Workflow.BgmManager in 'Workflow\DeepFrames.Workflow.BgmManager.pas',
  DeepFrames.Workflow.SubtitleTransformEngine in 'Workflow\DeepFrames.Workflow.SubtitleTransformEngine.pas',
  DeepFrames.Workflow.SubtitleQcEngine in 'Workflow\DeepFrames.Workflow.SubtitleQcEngine.pas',
  DeepFrames.Workflow.VideoTranscoder in 'Workflow\DeepFrames.Workflow.VideoTranscoder.pas',
  DeepFrames.Workflow.NotificationChain in 'Workflow\DeepFrames.Workflow.NotificationChain.pas',
  DeepFrames.Workflow.CookieCloudSync in 'Workflow\DeepFrames.Workflow.CookieCloudSync.pas',
  DeepFrames.Workflow.ChunkedUploader in 'Workflow\DeepFrames.Workflow.ChunkedUploader.pas',
  DeepFrames.Workflow.ArtifactOSBridge in 'Workflow\DeepFrames.Workflow.ArtifactOSBridge.pas',
  DeepFrames.Workflow.CommercialExporter in 'Workflow\DeepFrames.Workflow.CommercialExporter.pas',
  DeepFrames.Workflow.EventLog in 'Workflow\DeepFrames.Workflow.EventLog.pas',
  DeepFrames.UI.MainForm in 'UI\DeepFrames.UI.MainForm.pas' {MainForm};

{$R *.res}

begin
  // AutoFix: record runtime exceptions for self-healing (before Init to catch init errors too)
  TAutoFixErrorRecorder.Install;
  TAutoFixVclHook.Install;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  DeepBase.Manager.DeepBase.InitializeOrRaise;

  // AutoFix: register smoke scenario for self-healing loop.
  // ChainE2E.exe is the comprehensive E2E test; this smoke is a fast health probe.
  AutoFix.RegisterScenario('smoke',
    procedure
    var
      Err: string;
    begin
      if not TDeepFramesDB2Connection.TestConnection(Err) then
        raise Exception.Create('DB2 connection test failed: ' + Err);
    end);

  try
    TDeepFramesBootstrap.RegisterServices;

    // CLI helper: DeepFrames.exe --set-secret <name> <value>
    // Stores a DPAPI-encrypted secret under the current Windows user, so the
    // smoke scenario (running as the same user) can decrypt it. Used to seed
    // DB2.PasswordSecretRef = secret://deepframes/db2 with the PG password.
    // NOTE: must run AFTER RegisterServices — that is where the SQLite config
    // DB is opened and the DeepBase.Security service (which backs SaveSecret)
    // is constructed. Running it earlier was a silent no-op (Security=nil),
    // so the secret never landed in the Secrets table and smoke stayed red.
    if (ParamCount >= 3) and SameText(ParamStr(1), '--set-secret') then
    begin
      SaveSecret(ParamStr(2), ParamStr(3), 'set via --set-secret');
      if SecretExists(ParamStr(2)) then
        WriteLn('OK: secret saved ' + ParamStr(2))
      else
      begin
        WriteLn('ERROR: secret save failed (Security service not available) ' + ParamStr(2));
        Halt(1);
      end;
      Halt(0);
    end;

    // CLI helper: DeepFrames.exe --set-secret-file <name> <path>
    // Same as --set-secret but reads the value from a file. Required for
    // multi-line secrets (e.g. deepframes/baidu/asr_key = "APIKey\nSecretKey")
    // where the OS command line mangles embedded newlines and the value lands
    // truncated/garbled. File is read as UTF-8, then DPAPI-encrypted and stored
    // in the Secrets table exactly like --set-secret.
    if (ParamCount >= 3) and SameText(ParamStr(1), '--set-secret-file') then
    begin
      var FPath := ParamStr(3);
      if not TFile.Exists(FPath) then
      begin
        WriteLn('ERROR: secret file not found: ' + FPath);
        Halt(1);
      end;
      var FVal := TFile.ReadAllText(FPath, TEncoding.UTF8);
      SaveSecret(ParamStr(2), FVal, 'set via --set-secret-file');
      if SecretExists(ParamStr(2)) then
        WriteLn('OK: secret saved (from file) ' + ParamStr(2))
      else
      begin
        WriteLn('ERROR: secret save failed (Security service not available) ' + ParamStr(2));
        Halt(1);
      end;
      Halt(0);
    end;

    // TEMP (DBA-1 verification): DeepFrames.exe --verify-secret <name>
    // Read-only: decrypts a secret and prints length + masked head/tail of each
    // split line, so we can prove LoadSecret round-trips a stored secret without
    // printing plaintext. Remove once DBA-1 acceptance is signed off.
    if (ParamCount >= 2) and SameText(ParamStr(1), '--verify-secret') then
    begin
      var SName := ParamStr(2);
      var SVal := '';
      try
        SVal := LoadSecret(SName);
      except
        on E: Exception do
        begin
          WriteLn('ERR: LoadSecret raised: ' + E.Message);
          Halt(2);
        end;
      end;
      if Trim(SVal) = '' then
      begin
        WriteLn('EMPTY: secret ' + SName + ' not found or blank');
        Halt(3);
      end;
      WriteLn('OK: ' + SName + ' length=' + IntToStr(Length(SVal)));
      var Lines := SVal.Split([';', #10, #13]);
      for var I := 0 to High(Lines) do
      begin
        var L := Trim(Lines[I]);
        if L = '' then Continue;
        var Head := Copy(L, 1, 4);
        var Tail := Copy(L, Length(L) - 3, 4);
        WriteLn('  line' + IntToStr(I) + ': len=' + IntToStr(Length(L)) + ' head=' + Head + '...tail=' + Tail);
      end;
      Halt(0);
    end;

    // DBA-3 verification: DeepFrames.exe --test-llm [provider]
    // Sends one real chat completion through the facade path
    // (LLM.ChatWithHistoryByProvider inside CallRealAPI) to prove the LLM
    // chain is wired end-to-end — not the stub. Prints Success + ErrorCode
    // + masked head of ResponseJson so we can tell a real reply from a stub
    // ('status: stub') without dumping full content. Optional 2nd arg picks
    // the provider (agnes|gemini|stepfun); default = configured LLM provider.
    if (ParamCount >= 1) and SameText(ParamStr(1), '--test-llm') then
    begin
      var Reg := TProviderRegistry.Instance;
      if ParamCount >= 2 then
      begin
        try
          Reg.SwitchTo(ParamStr(2));
        except
          on E: Exception do
          begin
            WriteLn('ERR: SwitchTo(' + ParamStr(2) + ') failed: ' + E.Message);
            Halt(4);
          end;
        end;
      end;
      var Prov := Reg.LLMProvider;
      WriteLn('[test-llm] provider=' + Prov.GetProviderName);
      var Req: TChatCompletionRequest;
      Req.SystemPrompt := 'You are a test echo. Reply with one short sentence.';
      Req.UserMessage := 'Say hello in Chinese, then stop.';
      Req.OutputSchemaJson := '{}';
      Req.Model := '';
      Req.Temperature := 0.7;
      Req.MaxTokens := 256;
      Req.AgentRole := AGENT_ROLE_WORKER;
      var Res: TChatCompletionResult;
      var Met: TProviderRunMetrics;
      var Ok := Prov.ChatComplete(Req, Res, Met);
      WriteLn('[test-llm] Success=' + BoolToStr(Ok, True) + ' ErrorCode=' + Met.ErrorCode
        + ' LatencyMs=' + IntToStr(Met.LatencyMs)
        + ' Tokens=' + IntToStr(Met.TokenUsage.TotalTokens));
      var Snip := Res.ResponseJson;
      if Length(Snip) > 200 then
        Snip := Copy(Snip, 1, 200) + '...(' + IntToStr(Length(Res.ResponseJson)) + ' bytes)';
      WriteLn('[test-llm] ResponseJson head: ' + Snip);
      if (not Ok) or (Pos('stub', LowerCase(Res.ResponseJson)) > 0) then
      begin
        WriteLn('[test-llm] FAIL: call did not succeed or returned stub output');
        Halt(5);
      end;
      WriteLn('[test-llm] OK: real LLM reply received');
      Halt(0);
    end;

    // --run-pipeline: headless end-to-end run of the full DeepFrames chain
    // (Preprocess→Document→Agent→Audio→Video→Package) against the real
    // production provider chain (Agnes/Baidu primary + Gemini failover). No GUI.
    // Auto-seeds a project + source doc if DB is empty so a fresh checkout runs.
    if (ParamCount >= 1) and SameText(ParamStr(1), '--run-pipeline') then
    begin
      var PL: TextFile;
      AssignFile(PL, 'pipeline_run.log');
      try
        Rewrite(PL);
        // WPL: write a line to both the log file (flushed) and stdout.
        var WPL: string; // placeholder; we just inline WriteLn(PL,...)+Flush below
        var Step: string;

        Step := '[start] --run-pipeline entered';
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);

        var SeedPath := 'seed_wsh.md';
        if ParamCount >= 2 then
          SeedPath := ParamStr(2);

        // -----------------------------------------------------------------
        // D1 (tasks.md, 2026-07-13): full-capability CLI overrides.
        // Parse --key value pairs from ParamStr(3..N) BEFORE the pipeline runs
        // so every phase picks them up. Each override writes the config DB
        // (provider/model/voice/lang/strategy/ffmpeg/output) — providers read
        // config at call time, so no code change is needed downstream for most
        // keys. --provider switches the registry preset (whole-group) via the
        // existing SwitchTo, done after the registry is first accessed below.
        // Unknown flags are skipped (tolerant), keeping backward compat for
        // bare `--run-pipeline <seed>`.
        // -----------------------------------------------------------------
        var CliProvider := '';
        var CliLLMModel := '';
        var ForceRerun := False;
        // Start scanning at param 2 (param 1 is '--run-pipeline'). Supports
        // both `--run-pipeline <seed> --flag...` and bare
        // `--run-pipeline --flag...` — a leading non-flag token is treated as
        // the seed, flag tokens are parsed by the loop below. Previously this
        // was hardcoded to I:=3, which silently dropped --force-rerun in the
        // bare form (no seed) — the purge never ran and stale done jobs
        // survived, so VideoChain's idempotency check returned the old video
        // (stale .srt, unchanged mp4) instead of regenerating.
        var I := 2;
        // If param 2 is not a flag, consume it as the optional seed.
        if (I <= ParamCount) and not ParamStr(I).StartsWith('--') then
          Inc(I);
        while I <= ParamCount do
        begin
          if SameText(ParamStr(I), '--provider') and (I + 1 <= ParamCount) then
          begin CliProvider := ParamStr(I + 1); Inc(I, 2); end
          else if SameText(ParamStr(I), '--llm-model') and (I + 1 <= ParamCount) then
          begin CliLLMModel := ParamStr(I + 1); Inc(I, 2); end
          else if SameText(ParamStr(I), '--voice') and (I + 1 <= ParamCount) then
          begin SetConfig(CONFIG_TTS_VOICE, ParamStr(I + 1), 'TTS'); Inc(I, 2); end
          else if SameText(ParamStr(I), '--subtitle-lang') and (I + 1 <= ParamCount) then
          begin SetConfig(CONFIG_SUBTITLE_LANG, ParamStr(I + 1), 'Subtitle'); Inc(I, 2); end
          else if SameText(ParamStr(I), '--duration-strategy') and (I + 1 <= ParamCount) then
          begin SetConfig(CONFIG_DURATION_STRATEGY, ParamStr(I + 1), 'Video'); Inc(I, 2); end
          else if SameText(ParamStr(I), '--ffmpeg-path') and (I + 1 <= ParamCount) then
          begin
            SetConfig(CONFIG_FFMPEG_DIR, ExtractFileDir(ParamStr(I + 1)), 'Video');
            Inc(I, 2);
          end
          else if SameText(ParamStr(I), '--ffprobe-path') and (I + 1 <= ParamCount) then
          begin
            // ffprobe is expected alongside ffmpeg; reuse FfmpegDir.
            SetConfig(CONFIG_FFMPEG_DIR, ExtractFileDir(ParamStr(I + 1)), 'Video');
            Inc(I, 2);
          end
          else if SameText(ParamStr(I), '--output-dir') and (I + 1 <= ParamCount) then
          begin SetConfig(CONFIG_OUTPUT_DIR, ParamStr(I + 1), 'Output'); Inc(I, 2); end
          else if SameText(ParamStr(I), '--keep-intermediates') then
          begin SetConfig(CONFIG_KEEP_INTERMEDIATES, '1', 'Debug'); Inc(I, 1); end
          else if SameText(ParamStr(I), '--force-rerun') then
          begin ForceRerun := True; Inc(I, 1); end
          else
            Inc(I); // unknown flag — skip, tolerant
        end;
        // --llm-model writes to whichever provider model key is relevant.
        // Agnes is the video-capable primary; if a different provider was
        // selected via --provider, its own model key takes precedence anyway.
        if CliLLMModel <> '' then
          SetConfig(CONFIG_AGNES_LLM_MODEL, CliLLMModel, 'Agnes');

        // Seed a project + content unit + source doc if none exist (cold start).
        var Projects := TDeepFramesAppService.ListProjects;
        var ProjId: string;
        if Length(Projects) = 0 then
        begin
          Step := '[seed] creating project + importing source doc: ' + SeedPath;
          WriteLn(PL, Step); Flush(PL); WriteLn(Step);
          var P := TDeepFramesAppService.CreateProject('WSH end-to-end CLI run');
          TDeepFramesAppService.ImportMarkdown(SeedPath);
          ProjId := P.ProjectId;
        end
        else
          ProjId := Projects[0].ProjectId;
        Step := '[seed] project=' + ProjId;
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);

        // Provider chain that will be used (default = production failover).
        var Reg := TProviderRegistry.Instance;
        // D1: --provider overrides the whole-group preset. SwitchTo is a no-op
        // when the requested name equals the active one, so re-selecting the
        // default stepfun-mix is harmless. Unknown names raise here, which is
        // the correct hard-fail (better than a silent wrong provider).
        if CliProvider <> '' then
        begin
          Reg.SwitchTo(CliProvider);
          Step := '[provider] switched to ' + CliProvider;
          WriteLn(PL, Step); Flush(PL); WriteLn(Step);
        end;
        Step := '[provider] LLM=' + Reg.LLMProvider.GetProviderName
          + ' TTS=' + Reg.TTSProvider.GetProviderName
          + ' ASR=' + Reg.ASRProvider.GetProviderName
          + ' Image=' + Reg.ImageProvider.GetProviderName
          + ' Video=' + Reg.VideoProvider.GetProviderName;
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);

        Step := '[pipeline] RunFullPipelineAsync start...';
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);
        // DBA-4: enqueue pipeline on a DeepBase TWorkerQueue worker thread so the
        // CLI prompt is not blocked and per-phase progress can be printed live.
        // Poll GetPipelineStatus until terminal; the final TDeepFramesJob is
        // recovered from the worker's result map.
        var PipelineJobId := TDeepFramesAppService.RunFullPipelineAsync(ForceRerun,
          procedure(const APhase: string; const APhaseJob: TDeepFramesJob)
          begin
            // Fires on the worker thread. stdout WriteLn is thread-safe enough
            // for a CLI; we avoid the shared PL TextFile to prevent interleaving.
            WriteLn(Format('[poll] phase=%s status=%s', [APhase, APhaseJob.Status]));
          end, nil);
        Step := Format('[pipeline] enqueued PipelineJobId=%s (polling...)', [PipelineJobId]);
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);

        var Poll: TPipelineStatus;
        repeat
          Poll := TDeepFramesAppService.GetPipelineStatus(PipelineJobId);
          if not Poll.IsTerminal then
            Sleep(500);
        until Poll.IsTerminal;
        var Job := Poll.FinalJob;
        Step := Format('[pipeline] done JobType=%s JobId=%s Status=%s',
          [Job.JobType, Job.JobId, Job.Status]);
        WriteLn(PL, Step); Flush(PL); WriteLn(Step);

        // Print final video absolute path for user to open and review
        if SameText(Job.Status, 'COMPLETED') or SameText(Job.Status, 'done') then
        begin
          // Find the most recent video file in output/video directory
          var RootPath := DeepBase.Manager.DeepBase.RootPath;
          var VideoDir := TPath.Combine(RootPath, 'output\video');
          if TDirectory.Exists(VideoDir) then
          begin
            var VideoFiles := TDirectory.GetFiles(VideoDir, 'bilibili_1080p.mp4', TSearchOption.soAllDirectories);
            if Length(VideoFiles) > 0 then
            begin
              // Find the most recently modified video file
              var LatestVideo := VideoFiles[0];
              var LatestTime := TFile.GetLastWriteTime(LatestVideo);
              for I := 1 to High(VideoFiles) do
              begin
                var CurrTime := TFile.GetLastWriteTime(VideoFiles[I]);
                if CurrTime > LatestTime then
                begin
                  LatestTime := CurrTime;
                  LatestVideo := VideoFiles[i];
                end;
              end;
              Step := '[pipeline] Final video: ' + LatestVideo;
              WriteLn(PL, Step); Flush(PL); WriteLn(Step);

              // Extra prominent output for user
              WriteLn;
              WriteLn('========================================');
              WriteLn('视频生成成功！绝对路径：');
              WriteLn(LatestVideo);
              WriteLn('========================================');
              WriteLn;
            end;
          end;
        end;

        if SameText(Job.Status, STATUS_DONE) then
        begin
          CloseFile(PL);
          Halt(0);
        end
        else
        begin
          Step := '[pipeline] NON-COMPLETED status — see DeepFrames log table + steps';
          WriteLn(PL, Step); Flush(PL); WriteLn(Step);
          CloseFile(PL);
          Halt(2);
        end;
      except
        on E: Exception do
        begin
          try
            var DF: TextFile; AssignFile(DF, 'df_fatal_diag.txt'); Rewrite(DF);
            WriteLn(DF, 'CLS=' + E.ClassName);
            WriteLn(DF, 'MSG=' + E.Message);
            WriteLn(DF, 'UNIT=' + E.UnitName);
            try WriteLn(DF, 'STACK=' + E.StackTrace); except end;
            CloseFile(DF);
          except end;
          try
            WriteLn(PL, '[pipeline] FATAL: ' + E.Message); Flush(PL);
            CloseFile(PL);
          except end;
          WriteLn('[pipeline] FATAL: ' + E.Message);
          Halt(3);
        end;
      end;
    end;

    Application.CreateForm(TMainForm, MainForm);
    DeepBase.Manager.DeepBase.FireReadyCallbacks;

    // AutoFix: emit health-signal at app startup so the runner detects readiness
    // even when the form is hidden (e.g., autofix -WindowStyle Hidden).
    AutoFix.NotifyShellShown;

    Application.Run;
  finally
    TDeepFramesBootstrap.Shutdown;
    DeepBase.Manager.DeepBase.Finalize;
  end;
end.