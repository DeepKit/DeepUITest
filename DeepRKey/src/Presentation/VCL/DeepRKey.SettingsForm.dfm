object frmSettings: TfrmSettings
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'DeepRKey Settings'
  ClientHeight = 400
  ClientWidth = 480
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnShow = FormShow
  OnKeyDown = FormKeyDown
  object pgcMain: TPageControl
    Left = 8
    Top = 8
    Width = 464
    Height = 350
    ActivePage = tsStatus
    TabOrder = 0
    object tsStatus: TTabSheet
      Caption = 'Status'
      object lblStatusHook: TLabel
        Left = 16
        Top = 16
        Width = 420
        Height = 17
        Caption = 'Hook: ...'
      end
      object lblStatusWindows: TLabel
        Left = 16
        Top = 40
        Width = 420
        Height = 17
        Caption = 'Tracked windows: ...'
      end
      object lblStatusThreads: TLabel
        Left = 16
        Top = 64
        Width = 420
        Height = 17
        Caption = 'Tracked threads: ...'
      end
      object lblStatusMMF: TLabel
        Left = 16
        Top = 88
        Width = 420
        Height = 17
        Caption = 'MMF drops: ...'
      end
      object lblStatusGUID: TLabel
        Left = 16
        Top = 112
        Width = 420
        Height = 17
        Caption = 'Session GUID: ...'
      end
    end
    object tsGeneral: TTabSheet
      Caption = 'General'
      object chkAutoStart: TCheckBox
        Left = 16
        Top = 16
        Width = 200
        Height = 17
        Caption = 'Start with Windows'
        TabOrder = 0
      end
      object chkStartMinimized: TCheckBox
        Left = 16
        Top = 40
        Width = 200
        Height = 17
        Caption = 'Start minimized to tray'
        TabOrder = 1
      end
    end
    object tsMenu: TTabSheet
      Caption = 'Menu Items'
      object chkShowTopMost: TCheckBox
        Left = 16
        Top = 16
        Width = 200
        Height = 17
        Caption = 'Always On Top'
        TabOrder = 0
      end
      object chkShowTransparency: TCheckBox
        Left = 16
        Top = 40
        Width = 200
        Height = 17
        Caption = 'Transparency'
        TabOrder = 1
      end
      object chkShowMoveToMonitor: TCheckBox
        Left = 16
        Top = 64
        Width = 200
        Height = 17
        Caption = 'Move To Monitor'
        TabOrder = 2
      end
      object chkShowAlign: TCheckBox
        Left = 16
        Top = 88
        Width = 200
        Height = 17
        Caption = 'Align'
        TabOrder = 3
      end
      object chkShowResize: TCheckBox
        Left = 16
        Top = 112
        Width = 200
        Height = 17
        Caption = 'Resize'
        TabOrder = 4
      end
      object chkShowRollUp: TCheckBox
        Left = 16
        Top = 136
        Width = 200
        Height = 17
        Caption = 'Roll Up'
        TabOrder = 5
      end
    end
    object tsAdvanced: TTabSheet
      Caption = 'Advanced'
      object rgSnapStrategy: TRadioGroup
        Left = 16
        Top = 16
        Width = 420
        Height = 73
        Caption = 'Snap Layouts Conflict Strategy'
        Items.Strings = (
          'Windows Snap priority (default)'
          'DeepRKey align priority')
        TabOrder = 0
      end
    end
  end
  object btnOK: TButton
    Left = 310
    Top = 367
    Width = 75
    Height = 25
    Caption = 'OK'
    Default = True
    TabOrder = 1
    OnClick = btnOKClick
  end
  object btnCancel: TButton
    Left = 391
    Top = 367
    Width = 75
    Height = 25
    Caption = 'Cancel'
    TabOrder = 2
    OnClick = btnCancelClick
  end
  object btnApply: TButton
    Left = 229
    Top = 367
    Width = 75
    Height = 25
    Caption = 'Apply'
    TabOrder = 3
    OnClick = btnApplyClick
  end
end
