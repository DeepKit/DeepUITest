unit DeepAxis.UI.SendQueuePanel;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  DeepAxis.Pipeline.SendQueue;

type
  /// <summary>
  ///   发送队列面板 — 展示已完成/待处理/失败的任务。
  /// </summary>
  TSendQueuePanel = class(TPanel)
  private
    FTitleLabel: TLabel;
    FSummaryLabel: TLabel;
    FQueueMemo: TMemo;
    FSendQueue: TSendQueue;
    procedure BuildUI;
    procedure RefreshDisplay;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// <summary>设置发送队列引用</summary>
    procedure SetQueue(const AQueue: TSendQueue);

    /// <summary>刷新显示</summary>
    procedure Refresh;
  end;

implementation

{ TSendQueuePanel }

constructor TSendQueuePanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSendQueue := nil;
  BuildUI;
end;

destructor TSendQueuePanel.Destroy;
begin
  inherited;
end;

procedure TSendQueuePanel.BuildUI;
begin
  Self.BevelOuter := bvNone;
  Self.Caption := '';

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.Caption := '发送队列';
  FTitleLabel.Height := 20;

  FSummaryLabel := TLabel.Create(Self);
  FSummaryLabel.Parent := Self;
  FSummaryLabel.Align := alTop;
  FSummaryLabel.Caption := '待处理: 0  已完成: 0  失败: 0';
  FSummaryLabel.Height := 16;

  FQueueMemo := TMemo.Create(Self);
  FQueueMemo.Parent := Self;
  FQueueMemo.Align := alClient;
  FQueueMemo.ReadOnly := True;
  FQueueMemo.ScrollBars := ssVertical;
end;

procedure TSendQueuePanel.SetQueue(const AQueue: TSendQueue);
begin
  FSendQueue := AQueue;
  Refresh;
end;

procedure TSendQueuePanel.Refresh;
begin
  RefreshDisplay;
end;

procedure TSendQueuePanel.RefreshDisplay;
var
  LItems: TArray<TSendQueueItem>;
  LItem: TSendQueueItem;
  LStatusEmoji: string;
begin
  if FSendQueue = nil then
  begin
    FSummaryLabel.Caption := '队列未初始化';
    FQueueMemo.Clear;
    Exit;
  end;

  FSummaryLabel.Caption := FSendQueue.GetSummary;

  FQueueMemo.Clear;
  LItems := FSendQueue.GetAll;

  // 倒序显示（最新的在上面）
  for var I := Length(LItems) - 1 downto 0 do
  begin
    LItem := LItems[I];
    case LItem.Status of
      ssPending:  LStatusEmoji := '⏳';
      ssPasting:  LStatusEmoji := '📤';
      ssSent:     LStatusEmoji := '✅';
      ssFailed:   LStatusEmoji := '❌';
      ssSkipped:  LStatusEmoji := '⏭️';
    else
      LStatusEmoji := '❓';
    end;

    FQueueMemo.Lines.Add(Format('%s [%s] %s — %s',
      [LStatusEmoji, LItem.ContactName, LItem.Script, LItem.ErrorMessage]));
  end;
end;

end.