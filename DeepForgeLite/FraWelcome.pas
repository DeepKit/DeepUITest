unit FraWelcome;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.Layouts,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo;

type
  TFrameWelcome = class(TFrame)
    LayoutRoot: TLayout;
    LayoutContent: TLayout;
    
    LblTitle: TLabel;
    LblSubtitle: TLabel;
    LblDivider: TLabel;
    
    LblWhatIsODD: TLabel;
    LblODDDesc: TLabel;
    
    LayoutTraditional: TLayout;
    LblTraditionalTitle: TLabel;
    LblTraditionalDesc: TLabel;
    LayoutTraditionalItems: TLayout;
    
    LayoutODD: TLayout;
    LblODDTitle: TLabel;
    LblODDDesc: TLabel;
    LayoutODDItems: TLayout;
    
    LblDivider2: TLabel;
    
    BtnStartVerify: TButton;
    
    LblSupported: TLabel;
    
    procedure BtnStartVerifyClick(Sender: TObject);
  private
    FOnStartVerify: TNotifyEvent;
  public
    property OnStartVerify: TNotifyEvent read FOnStartVerify write FOnStartVerify;
  end;

implementation

{$R *.fmx}

procedure TFrameWelcome.BtnStartVerifyClick(Sender: TObject);
begin
  if Assigned(FOnStartVerify) then
    FOnStartVerify(Self);
end;

end.
