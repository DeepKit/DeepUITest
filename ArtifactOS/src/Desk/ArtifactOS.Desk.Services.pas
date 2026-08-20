{ ============================================================================
  ArtifactOS.Desk.Services

  Service interfaces and implementations for ArtifactOS Desk.
  Phase 1: database connectivity check and status query helpers.
  ============================================================================ }

unit ArtifactOS.Desk.Services;

interface

uses
  System.SysUtils,
  DeepBase.VCL.DeepShell;

type
  IArtifactOSService = interface(IInterface)
    ['{F8A3D1E2-4B5C-6D7E-8F9A-0B1C2D3E4F50}']
    function GetDatabaseStatus: string;
    function GetActiveCaseCount: Integer;
    function GetPendingPackagesCount: Integer;
  end;

  TArtifactOSServiceImpl = class(TInterfacedObject, IArtifactOSService)
  public
    function GetDatabaseStatus: string;
    function GetActiveCaseCount: Integer;
    function GetPendingPackagesCount: Integer;
  end;

implementation

uses
  ArtifactOS.Core.DB.Connection;

{ TArtifactOSServiceImpl }

function TArtifactOSServiceImpl.GetDatabaseStatus: string;
begin
  try
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''artifactos''');
      if V = '1' then
        Result := 'connected'
      else
        Result := 'schema_missing';
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    Result := 'error';
  end;
end;

function TArtifactOSServiceImpl.GetActiveCaseCount: Integer;
begin
  Result := 0;
  try
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.case_record WHERE status=''active''');
      Result := StrToIntDef(V, 0);
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    Result := 0;
  end;
end;

function TArtifactOSServiceImpl.GetPendingPackagesCount: Integer;
begin
  Result := 0;
  try
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.publication_package WHERE status IN (''draft'', ''preflight'', ''queued'')');
      Result := StrToIntDef(V, 0);
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    Result := 0;
  end;
end;

end.
