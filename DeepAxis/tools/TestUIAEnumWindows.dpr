{*******************************************************************************
  TestUIAEnumWindows — 枚举所有顶层窗口，找到微信 4.x 的真实窗口类名
*******************************************************************************}
program TestUIAEnumWindows;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Variants,
  Winapi.Windows,
  Winapi.ActiveX,
  Winapi.UIAutomation;

type
  TEnumResult = class
    Lines: TStringList;
    WeChatHandles: TList;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TEnumResult.Create;
begin
  inherited;
  Lines := TStringList.Create;
  WeChatHandles := TList.Create;
end;

destructor TEnumResult.Destroy;
begin
  Lines.Free;
  WeChatHandles.Free;
  inherited;
end;

function EnumWndProc(hwnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  LClassName: array[0..255] of Char;
  LWndText: array[0..255] of Char;
  LResult: TEnumResult;
  LVisible: Boolean;
  LClassStr: string;
  LTitleStr: string;
begin
  LResult := TEnumResult(lParam);
  GetClassNameW(hwnd, LClassName, SizeOf(LClassName));
  GetWindowTextW(hwnd, LWndText, SizeOf(LWndText));

  LVisible := IsWindowVisible(hwnd);
  LClassStr := string(LClassName);
  LTitleStr := string(LWndText);

  // 记录所有包含 "WeChat" 或 "wechat" 的窗口
  if (Pos('WeChat', LClassStr) > 0) or
     (Pos('wechat', LClassStr) > 0) or
     (Pos('WeChat', LTitleStr) > 0) or
     (Pos('微信', LTitleStr) > 0) then
  begin
    LResult.Lines.Add(Format('[MATCH] HWND=%d Class="%s" Title="%s" Visible=%s',
      [hwnd, LClassStr, LTitleStr, if LVisible then 'yes' else 'no']));
    LResult.WeChatHandles.Add(Pointer(hwnd));
  end;

  // 也记录所有可见的顶层窗口 (用于排查)
  if LVisible and (LTitleStr <> '') then
    LResult.Lines.Add(Format('  HWND=%d Class="%s" Title="%s"',
      [hwnd, LClassStr, LTitleStr]));

  Result := True; // 继续枚举
end;

procedure EnumerateWindows;
var
  LResult: TEnumResult;
  I: Integer;
  LProcNames: array of string;
  LHR: HRESULT;
  LAuto: IUIAutomation;
  LRoot: IUIAutomationElement;
  LFound: IUIAutomationElement;
  LClassNames: TArray<string>;
  LClassName: string;
  LCond: IUIAutomationCondition;
  LName: OleVariant;
  LTreeWalker: IUIAutomationTreeWalker;
  LTrueCond: IUIAutomationCondition;
  LChild: IUIAutomationElement;
  LCount: Integer;
  LCName, LCClass, LCAutoId: OleVariant;
  LSName, LSClass: string;
begin
  LResult := TEnumResult.Create;
  try
    WriteLn('=== Enumerating all top-level windows ===');
    WriteLn;

    EnumWindows(@EnumWndProc, LPARAM(LResult));

    WriteLn(LResult.Lines.Text);

    WriteLn;
    WriteLn('=== WeChat-related windows found: ', LResult.WeChatHandles.Count, ' ===');

    if LResult.WeChatHandles.Count = 0 then
    begin
      WriteLn('[WARN] No WeChat windows found!');
      WriteLn;
      WriteLn('Checking WeChat processes...');
      SetLength(LProcNames, 0);
      // 使用 tasklist 结果 — 已知有 WeChatAppEx.exe
      WriteLn('  Known: WeChatAppEx.exe processes are running (from tasklist)');
      WriteLn('  WeChat 4.x likely uses a different window class name.');
    end
    else
    begin
      for I := 0 to LResult.WeChatHandles.Count - 1 do
      begin
        var LH: HWND;
        var LPid: DWORD;
        LH := HWND(LResult.WeChatHandles[I]);
        GetWindowThreadProcessId(LH, LPid);
        WriteLn(Format('  [%d] HWND=%d PID=%d', [I, LH, LPid]));
      end;
    end;

    // Also try UIA to find any WeChat-related elements
    WriteLn;
    WriteLn('=== UIA: Search by different class names ===');

    LHR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
    LHR := CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
      IUIAutomation, LAuto);

    if Succeeded(LHR) then
    begin
      LHR := LAuto.GetRootElement(LRoot);
      if Succeeded(LHR) then
      begin
        // 尝试不同的类名
        LClassNames := TArray<string>.Create(
          'WeChatMainWndForPC',      // 微信 3.x
          'WeChat MainWindow',       // 可能的新类名
          'WeChatAppWnd',            // 猜测
          'Chrome_WidgetWin_0',      // Electron-like
          'Qt5QWindowIcon',          // Qt
          'Qt5152QWindowIcon',       // Qt version-specific
          'QWidget',                 // Qt base
          'CefWebViewWnd',           // CEF
          'WeChat Login',            // 登录窗口
          'WeChatChatWndForPC'       // 另一个猜测
        );

        for LClassName in LClassNames do
        begin
          LHR := LAuto.CreatePropertyCondition(UIA_ClassNamePropertyId, LClassName, LCond);
          if Succeeded(LHR) and (LCond <> nil) then
          begin
            LHR := LRoot.FindFirst(TreeScope_Children, LCond, LFound);
            if Succeeded(LHR) and (LFound <> nil) then
            begin
              LFound.GetCurrentPropertyValue(UIA_NamePropertyId, LName);
              WriteLn(Format('  [FOUND] Class="%s" Name="%s"', [LClassName, VarToStr(LName)]));
            end;
          end;
        end;

        // 也列出 UIA 可见的所有顶层窗口
        WriteLn;
        WriteLn('=== UIA: All top-level children of desktop ===');
        LHR := LAuto.CreateTrueCondition(LTrueCond);
        if Succeeded(LHR) then
        begin
          LHR := LAuto.CreateTreeWalker(LTrueCond, LTreeWalker);
          if Succeeded(LHR) then
          begin
            LHR := LTreeWalker.GetFirstChildElement(LRoot, LChild);
            LCount := 0;
            while Succeeded(LHR) and (LChild <> nil) and (LCount < 50) do
            begin
              Inc(LCount);
              LChild.GetCurrentPropertyValue(UIA_NamePropertyId, LCName);
              LChild.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LCClass);
              LChild.GetCurrentPropertyValue(UIA_AutomationIdPropertyId, LCAutoId);
              // 只打印名称或类名包含 WeChat 的
              LSName := VarToStr(LCName);
              LSClass := VarToStr(LCClass);
              if (Pos('WeChat', LSName) > 0) or (Pos('微信', LSName) > 0) or
                 (Pos('WeChat', LSClass) > 0) or (Pos('wechat', LSClass) > 0) then
              begin
                WriteLn(Format('  [MATCH] [%d] Name="%s" Class="%s" AutoId="%s"',
                  [LCount, LSName, LSClass, VarToStr(LCAutoId)]));
              end;
              LChild := nil;
              LHR := LTreeWalker.GetNextSiblingElement(LChild, LChild);
            end;
            WriteLn('  Total desktop children: ', LCount);
          end;
        end;
      end;
    end;

  finally
    LResult.Free;
  end;
end;

begin
  try
    WriteLn('╔══════════════════════════════════════════════════════╗');
    WriteLn('║  TestUIAEnumWindows — Find WeChat 4.x Window Class  ║');
    WriteLn('╚══════════════════════════════════════════════════════╝');
    WriteLn;

    EnumerateWindows;

    WriteLn;
    WriteLn('Done.');
  except
    on E: Exception do
      WriteLn('[FATAL] ', E.ClassName, ': ', E.Message);
  end;
end.
