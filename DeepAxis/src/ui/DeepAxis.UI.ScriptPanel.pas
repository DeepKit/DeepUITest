unit DeepAxis.UI.ScriptPanel;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes,
  DeepAxis.Pipeline.ScriptEngine;

type
  TScriptPasteEvent = procedure(const AScript: string) of object;
  TScriptSkipEvent = procedure of object;

  TScriptPanel = class(TPanel)
  private
    FTitleLabel: TLabel;
    FScriptMemo: TMemo;
    FVariantLabel: TLabel;
    FVariantIndex: Integer;
    FVariants: TArray<string>;
    FScriptEngine: TScriptEngine;
    FCurrentContact: TContact;
    FCurrentHintType: TRadarHintType;
    FOnPaste: TScriptPasteEvent;
    FOnSkip: TScriptSkipEvent;
    procedure BuildUI;
    procedure UpdateScriptDisplay;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure GenerateFor(const AContact: TContact; AHintType: TRadarHintType);
    function GetCurrentScript: string;
    procedure NextVariant;

    procedure PrevVariant;

    property OnPaste: TScriptPasteEvent read FOnPaste write FOnPaste;

    property OnSkip: TScriptSkipEvent read FOnSkip write FOnSkip;
  end;

implementation

{ TScriptPanel }

constructor TScriptPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FScriptEngine := TScriptEngine.Create;
  FVariantIndex := 0;
  BuildUI;
end;

destructor TScriptPanel.Destroy;
begin
  FScriptEngine.Free;
  inherited;
end;

procedure TScriptPanel.BuildUI;
begin
  Self.BevelOuter := bvNone;
  Self.Caption := '';

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.Caption := '话术草稿';
  FTitleLabel.Height := 20;

  FVariantLabel := TLabel.Create(Self);
  FVariantLabel.Parent := Self;
  FVariantLabel.Align := alTop;
  FVariantLabel.Caption := '变体 1/1';
  FVariantLabel.Height := 16;

  FScriptMemo := TMemo.Create(Self);
  FScriptMemo.Parent := Self;
  FScriptMemo.Align := alClient;
  FScriptMemo.ReadOnly := False;
  FScriptMemo.ScrollBars := ssVertical;
  FScriptMemo.WordWrap := True;
end;

procedure TScriptPanel.GenerateFor(const AContact: TContact;
  AHintType: TRadarHintType);
begin
  FCurrentContact := AContact;
  FCurrentHintType := AHintType;
  FVariantIndex := 0;

  FVariants := FScriptEngine.GenerateVariants(AContact, AHintType, 3);
  if Length(FVariants) = 0 then
  begin
    SetLength(FVariants, 1);
    FVariants[0] := FScriptEngine.GenerateScript(AContact, AHintType);
  end;

  UpdateScriptDisplay;
end;

procedure TScriptPanel.UpdateScriptDisplay;
begin
  if (FVariantIndex >= 0) and (FVariantIndex < Length(FVariants)) then
  begin
    FScriptMemo.Text := FVariants[FVariantIndex];
    FVariantLabel.Caption := Format('变体 %d/%d  [1/2/3 切换]', [FVariantIndex + 1, Length(FVariants)]);
  end
  else
  begin
    FScriptMemo.Text := '';
    FVariantLabel.Caption := '无话术';
  end;
end;

function TScriptPanel.GetCurrentScript: string;
begin
  Result := FScriptMemo.Text;
end;

procedure TScriptPanel.NextVariant;
begin
  if Length(FVariants) = 0 then Exit;
  FVariantIndex := (FVariantIndex + 1) mod Length(FVariants);
  UpdateScriptDisplay;
end;

procedure TScriptPanel.PrevVariant;
begin
  if Length(FVariants) = 0 then Exit;
  FVariantIndex := (FVariantIndex - 1 + Length(FVariants)) mod Length(FVariants);
  UpdateScriptDisplay;
end;

end.