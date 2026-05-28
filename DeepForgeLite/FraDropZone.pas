unit FraDropZone;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Objects;

type
  TOnFileDropped = procedure(const FilePath: string) of object;
  
  TFrameDropZone = class(TFrame)
    Rectangle1: TRectangle;
    LblHint: TLabel;
    procedure Rectangle1DragOver(Sender: TObject; const Data: TDragObject;
      const Point: TPointF; var Operation: TDragOperation);
    procedure Rectangle1DragDrop(Sender: TObject; const Data: TDragObject;
      const Point: TPointF);
  private
    FOnFileDropped: TOnFileDropped;
  public
    property OnFileDropped: TOnFileDropped read FOnFileDropped write FOnFileDropped;
  end;

implementation

{$R *.fmx}

procedure TFrameDropZone.Rectangle1DragOver(Sender: TObject;
  const Data: TDragObject; const Point: TPointF; var Operation: TDragOperation);
begin
  if Length(Data.Files) = 1 then
    Operation := TDragOperation.Copy
  else
    Operation := TDragOperation.None;
end;

procedure TFrameDropZone.Rectangle1DragDrop(Sender: TObject;
  const Data: TDragObject; const Point: TPointF);
begin
  if (Length(Data.Files) = 1) and Assigned(FOnFileDropped) then
    FOnFileDropped(Data.Files[0]);
end;

end.
