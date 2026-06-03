unit DeepFrames.Persistence.Migrations;

interface

uses
  DeepBase.DB.Migrations;

type
  TDeepFramesMigrations = class
  public
    class function RunMigrations: TMigrationResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  DeepBase.DB.Pool,
  DeepFrames.Persistence.Connection;

class function TDeepFramesMigrations.RunMigrations: TMigrationResult;
var
  Conn: TFDConnection;
  MigrationsDir: string;
begin
  MigrationsDir := TPath.Combine(TDirectory.GetCurrentDirectory, 'db/postgres');
  if not TDirectory.Exists(MigrationsDir) then
    MigrationsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'db/postgres');

  Conn := TDeepFramesDB2Connection.CreateConnection(True);
  try
    Result := TMigrationEngine.Run(Conn, dbPostgreSQL, MigrationsDir);
  finally
    Conn.Free;
  end;
end;

end.
