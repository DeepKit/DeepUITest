unit DeepFrames.App.Bootstrap;

interface

type
  TDeepFramesBootstrap = class
  public
    class procedure RegisterServices; static;
    class procedure Shutdown; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  DeepBase.Config,
  DeepBase.Manager,
  DeepBase.DB.Factory,
  DeepBase.DB.JobQueue,
  DeepFrames.Shared.Consts,
  DeepFrames.Persistence.Connection;

class procedure TDeepFramesBootstrap.RegisterServices;
var
  RootPath: string;
  ConfigDbPath: string;
begin
  RootPath := DeepBase.Manager.DeepBase.RootPath;
  ConfigDbPath := TPath.Combine(RootPath, 'DeepFramesConfig.db');
  TDBConnectionFactory.Configure(ConfigDbPath, RootPath);

  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_OUTPUT_DIR, 'output')));
  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_WORKER_DIR, 'workers')));
  TDirectory.CreateDirectory(TPath.Combine(RootPath, GetConfig(CONFIG_LOG_DIR, 'logs')));

  if Trim(GetConfig(CONFIG_ROOT_PATH, '')) = '' then
    SetConfig(CONFIG_ROOT_PATH, RootPath, 'Paths');
  if Trim(GetConfig(CONFIG_OUTPUT_DIR, '')) = '' then
    SetConfig(CONFIG_OUTPUT_DIR, 'output', 'Paths');
  if Trim(GetConfig(CONFIG_WORKER_DIR, '')) = '' then
    SetConfig(CONFIG_WORKER_DIR, 'workers', 'Paths');
  if Trim(GetConfig(CONFIG_LOG_DIR, '')) = '' then
    SetConfig(CONFIG_LOG_DIR, 'logs', 'Paths');

  TDeepFramesDB2Connection.EnsureDefaultSettings;
  TJobQueue.SetConnectionProvider(
    function: TFDConnection
    begin
      Result := TDeepFramesDB2Connection.CreateConnection(True);
    end);
end;

class procedure TDeepFramesBootstrap.Shutdown;
begin
  TJobQueue.Clear;
  TDeepFramesDB2Connection.ReleasePool;
end;

end.
