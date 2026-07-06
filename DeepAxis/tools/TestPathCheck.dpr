program TestPathCheck;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils;

var
  LDataDir, LDbRelPath, LFullPath: string;
begin
  LDataDir := 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage';
  LDbRelPath := 'contact\contact.db';
  LFullPath := TPath.Combine(LDataDir, LDbRelPath);

  Writeln('数据目录: ' + LDataDir);
  Writeln('相对路径: ' + LDbRelPath);
  Writeln('完整路径: ' + LFullPath);
  Writeln('文件存在: ' + BoolToStr(TFile.Exists(LFullPath), True));

  // 列出实际文件
  Writeln('');
  Writeln('实际文件:');
  var LFiles := TDirectory.GetFiles(LDataDir + '\contact', '*.db');
  for var LFile in LFiles do
    Writeln('  ' + LFile);
end.
