unit DeepFrames.Persistence.Migrations;

interface

uses
  DeepBase.DB.Migrations;

type
  TDeepFramesMigrations = class
  public
    class function RunMigrations: TMigrationResult; static;
    class function RunDB3Migrations: TMigrationResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  FireDAC.Comp.Client,
  DeepBase.DB.Pool,
  DeepFrames.Persistence.Connection,
  DeepFrames.Persistence.DB3Connection;

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

class function TDeepFramesMigrations.RunDB3Migrations: TMigrationResult;
var
  Conn: TFDConnection;
  MigrationsDir: string;
begin
  MigrationsDir := TPath.Combine(TDirectory.GetCurrentDirectory, 'db/postgres');
  if not TDirectory.Exists(MigrationsDir) then
    MigrationsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'db/postgres');

  if not TDeepFramesDB3Connection.IsConfigured then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Success := False;
    Result.LastError := 'DB3 not configured — skip';
    Exit;
  end;

  Conn := TDeepFramesDB3Connection.CreateConnection(True);
  try
    Result := TMigrationEngine.Run(Conn, dbPostgreSQL, MigrationsDir);
  finally
    Conn.Free;
  end;
end;

end.
