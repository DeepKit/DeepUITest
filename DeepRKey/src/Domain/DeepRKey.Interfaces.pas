unit DeepRKey.Interfaces;

interface

uses
  System.SysUtils;

type
  /// <summary>配置存储接口（v0.1: USE_STUB / v0.2+: USE_DEEPBASE）</summary>
  IRKeyConfig = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function ReadBool(const Key: string; Default: Boolean): Boolean;
    function ReadString(const Key, Default: string): string;
    function ReadInteger(const Key: string; Default: Integer): Integer;
    procedure WriteBool(const Key: string; Value: Boolean);
    procedure WriteString(const Key, Default: string);
    procedure WriteInteger(const Key: string; Value: Integer);
    procedure Apply;
  end;

  /// <summary>日志接口（v0.1: Stub/OutputDebugString / v0.2+: DeepBase.Logger）</summary>
  IRKeyLogger = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    procedure Info(const Msg, Category: string);
    procedure Warn(const Msg, Category: string);
    procedure Error(const Msg, Category: string);
    procedure Debug(const Msg: string);  // 仅在 Debug 构建或诊断模式输出
  end;

  /// <summary>国际化接口（v0.1: Stub/ResourceString / v0.2+: DeepBase.I18n）</summary>
  IRKeyI18n = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    function T(const Key, Default: string): string;
    procedure SetLanguage(const LangCode: string);
    function GetCurrentLanguage: string;
  end;

implementation

end.