program TestKeyCapture;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Winapi.Windows, Winapi.TlHelp32,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Config,
  DeepAxis.WeChat.Decrypt, DeepAxis.WeChat.Scanner;

procedure WriteLog(const AMsg: string);
begin
  Writeln(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

procedure DoKeyCaptureTest;
var
  LScanner: TWeChatScanner;
  LPid: Cardinal;
  LResult: TWeChatKeyCaptureResult;
begin
  WriteLog('=== 密钥捕获测试 ===');
  WriteLog('');

  LScanner := TWeChatScanner.Create;
  try
    // 1. 检查微信进程
    WriteLog('[1] 检查微信进程...');
    LPid := LScanner.FindWeChatProcess;
    if LPid = 0 then
    begin
      WriteLog('  X 未找到微信进程');
      WriteLog('  请先启动微信并登录');
      Exit;
    end;
    WriteLog('  OK 微信进程 PID: ' + IntToStr(LPid));

    // 2. 尝试已保存的密钥
    WriteLog('');
    WriteLog('[2] 尝试已保存的密钥...');
    if LScanner.TrySavedKeysOnly then
    begin
      WriteLog('  OK 使用已保存的密钥');
      WriteLog('  解密文件路径:');
      WriteLog('    Contact: ' + LScanner.DecryptedContactPath);
      WriteLog('    Message: ' + LScanner.DecryptedMessage0Path);
      WriteLog('    Session: ' + LScanner.DecryptedSessionPath);
      Exit;
    end
    else
      WriteLog('  X 无可用密钥');

    // 3. 尝试完整扫描
    WriteLog('');
    WriteLog('[3] 开始内存扫描...');
    WriteLog('  这可能需要10-30秒...');
    LResult := LScanner.StartScan;

    WriteLog('');
    WriteLog('[4] 扫描结果:');
    if LResult.IsSuccess then
    begin
      WriteLog('  OK 密钥捕获成功!');
      WriteLog('  状态: ' + WeChatStateToStr(LResult.State));
      WriteLog('  微信版本: ' + LResult.WeChatVersion);
      WriteLog('');
      WriteLog('  解密文件:');
      WriteLog('    Contact: ' + LScanner.DecryptedContactPath);
      WriteLog('    Message: ' + LScanner.DecryptedMessage0Path);
      WriteLog('    Session: ' + LScanner.DecryptedSessionPath);
    end
    else
    begin
      WriteLog('  X 密钥捕获失败');
      WriteLog('  状态: ' + WeChatStateToStr(LResult.State));
      WriteLog('  错误: ' + LResult.ErrorMessage);
      WriteLog('');
      WriteLog('  可能的原因:');
      WriteLog('  1. 微信未登录或刚启动，密钥尚未生成');
      WriteLog('  2. 需要管理员权限');
      WriteLog('  3. 微信版本不兼容');
      WriteLog('  4. 内存保护机制');
    end;
  finally
    LScanner.Free;
  end;
end;

begin
  WriteLog('DeepAxis 密钥捕获测试工具');
  WriteLog('');
  DoKeyCaptureTest;
  Writeln('');
  Write('按回车键退出...');
  Readln;
end.
