program TestSavedKeys;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DeepAxis.Core.Base, DeepAxis.Core.Config,
  DeepAxis.WeChat.Decrypt, DeepAxis.WeChat.Scanner;

procedure WriteLog(const AMsg: string);
begin
  Writeln(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

var
  LScanner: TWeChatScanner;
  LKeysPath, LDataDir: string;
begin
  WriteLog('=== 测试已保存的密钥 ===');
  WriteLog('');

  LScanner := TWeChatScanner.Create;
  try
    // 查找密钥文件
    WriteLog('[1] 查找密钥文件...');
    LKeysPath := LScanner.FindSavedKeysPath;
    if LKeysPath = '' then
    begin
      WriteLog('  X 未找到密钥文件');
      Exit;
    end;
    WriteLog('  OK 找到密钥文件: ' + LKeysPath);

    // 尝试加载密钥
    WriteLog('');
    WriteLog('[2] 加载密钥...');
    if LScanner.KeyManager.LoadFromJSON(LKeysPath) then
    begin
      WriteLog('  OK 密钥加载成功');
      WriteLog('  密钥数量: ' + IntToStr(LScanner.KeyManager.GetKeyCount));
    end
    else
    begin
      WriteLog('  X 密钥加载失败');
      Exit;
    end;

    // 查找微信数据目录
    WriteLog('');
    WriteLog('[3] 查找微信数据目录...');
    LDataDir := LScanner.FindWeChatDataDir;
    if LDataDir = '' then
    begin
      WriteLog('  X 未找到微信数据目录');
      Exit;
    end;
    WriteLog('  OK 微信数据目录: ' + LDataDir);

    // 尝试解密
    WriteLog('');
    WriteLog('[4] 尝试解密数据库...');
    if LScanner.TrySavedKeysOnly then
    begin
      WriteLog('  OK 解密成功!');
      WriteLog('  解密文件:');
      WriteLog('    Contact: ' + LScanner.DecryptedContactPath);
      WriteLog('    Message: ' + LScanner.DecryptedMessage0Path);
      WriteLog('    Session: ' + LScanner.DecryptedSessionPath);

      // 检查文件是否存在
      WriteLog('');
      WriteLog('[5] 验证解密文件...');
      if TFile.Exists(LScanner.DecryptedContactPath) then
        WriteLog('  OK Contact 文件存在 (' + IntToStr(TFile.GetSize(LScanner.DecryptedContactPath)) + ' bytes)')
      else
        WriteLog('  X Contact 文件不存在');

      if TFile.Exists(LScanner.DecryptedMessage0Path) then
        WriteLog('  OK Message 文件存在 (' + IntToStr(TFile.GetSize(LScanner.DecryptedMessage0Path)) + ' bytes)')
      else
        WriteLog('  X Message 文件不存在');

      if TFile.Exists(LScanner.DecryptedSessionPath) then
        WriteLog('  OK Session 文件存在 (' + IntToStr(TFile.GetSize(LScanner.DecryptedSessionPath)) + ' bytes)')
      else
        WriteLog('  X Session 文件不存在');
    end
    else
    begin
      WriteLog('  X 解密失败');
    end;
  finally
    LScanner.Free;
  end;

  Writeln('');
  Write('按回车键退出...');
  Readln;
end.
