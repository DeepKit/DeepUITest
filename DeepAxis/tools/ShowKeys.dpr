program ShowKeys;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DeepAxis.WeChat.Decrypt;

var
  LKeyMgr: TKeyManager;
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
begin
  LKeyMgr := TKeyManager.Create;
  try
    LKeyMgr.LoadFromJSON(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json'));
    LKeys := LKeyMgr.FindKeysForDir('D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage');
    Writeln('密钥列表:');
    for LEntry in LKeys do
      Writeln('  [' + LEntry.DbRelPath + ']');
  finally
    LKeyMgr.Free;
  end;
  Readln;
end.
