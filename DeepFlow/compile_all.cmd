@echo off
cd /d d:\_Progs\02Business\DeepFlow
set DCC="D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\Dcc64.exe"
if not exist BuildOutput\dcu64 mkdir BuildOutput\dcu64
echo === Compiling all DeepFlow units ===
for %%f in (
  Source\DeepFlow.Constants.pas
  Source\Core\DeepFlow.DI.pas
  Source\Tenant\DeepFlow.Tenant.pas
  Source\Workflow\DeepFlow.Workflow.Definition.pas
  Source\Workflow\DeepFlow.Workflow.Context.pas
  Source\Workflow\DeepFlow.Workflow.Executor.pas
  Source\Workflow\DeepFlow.Workflow.State.pas
  Source\Workflow\DeepFlow.Workflow.Errors.pas
  Source\Workflow\DeepFlow.Workflow.Version.pas
  Source\Workflow\DeepFlow.Workflow.Version.API.pas
  Source\Workflow\DeepFlow.Workflow.ImportExport.pas
  Source\Session\DeepFlow.Session.Types.pas
  Source\Session\DeepFlow.Session.Manager.pas
  Source\Roles\DeepFlow.Roles.Commander.pas
  Source\AI\DeepFlow.AI.Adapter.pas
  Source\AI\DeepFlow.AI.Recommendation.pas
  Source\AI\DeepFlow.AI.NLWorkflowGen.pas
  Source\AI\DeepFlow.AI.AnomalyDetection.pas
  Source\AI\DeepFlow.AI.SmartRetry.pas
  Source\Skill\DeepFlow.Skill.Types.pas
  Source\Skill\DeepFlow.Skill.Client.pas
  Source\Skill\DeepFlow.Skill.Executor.pas
  Source\Security\DeepFlow.Security.Sanitizer.pas
  Source\Security\DeepFlow.Security.Filter.pas
  Source\Security\DeepFlow.Security.RateLimit.pas
  Source\Validation\DeepFlow.Validation.Schema.pas
  Source\Audit\DeepFlow.Audit.Types.pas
  Source\Audit\DeepFlow.Audit.Store.pas
  Source\Audit\DeepFlow.Audit.Manager.pas
  Source\Metrics\DeepFlow.Metrics.Types.pas
  Source\Metrics\DeepFlow.Metrics.Collector.pas
  Source\Diagnostics\DeepFlow.Diagnostics.pas
  Source\Diagnostics\DeepFlow.Diagnostics.Integration.pas
  Source\Diagnostics\DeepFlow.Diagnostics.ErrorCollector.pas
  Source\Diagnostics\DeepFlow.Diagnostics.TraceExporter.pas
  Source\Diagnostics\DeepFlow.Diagnostics.Debugger.pas
  Source\EventSourcing\DeepFlow.EventSourcing.Types.pas
  Source\EventSourcing\DeepFlow.EventSourcing.Store.pas
  Source\EventSourcing\DeepFlow.EventSourcing.Instance.pas
  Source\EventSourcing\DeepFlow.EventSourcing.Replay.pas
  Source\MCP\DeepFlow.MCP.Types.pas
  Source\MCP\DeepFlow.MCP.Server.pas
  Source\MCP\DeepFlow.MCP.Client.pas
  Source\Performance\DeepFlow.Performance.Pool.pas
  Source\Performance\DeepFlow.Performance.Cache.pas
  Source\Performance\DeepFlow.Performance.JSON.pas
  Source\Performance\DeepFlow.Performance.Concurrent.pas
  Source\Plugin\DeepFlow.Plugin.Intf.pas
  Source\Plugin\DeepFlow.Plugin.Loader.pas
  Source\Plugin\DeepFlow.Plugin.Registry.pas
  Source\Plugin\DeepFlow.Plugin.Examples.pas
  Source\Queue\DeepFlow.Queue.Types.pas
  Source\Queue\DeepFlow.Queue.RabbitMQ.pas
  Source\Queue\DeepFlow.Queue.Kafka.pas
  Source\Storage\DeepFlow.Storage.Types.pas
  Source\Storage\DeepFlow.Storage.PostgreSQL.pas
  Source\Storage\DeepFlow.Storage.SQLite.pas
  Source\Realtime\DeepFlow.Realtime.WebSocket.pas
  Source\Cloud\DeepFlow.Cloud.Telemetry.Types.pas
  Source\Cloud\DeepFlow.Cloud.Telemetry.SDK.pas
  Source\Analytics\DeepFlow.Analytics.pas
  Source\Tests\DeepFlow.Tests.Executor.pas
  Source\Tests\DeepFlow.Tests.Benchmark.pas
  Source\Tests\DeepFlow.Tests.E2E.pas
) do (
  echo.
  echo === %%f ===
  %DCC% @build.rsp "%%f" >> compile_all_out.txt 2>&1
  if errorlevel 1 (
    echo FAILED: %%f
  ) else (
    echo OK: %%f
  )
)
echo === Done ===
