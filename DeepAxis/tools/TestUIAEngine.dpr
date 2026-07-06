{*******************************************************************************
  TestUIAEngine — 运行时验证 UIA 引擎在微信 4.x 上的实际行为

  测试项:
    1. LocateWeChat — 窗口查找 + 版本检测
    2. IUIAutomation COM 初始化
    3. FindInputControlUIA — 控件树导航
    4. PasteScript — 三层降级 + 粘贴验证
    5. GetWeChatWindowState — 窗口状态感知
    6. SendFile — CF_HDROP 文件发送 (可选, 需要测试文件)
*******************************************************************************}
program TestUIAEngine;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils, System.Variants,
  Winapi.Windows,
  Winapi.ActiveX,
  Winapi.UIAutomation,
  DeepAxis.UIA.Engine in '..\src\uia\DeepAxis.UIA.Engine.pas';

function HResultToStr(HR: HRESULT): string;
begin
  if Succeeded(HR) then
    Result := Format('S_OK (0x%.8x)', [HR])
  else
    Result := Format('FAIL (0x%.8x)', [DWORD(HR)]);
end;

procedure WriteSeparator(const ATitle: string);
begin
  WriteLn;
  WriteLn('=== ', ATitle, ' ===');
  WriteLn(StringOfChar('-', 60));
end;

procedure TestLocateWeChat(AEngine: TUiaEngine);
var
  LResult: TUiaResult;
  LState: TWeChatWindowState;
begin
  WriteSeparator('Test 1: LocateWeChat + Version Detection');

  LResult := AEngine.LocateWeChat;
  WriteLn('  Success:      ', LResult.Success);
  WriteLn('  Strategy:     ', Ord(LResult.Strategy));
  WriteLn('  Duration:     ', LResult.DurationMs, ' ms');
  WriteLn('  Evidence:     ', LResult.Evidence);
  if not LResult.Success then
    WriteLn('  Error:        ', LResult.ErrorMessage);

  WriteLn;
  WriteLn('  WeChat Version: ', AEngine.Version.ToString);
  WriteLn('  IsV4Plus:       ', AEngine.Version.IsV4Plus);
  WriteLn('  ExePath:        ', AEngine.Version.ExePath);

  WriteLn;
  LState := AEngine.GetWeChatWindowState;
  WriteLn('  Window Exists:    ', LState.Exists);
  WriteLn('  Window Visible:   ', LState.Visible);
  WriteLn('  Window Foreground:', LState.Foreground);
  WriteLn('  Window Obstructed:', LState.Obstructed);
  WriteLn('  Window Handle:    ', LState.Handle);
  WriteLn('  Window Rect:      ', LState.Rect.Left, ',', LState.Rect.Top,
    ' ', LState.Rect.Width, 'x', LState.Rect.Height);
  WriteLn('  State String:     ', LState.StateString);
end;

procedure TestUIAInit(AEngine: TUiaEngine);
var
  LHR: HRESULT;
  LAuto: IUIAutomation;
  LWeChat: IUIAutomationElement;
  LWeChatHwnd: HWND;
  LFound: IUIAutomationElement;
  LClassName: OleVariant;
  LEditCond: IUIAutomationCondition;
  LDocCond: IUIAutomationCondition;
  LTreeWalker: IUIAutomationTreeWalker;
  LTrueCond: IUIAutomationCondition;
  LChild: IUIAutomationElement;
  LCount: Integer;
  LCName, LCClass, LCAutoId, LCType: OleVariant;
  LState: TWeChatWindowState;
begin
  WriteSeparator('Test 2: IUIAutomation COM Deep Dive (v4.x aware)');

  // 使用引擎已定位的窗口句柄
  LState := AEngine.GetWeChatWindowState;
  if not LState.Exists then
  begin
    WriteLn('  [FAIL] WeChat window not found by engine');
    Exit;
  end;
  LWeChatHwnd := LState.Handle;
  WriteLn('  [OK] Using engine window HWND=', Integer(LWeChatHwnd));

  // CoInitialize
  LHR := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  WriteLn('  CoInitializeEx: ', HResultToStr(LHR));

  // Create IUIAutomation
  LHR := CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
    IUIAutomation, LAuto);
  WriteLn('  CoCreateInstance: ', HResultToStr(LHR));
  if Failed(LHR) then
  begin
    WriteLn('  [FAIL] Cannot create IUIAutomation');
    Exit;
  end;

  // Get UIA Element from HWND
  LHR := LAuto.ElementFromHandle(LWeChatHwnd, LWeChat);
  WriteLn('  ElementFromHandle: ', HResultToStr(LHR));
  if Failed(LHR) or (LWeChat = nil) then
  begin
    WriteLn('  [FAIL] Cannot get UIA element from HWND');
    Exit;
  end;

  // Read window properties
  LWeChat.GetCurrentPropertyValue(UIA_NamePropertyId, LClassName);
  WriteLn('  WeChat Window Name: ', VarToStr(LClassName));
  LWeChat.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClassName);
  WriteLn('  WeChat Window Class: ', VarToStr(LClassName));
  LWeChat.GetCurrentPropertyValue(UIA_ControlTypePropertyId, LClassName);
  WriteLn('  WeChat Window CtrlType: ', VarToStr(LClassName));

  // Try to find EditControl in descendants
  WriteLn;
  WriteLn('  --- Searching for input control in descendants ---');

  // Method A: FindFirst with EditControl type
  LHR := LAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
    UIA_EditControlTypeId, LEditCond);
  WriteLn('  CreatePropertyCondition(EditControl): ', HResultToStr(LHR));
  if Succeeded(LHR) then
  begin
    LHR := LWeChat.FindFirst(TreeScope_Descendants, LEditCond, LFound);
    WriteLn('  FindFirst(EditControl, Descendants): ', HResultToStr(LHR));
    if Succeeded(LHR) and (LFound <> nil) then
    begin
      WriteLn('  [OK] Found EditControl!');
      LFound.GetCurrentPropertyValue(UIA_NamePropertyId, LClassName);
      WriteLn('  EditControl Name: ', VarToStr(LClassName));
      LFound.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClassName);
      WriteLn('  EditControl Class: ', VarToStr(LClassName));
    end
    else
      WriteLn('  [INFO] No EditControl (expected for WeChat 4.x Qt framework)');
  end;

  // Method B: FindFirst with DocumentControl type
  WriteLn;
  LHR := LAuto.CreatePropertyCondition(UIA_ControlTypePropertyId,
    UIA_DocumentControlTypeId, LDocCond);
  WriteLn('  CreatePropertyCondition(DocumentControl): ', HResultToStr(LHR));
  if Succeeded(LHR) then
  begin
    LHR := LWeChat.FindFirst(TreeScope_Descendants, LDocCond, LFound);
    WriteLn('  FindFirst(DocumentControl, Descendants): ', HResultToStr(LHR));
    if Succeeded(LHR) and (LFound <> nil) then
    begin
      WriteLn('  [OK] Found DocumentControl!');
      LFound.GetCurrentPropertyValue(UIA_NamePropertyId, LClassName);
      WriteLn('  DocumentControl Name: ', VarToStr(LClassName));
      LFound.GetCurrentPropertyValue(UIA_ClassNamePropertyId, LClassName);
      WriteLn('  DocumentControl Class: ', VarToStr(LClassName));
    end
    else
      WriteLn('  [INFO] No DocumentControl');
  end;

  // Enumerate top-level children
  WriteLn;
  WriteLn('  --- Top-level children of WeChat window ---');
  LHR := LAuto.CreateTrueCondition(LTrueCond);
  if Succeeded(LHR) then
  begin
    LHR := LAuto.CreateTreeWalker(LTrueCond, LTreeWalker);
    if Succeeded(LHR) then
    begin
      LHR := LTreeWalker.GetFirstChildElement(LWeChat, LChild);
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
           VarToStr(LCClass), VarToStr(LCType)]));
        LChild := nil;
        LHR := LTreeWalker.GetNextSiblingElement(LChild, LChild);
      end;
      WriteLn('  Total children: ', LCount);
    end;
  end;
end;

procedure TestPasteScript(AEngine: TUiaEngine);
var
  LResult: TUiaResult;
  LTestScript: string;
begin
  WriteSeparator('Test 3: PasteScript (Three-Tier Fallback)');

  LTestScript := '[UIA Engine v2 Test] ' + FormatDateTime('hh:nn:ss', Now)
    + ' — 这是一条测试话术，验证粘贴功能。';

  WriteLn('  Script: ', LTestScript);
  WriteLn('  Pasting... (请切换到微信窗口观察)');
  Sleep(1000);

  LResult := AEngine.PasteScript(LTestScript);

  WriteLn;
  WriteLn('  Success:   ', LResult.Success);
  WriteLn('  Strategy:  ', Ord(LResult.Strategy));
  WriteLn('  Retries:   ', LResult.RetryCount);
  WriteLn('  Duration:  ', LResult.DurationMs, ' ms');
  WriteLn('  Evidence:  ', LResult.Evidence);
  if not LResult.Success then
    WriteLn('  Error:     ', LResult.ErrorMessage);
end;

procedure TestSendFile(AEngine: TUiaEngine);
var
  LResult: TUiaResult;
  LTempFile: string;
begin
  WriteSeparator('Test 4: SendFile (CF_HDROP)');

  // 创建临时测试文件
  LTempFile := TPath.Combine(TPath.GetTempPath, 'uia_test_file.txt');
  TFile.WriteAllText(LTempFile, 'UIA Engine Test File - ' + DateTimeToStr(Now));
  WriteLn('  Temp file: ', LTempFile);

  WriteLn('  Sending file... (请切换到微信窗口观察)');
  Sleep(1000);

  LResult := AEngine.SendFile(LTempFile);

  WriteLn;
  WriteLn('  Success:   ', LResult.Success);
  WriteLn('  Strategy:  ', Ord(LResult.Strategy));
  WriteLn('  Duration:  ', LResult.DurationMs, ' ms');
  WriteLn('  Evidence:  ', LResult.Evidence);

  // 清理
  if TFile.Exists(LTempFile) then
    TFile.Delete(LTempFile);
end;

var
  GEngine: TUiaEngine;

begin
  try
    WriteLn('╔══════════════════════════════════════════════════════╗');
    WriteLn('║  DeepAxis UIA Engine v2 — Runtime Verification      ║');
    WriteLn('║  Target: WeChat 4.x on this machine                 ║');
    WriteLn('╚══════════════════════════════════════════════════════╝');
    WriteLn;
    WriteLn('请确保微信已打开并登录。');
    WriteLn('3 秒后自动开始测试...');
    Sleep(3000);

    GEngine := TUiaEngine.Create;
    try
      TestLocateWeChat(GEngine);
      TestUIAInit(GEngine);
      TestPasteScript(GEngine);
      TestSendFile(GEngine);

      WriteSeparator('Summary');
      WriteLn('  All tests completed. Check output above for details.');
      WriteLn('  WeChat version: ', GEngine.Version.ToString);
      WriteLn('  IsV4Plus:       ', GEngine.Version.IsV4Plus);
    finally
      GEngine.Free;
    end;

    WriteLn;
    WriteLn('测试完成。');
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('[FATAL] ', E.ClassName, ': ', E.Message);
    end;
  end;
end.
