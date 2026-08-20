object frmAbout: TfrmAbout
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'About DeepRKey'
  ClientHeight = 220
  ClientWidth = 360
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  object pnlMain: TPanel
    Left = 0
    Top = 0
    Width = 360
    Height = 220
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 16
      Width = 328
      Height = 24
      Alignment = taCenter
      AutoSize = False
      Caption = 'DeepRKey'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -20
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblVersion: TLabel
      Left = 16
      Top = 44
      Width = 328
      Height = 16
      Alignment = taCenter
      AutoSize = False
      Caption = 'v0.1.0'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblDescription: TLabel
      Left = 16
      Top = 70
      Width = 328
      Height = 16
      Alignment = taCenter
      AutoSize = False
      Caption = 'Windows System Menu Enhancement Tool'
    end
    object lblTech: TLabel
      Left = 16
      Top = 92
      Width = 328
      Height = 16
      Alignment = taCenter
      AutoSize = False
      Caption = 'Delphi 13.1 + VCL + Win32 API'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblCopyright: TLabel
      Left = 16
      Top = 120
      Width = 328
      Height = 16
      Alignment = taCenter
      AutoSize = False
      Caption = 'Copyright (c) 2026'
    end
    object lblLicense: TLabel
      Left = 16
      Top = 142
      Width = 328
      Height = 16
      Alignment = taCenter
      AutoSize = False
      Caption = 'MIT License'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object btnOK: TButton
      Left = 140
      Top = 175
      Width = 80
      Height = 25
      Caption = 'OK'
      Default = True
      TabOrder = 0
      OnClick = btnOKClick
    end
  end
end