object frmTransparency: TfrmTransparency
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Custom Transparency'
  ClientHeight = 180
  ClientWidth = 380
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poMainFormCenter
  OnKeyDown = FormKeyDown
  object lblPreset: TLabel
    Left = 16
    Top = 16
    Width = 350
    Height = 17
    Caption = 'Set window transparency (10 = almost invisible, 255 = opaque)'
  end
  object lblValue: TLabel
    Left = 16
    Top = 44
    Width = 100
    Height = 17
    Caption = '100%'
  end
  object tbAlpha: TTrackBar
    Left = 16
    Top = 68
    Width = 345
    Height = 35
    Min = 10
    Max = 255
    Frequency = 25
    Position = 255
    TabOrder = 0
    OnChange = tbAlphaChange
  end
  object edtAlpha: TEdit
    Left = 16
    Top = 112
    Width = 65
    Height = 25
    NumbersOnly = True
    TabOrder = 1
    Text = '255'
    OnChange = edtAlphaChange
    OnKeyPress = edtAlphaKeyPress
  end
  object btnOK: TButton
    Left = 215
    Top = 140
    Width = 75
    Height = 25
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 2
  end
  object btnCancel: TButton
    Left = 296
    Top = 140
    Width = 75
    Height = 25
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end