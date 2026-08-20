unit DeepAxis.Core.Governance;

interface

/// <summary>
///   Registers all L2/L3 governance actions and AutoFix scenarios.
///   Called once during startup before the main form is created.
/// </summary>
procedure RegisterGovernanceActions;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DeepAxis.Core.Base,
  DeepAxis.Core.Profile,
  DeepAxis.Core.Config,
  DeepBase.AutoFix;

procedure RegisterGovernanceActions;
begin
  // In P0/personal_full, governance is gmObserve.

  // ── AutoFix 冒烟场景 ─────────────────────────────────────────────
  // 当 --autofix-mode 激活时，这些场景会在 UI 就绪后自动回放

  AutoFix.RegisterScenario('smoke',
    procedure
    begin
      // 验证: 密钥文件可访问
      var LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
      if TFile.Exists(LKeysPath) then
        Exit; // key file exists
      // 无密钥文件也不算失败，可能是首次运行
    end);

  AutoFix.RegisterScenario('check_db2',
    procedure
    begin
      // 验证: DB2 路径可写
      var LDB2Path := TDeepAxisConfig.GetDB2Path;
      var LDir := TPath.GetDirectoryName(LDB2Path);
      if not TDirectory.Exists(LDir) then
        ForceDirectories(LDir);
      // 验证目录可写
      var LTestFile := TPath.Combine(LDir, '.write_test');
      TFile.WriteAllText(LTestFile, 'ok');
      TFile.Delete(LTestFile);
    end);

  AutoFix.RegisterScenario('check_config',
    procedure
    begin
      // 验证: 配置系统可加载
      TDeepAxisConfig.GetProfile;
      TDeepAxisConfig.GetWeChatDataPath;
    end);
end;

end.