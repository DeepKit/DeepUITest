{*******************************************************************************
  TestFindWeChat — 测试 FindWindowW 查找微信窗口
*******************************************************************************}
program TestFindWeChat;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows;

var
  LWnd: HWND;
  LTitle: array[0..255] of WideChar;
  LTitleStr: string;
  I: Integer;
  LSearchTitle: string;
begin
  WriteLn('=== Testing FindWindowW for WeChat ===');
  WriteLn;

  // Test 1: FindWindowW with class and title
  LWnd := FindWindowW('Qt51514QWindowIcon', '微信');
  WriteLn(Format('FindWindowW(Qt51514QWindowIcon, 微信): HWND=%d', [Integer(LWnd)]));

  // Test 2: FindWindowW with class only
  LWnd := FindWindowW('Qt51514QWindowIcon', nil);
  WriteLn(Format('FindWindowW(Qt51514QWindowIcon, nil): HWND=%d', [Integer(LWnd)]));

  if LWnd <> 0 then
  begin
    GetWindowTextW(LWnd, LTitle, Length(LTitle));
    LTitleStr := string(LTitle);
    WriteLn(Format('  Title: "%s" (len=%d)', [LTitleStr, Length(LTitleStr)]));
    Write('  Title bytes: ');
    for I := 1 to Length(LTitleStr) do
      Write(Format('%.4x ', [Ord(LTitleStr[I])]));
    WriteLn;
  end;

  // Test 3: FindWindowW with "Weixin" title
  LWnd := FindWindowW('Qt51514QWindowIcon', 'Weixin');
  WriteLn(Format('FindWindowW(Qt51514QWindowIcon, Weixin): HWND=%d', [Integer(LWnd)]));

  // Test 4: Use a variable for the title
  LSearchTitle := '微信';
  LWnd := FindWindowW('Qt51514QWindowIcon', PWideChar(LSearchTitle));
  WriteLn(Format('FindWindowW with PWideChar variable: HWND=%d', [Integer(LWnd)]));

  if LWnd <> 0 then
  begin
    GetWindowTextW(LWnd, LTitle, Length(LTitle));
    LTitleStr := string(LTitle);
    WriteLn(Format('  Title: "%s" (len=%d)', [LTitleStr, Length(LTitleStr)]));
  end;
end.
