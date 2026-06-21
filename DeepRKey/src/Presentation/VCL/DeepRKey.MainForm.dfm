object frmMain: TfrmMain
  Left = 0
  Top = 0
  BorderIcons = []
  BorderStyle = bsNone
  Caption = 'DeepRKey'
  ClientHeight = 0
  ClientWidth = 0
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDefault
  Visible = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  object TrayIcon: TTrayIcon
    PopupMenu = TrayPopupMenu
    Visible = False
  end
  object TrayPopupMenu: TPopupMenu
    Left = 8
    Top = 8
    object miPause: TMenuItem
      Caption = 'Pause'
      OnClick = miPauseClick
    end
    object miSettings: TMenuItem
      Caption = 'Settings...'
      OnClick = miSettingsClick
    end
    object miAbout: TMenuItem
      Caption = 'About...'
      OnClick = miAboutClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object miExit: TMenuItem
      Caption = 'Exit'
      OnClick = miExitClick
    end
  end
end