{*******************************************************************************
  TestQtWeChatCheck — 快速验证 Qt51514QWindowIcon 是否是微信 4.x 主窗口
*******************************************************************************}
program TestQtWeChatCheck;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Variants,
  Winapi.Windows, Winapi.ActiveX, Winapi.UIAutomation;

var
  GQtHwnd: HWND;
  GQtPid: DWORD;
  GQtFound: Boolean;

function FindQtWeChatEnumProc(hwnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  LClassName: array[0..255] of Char;
  LWndText: array[0..255] of Char;
  LPid: DWORD;
  LTitleStr: string;
  LClassStr: string;
  LTitleLen: Integer;
  I: Integer;
begin
  GetClassNameW(hwnd, LClassName, SizeOf(LClassName));
  if string(LClassName) = 'Qt51514QWindowIcon' then
  begin
    GetWindowTextW(hwnd, LWndText, SizeOf(LWndText));
    GetWindowThreadProcessId(hwnd, LPid);
    LTitleStr := string(LWndText);
    LClassStr := string(LClassName);
    LTitleLen := Length(LTitleStr);
    WriteLn(Format('[FOUND] HWND=%d PID=%d Class="%s" Title="%s" (len=%d)',
      [hwnd, Integer(LPid), LClassStr, LTitleStr, LTitleLen]));
    Write('  Title bytes: ');
    for I := 1 to LTitleLen do
      Write(Format('%.4x ', [Ord(LTitleStr[I])]));
    WriteLn;

    GQtHwnd := hwnd;
    GQtPid := LPid;
    GQtFound := True;
  end;
  Result := True;
end;

procedure TryUIAOnQtWindow;
var
  LHR: HRESULT;
  LAuto: IUIAutomation;
  LRoot: IUIAutomationElement;
  LElement: IUIAutomationElement;
  LCond: IUIAutomationCondition;
  LTreeWalker: IUIAutomationTreeWalker;
  LChild: IUIAutomationElement;
  LTrueCond: IUIAutomationCondition;
  LCount: Integer;
  LCName, LCClass, LCAutoId, LCType: OleVariant;
begin
  WriteLn;
  WriteLn('=== UIA: Query Qt51514QWindowIcon window ===');

  if not GQtFound then
  begin
    WriteLn('[SKIP] Qt window not found');
    Exit;
  end;

  LHR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  LHR := CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
    IUIAutomation, LAuto);
  if not Succeeded(LHR) then
  begin
    WriteLn('[FAIL] Cannot create IUIAutomation');
    Exit;
  end;

  // Try ElementFromHandle first (direct HWND binding)
  LHR := LAuto.ElementFromHandle(GQtHwnd, LElement);
  if Succeeded(LHR) and (LElement <> nil) then
  begin
    var LName: OleVariant;
    LElement.GetCurrentPropertyValue(UIA_NamePropertyId, LName);
    var LClass: OleVariant;
    LElement.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClass);
    var LAutoId: OleVariant;
    LElement.GetCurrentPropertyValue(UIA_AutomationIdPropertyId, LAutoId);
    var LCtrlType: OleVariant;
    LElement.GetCurrentPropertyValue(UIA_ControlTypePropertyId, LCtrlType);
    WriteLn(Format('  [UIA OK] Name="%s" Class="%s" AutoId="%s" CtrlType=%s',
      [VarToStr(LName), VarToStr(LClass), VarToStr(LAutoId), VarToStr(LCtrlType)]));

    // Try to find EditControl or DocumentControl in descendants
    WriteLn;
    WriteLn('  --- Searching descendants for input controls ---');

    var LEditCond: IUIAutomationCondition;
    var LFound: IUIAutomationElement;

    LHR := LAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
      UIA_EditControlTypeId, LEditCond);
    if Succeeded(LHR) then
    begin
      LHR := LElement.FindFirst(TreeScope_Descendants, LEditCond, LFound);
      if Succeeded(LHR) and (LFound <> nil) then
      begin
        LFound.GetCurrentPropertyValue(UIA_NamePropertyId, LName);
        LFound.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClass);
        WriteLn(Format('  [EDIT] Found EditControl: Name="%s" Class="%s"',
          [VarToStr(LName), VarToStr(LClass)]));
      end
      else
        WriteLn('  [INFO] No EditControl found in Qt window descendants');
    end;

    LHR := LAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
      UIA_DocumentControlTypeId, LEditCond);
    if Succeeded(LHR) then
    begin
      LHR := LElement.FindFirst(TreeScope_Descendants, LEditCond, LFound);
      if Succeeded(LHR) and (LFound <> nil) then
      begin
        LFound.GetCurrentPropertyValue(UIA_NamePropertyId, LName);
        LFound.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClass);
        WriteLn(Format('  [DOC] Found DocumentControl: Name="%s" Class="%s"',
          [VarToStr(LName), VarToStr(LClass)]));
      end
      else
        WriteLn('  [INFO] No DocumentControl found in Qt window descendants');
    end;

    // Enumerate top-level children of Qt window
    WriteLn;
    WriteLn('  --- Top-level children of Qt WeChat window ---');
    LHR := LAuto.CreateTrueCondition(LTrueCond);
    if Succeeded(LHR) then
    begin
      LHR := LAuto.CreateTreeWalker(LTrueCond, LTreeWalker);
      if Succeeded(LHR) then
      begin
        LHR := LTreeWalker.GetFirstChildElement(LElement, LChild);
        LCount := 0;
        while Succeeded(LHR) and (LChild <> nil) and (LCount < 30) do
        begin
          Inc(LCount);
          LChild.GetCurrentPropertyValue(UIA_NamePropertyId, LCName);
          LChild.GetCurrentPropertyValue(UIA_AutomationIdPropertyId, LCAutoId);
          LChild.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LCClass);
          LChild.GetCurrentPropertyValue(UIA_ControlTypePropertyId, LCType);
          WriteLn(Format('  [%d] Name="%s" AutoId="%s" Class="%s" Type=%s',
            [LCount, VarToStr(LCName), VarToStr(LCAutoId),
             VarToStr(LCClass), VarToStr(LCtrlType)]));
          LChild := nil;
          LHR := LTreeWalker.GetNextSiblingElement(LChild, LChild);
        end;
        WriteLn('  Total children: ', LCount);
      end;
    end;
  end
  else
    WriteLn(Format('  [FAIL] ElementFromHandle: HR=0x%.8x', [DWORD(LHR)]));
end;

begin
  try
    WriteLn('╔══════════════════════════════════════════════════════╗');
    WriteLn('║  TestQtWeChatCheck — Verify Qt Window = WeChat 4.x  ║');
    WriteLn('╚══════════════════════════════════════════════════════╝');
    WriteLn;

    GQtFound := False;
    GQtHwnd := 0;
    GQtPid := 0;

    EnumWindows(@FindQtWeChatEnumProc, 0);

    if GQtFound then
      WriteLn(Format('  -> PID %d belongs to Qt WeChat window', [GQtPid]))
    else
      WriteLn('  -> Qt window NOT found!');

    TryUIAOnQtWindow;

    WriteLn;
    WriteLn('Done.');
  except
    on E: Exception do
      WriteLn('[FATAL] ', E.ClassName, ': ', E.Message);
  end;
end.
