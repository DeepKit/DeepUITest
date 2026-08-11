{*******************************************************************************
  TestWeChatOwnership — 检查微信窗口是否被其他窗口拥有
*******************************************************************************}
program TestWeChatOwnership;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes,
  Winapi.Windows;

type
  PWindowInfo = ^TWindowInfo;
  TWindowInfo = record
    Handle: HWND;
    Title: string;
    Owner: HWND;
    Parent: HWND;
    Visible: Boolean;
  end;

var
  GQtWindows: TList;

function EnumAllQtWindows(hwnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  LClassName: array[0..255] of WideChar;
  LTitle: array[0..255] of WideChar;
  LClassStr: string;
  LInfo: PWindowInfo;
begin
  GetClassNameW(hwnd, LClassName, 256);
  LClassStr := string(LClassName);
  if LClassStr <> 'Qt51514QWindowIcon' then
  begin
    Result := True;
    Exit;
  end;

  GetWindowTextW(hwnd, LTitle, 256);

  New(LInfo);
  LInfo.Handle := hwnd;
  LInfo.Title := string(LTitle);
  LInfo.Owner := GetWindow(hwnd, GW_OWNER);
  LInfo.Parent := GetParent(hwnd);
  LInfo.Visible := IsWindowVisible(hwnd);
  GQtWindows.Add(LInfo);

  Result := True;
end;

var
  I: Integer;
  LInfo: PWindowInfo;
  J: Integer;
  LVisStr: string;
begin
  WriteLn('=== Checking Qt window ownership ===');
  WriteLn;

  GQtWindows := TList.Create;
  try
    EnumWindows(@EnumAllQtWindows, 0);

    WriteLn('Found ', GQtWindows.Count, ' Qt windows:');
    WriteLn;

    for I := 0 to GQtWindows.Count - 1 do
    begin
      LInfo := PWindowInfo(GQtWindows[I]);
      WriteLn('  [', I, '] HWND=', Integer(LInfo.Handle));
      WriteLn('      Title: "', LInfo.Title, '" (len=', Length(LInfo.Title), ')');
      Write('      Title bytes: ');
      for J := 1 to Length(LInfo.Title) do
        Write(Format('%.4x ', [Ord(LInfo.Title[J])]));
      WriteLn;
      if LInfo.Visible then
        LVisStr := 'yes'
      else
        LVisStr := 'no';
      WriteLn('      Owner: ', Integer(LInfo.Owner),
              ', Parent: ', Integer(LInfo.Parent),
              ', Visible: ', LVisStr);
      WriteLn;
      Dispose(LInfo);
    end;
  finally
    GQtWindows.Free;
  end;

  WriteLn('Done.');
end.
