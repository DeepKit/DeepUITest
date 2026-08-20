unit DeepAxis.UI.ScriptPanel;

interface

uses
  System.SysUtils, System.Classes,
  Winapi.Windows,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.SendModes,
  DeepAxis.Pipeline.ScriptEngine;

type
  TScriptPasteEvent = procedure(const AScript: string) of object;
  /// <summary>带发送模式的粘贴事件 (docs/03 §4.4)。Mode 由模式选择器决定。</summary>
  TScriptPasteWithModeEvent = procedure(const AScript: string; AMode: TSendMode) of object;
  TScriptSkipEvent = procedure of object;

  TScriptPanel = class(TPanel)
  private
    FTitleLabel: TLabel;
    FScriptMemo: TMemo;
    FVariantLabel: TLabel;
    FModeCombo: TComboBox;
    FBtnRow: TPanel;  // 模式选择按钮行容器 (ComboBox 父)
    FVariantIndex: Integer;
    FVariants: TArray<string>;
    FScriptEngine: TScriptEngine;
    FCurrentContact: TContact;
    FCurrentHintType: TRadarHintType; // Use TRadarHintType from Core.Base
    FOnPaste: TScriptPasteEvent;
    FOnPasteWithMode: TScriptPasteWithModeEvent;
    FOnSkip: TScriptSkipEvent;
    procedure BuildUI;
    procedure UpdateScriptDisplay;
    procedure DoPasteClick(Sender: TObject);
    procedure DoSkipClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure GenerateFor(const AContact: TContact; AHintType: TRadarHintType); // Use Core.Base enum
    function GetCurrentScript: string;
    /// <summary>当前选择的发送模式。</summary>
    function GetSelectedMode: TSendMode;
    procedure NextVariant;
    procedure PrevVariant;

    property OnPaste: TScriptPasteEvent read FOnPaste write FOnPaste;
    property OnPasteWithMode: TScriptPasteWithModeEvent read FOnPasteWithMode write FOnPasteWithMode;
    property OnSkip: TScriptSkipEvent read FOnSkip write FOnSkip;
    /// <summary>句柄就绪后调用: 初始化 ComboBox 默认选中 (BUG-041/050)。</summary>
    procedure EnsureModeInitialized;
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
var
  LPasteBtn: TButton;
  LSkipBtn: TButton;
  LBtnRow: TPanel;
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

  // 模式选择 + 操作按钮行 (docs/03 §4.4 三模式)
  LBtnRow := TPanel.Create(Self);
  LBtnRow.Parent := Self;
  LBtnRow.Align := alBottom;
  LBtnRow.Height := 32;
  LBtnRow.BevelOuter := bvNone;
  FBtnRow := LBtnRow;

  // BUG-041/050 fix: TComboBox 创建即需要句柄 (csDropDownList 风格),
  // FormCreate 阶段 MainForm 主窗句柄未就绪 → EInvalidOperation 'no parent window'。
  // ComboBox 整个延后到 EnsureModeInitialized (父句柄链就绪后) 再创建。
  FModeCombo := nil;

  LSkipBtn := TButton.Create(Self);
  LSkipBtn.Parent := LBtnRow;
  LSkipBtn.Align := alRight;
  LSkipBtn.Caption := '跳过';
  LSkipBtn.Width := 60;
  LSkipBtn.OnClick := DoSkipClick;

  LPasteBtn := TButton.Create(Self);
  LPasteBtn.Parent := LBtnRow;
  LPasteBtn.Align := alRight;
  LPasteBtn.Caption := '粘贴/发送';
  LPasteBtn.Width := 90;
  LPasteBtn.OnClick := DoPasteClick;

  FScriptMemo := TMemo.Create(Self);
  FScriptMemo.Parent := Self;
  FScriptMemo.Align := alClient;
  FScriptMemo.ReadOnly := False;
  FScriptMemo.ScrollBars := ssVertical;
  FScriptMemo.WordWrap := True;
end;

procedure TScriptPanel.EnsureModeInitialized;
begin
  // BUG-041/050 fix: ComboBox 创建 + Items.Add + ItemIndex 都触发句柄创建,
  // 只能在父句柄链就绪后调用 (MainForm.FormShow)。
  if (FModeCombo = nil) and (FBtnRow <> nil) then
  begin
    FModeCombo := TComboBox.Create(FBtnRow);
    FModeCombo.Parent := FBtnRow;
    FModeCombo.Align := alLeft;
    FModeCombo.Style := csDropDownList;
    FModeCombo.Width := 120;
    FModeCombo.Items.Add('辅助发送');
    FModeCombo.Items.Add('手动发送');
    FModeCombo.Items.Add('最终发送');
    FModeCombo.ItemIndex := 0;
  end;
end;

procedure TScriptPanel.DoPasteClick(Sender: TObject);
var
  LScript: string;
  LMode: TSendMode;
begin
  LScript := GetCurrentScript;
  LMode := GetSelectedMode;
  // 优先用带模式的事件; 若调用方只绑了旧 OnPaste 也兼容
  if Assigned(FOnPasteWithMode) then
    FOnPasteWithMode(LScript, LMode)
  else if Assigned(FOnPaste) then
    FOnPaste(LScript);
end;

procedure TScriptPanel.DoSkipClick(Sender: TObject);
begin
  if Assigned(FOnSkip) then FOnSkip;
end;

function TScriptPanel.GetSelectedMode: TSendMode;
begin
  case FModeCombo.ItemIndex of
    1:  Result := smManual;
    2:  Result := smFinal;
    else Result := smAssist;
  end;
end;

procedure TScriptPanel.GenerateFor(const AContact: TContact;
  AHintType: TRadarHintType); // Use TRadarHintType from Core.Base
var
  LContext: TScriptGenerationContext;
  LGoal: string;
begin
  FCurrentContact := AContact;
  FCurrentHintType := AHintType;
  FVariantIndex := 0;

  // Build generation context from contact
  LContext.ContactId := AContact.ContactId;
  LContext.ContactName := AContact.DisplayNameRedacted;
  LContext.Remark := AContact.Remark;  // BUG-051 #88: 个性化提取
  LContext.Tier := tGreen;
  LContext.DaysSinceLastContact := 0;
  LContext.InboundCount := 0;
  LContext.OutboundCount := 0;

  // Map hint type to goal keyword
  case AHintType of
    rhtCooling,      rhtLongSilence   : LGoal := 'reactivation';
    rhtReactivated,  rhtOutboundHeavy : LGoal := 'repurchase';
    rhtDataInsufficient               : LGoal := 'followup';
  else
    LGoal := 'followup';
  end;

  // Generate 3 variants by calling Generate multiple times
  SetLength(FVariants, 3);
  FVariants[0] := FScriptEngine.Generate(LContext, LGoal);
  FVariants[1] := FScriptEngine.Generate(LContext, LGoal);
  FVariants[2] := FScriptEngine.Generate(LContext, LGoal);

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