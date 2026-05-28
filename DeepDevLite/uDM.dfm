object DM: TDM
  OldCreateOrder = False
  Height = 150
  Width = 215
  object ConnConfig: TFDConnection
    Params.Strings = (
      'Database=DeepDevLiteConfig.db'
      'DriverID=SQLite'
      'LockingMode=Normal')
    Connected = True
    LoginPrompt = False
    Left = 40
    Top = 24
  end
  object ConnData: TFDConnection
    Params.Strings = (
      'DriverID=SQLite'
      'LockingMode=Normal')
    LoginPrompt = False
    Left = 40
    Top = 80
  end
end
