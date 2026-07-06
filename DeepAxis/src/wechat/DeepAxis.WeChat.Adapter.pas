unit DeepAxis.WeChat.Adapter;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DeepAxis.Core.Base,
  DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Registry of known schema adapters. Maps adapter IDs to implementations.
  ///   Used by TWeChatReader to auto-select the right adapter.
  /// </summary>
  TSchemaAdapterRegistry = class
  private
    FAdapters: TDictionary<string, ISchemaAdapter>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterAdapter(const AAdapter: ISchemaAdapter);
    function TryResolve(const AAdapterId: string; out AAdapter: ISchemaAdapter): Boolean;
    function GetAdapters: TArray<ISchemaAdapter>;
    function TryDetect(const ASchemaFingerprint: string; out AAdapter: ISchemaAdapter): Boolean;
  end;

implementation

{ TSchemaAdapterRegistry }

constructor TSchemaAdapterRegistry.Create;
begin
  inherited Create;
  FAdapters := TDictionary<string, ISchemaAdapter>.Create;
end;

destructor TSchemaAdapterRegistry.Destroy;
begin
  FAdapters.Free;
  inherited;
end;

procedure TSchemaAdapterRegistry.RegisterAdapter(const AAdapter: ISchemaAdapter);
begin
  FAdapters.AddOrSetValue(AAdapter.GetAdapterId, AAdapter);
end;

function TSchemaAdapterRegistry.TryResolve(const AAdapterId: string;
  out AAdapter: ISchemaAdapter): Boolean;
begin
  Result := FAdapters.TryGetValue(AAdapterId, AAdapter);
end;

function TSchemaAdapterRegistry.GetAdapters: TArray<ISchemaAdapter>;
begin
  Result := FAdapters.Values.ToArray;
end;

function TSchemaAdapterRegistry.TryDetect(const ASchemaFingerprint: string;
  out AAdapter: ISchemaAdapter): Boolean;
var
  LAdapter: ISchemaAdapter;
begin
  for LAdapter in FAdapters.Values do
    if SameText(LAdapter.GetSchemaFingerprint, ASchemaFingerprint) then
    begin
      AAdapter := LAdapter;
      Exit(True);
    end;
  Result := False;
end;

end.