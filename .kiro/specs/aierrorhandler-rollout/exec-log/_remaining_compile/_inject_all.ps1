# Batch inject AIErrorHandler bootstrap into G10/G11/G13/G14/G15/G16part dprs.
# Uses byte-level injection to preserve any non-UTF8 encoding mojibake.
$ErrorActionPreference = 'Stop'
$InjectScript = 'D:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g8_compile\_inject.ps1'

# Schema:
#   path        : absolute path to .dpr
#   usesAnchor  : line content (without trailing CRLF) AFTER which the uses-injection goes
#                 ('' = skip uses inject, file already has Bootstrap in uses)
#   usesLine    : the uses-injection line (without trailing CRLF)
#   callAnchor  : line content AFTER which the call-injection goes
#                 (typically 'begin', or specific line in main body)
#   callLine    : the call-injection line (e.g. '  InstallAIErrorHandler;' or
#                 '  InstallAIErrorHandlerForTests;')
$jobs = @(
  # ------ G10 Demos (Production_Mode, InstallAIErrorHandler) ------
  @{ path='D:\_Progs\02Business\DeepBase\doQry\examples\DoQryDemo\DoQryDemo.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\DataBindingDemo\DataBindingDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\FullDemo\FullDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\MicroserviceClientDemo\MicroserviceClientDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\MultiLanguageDemo\MultiLanguageDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\MVVMDemo\MVVMDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\Phase0Demo\Phase0Demo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },

  # ------ G11 Demos (Production_Mode) ------
  @{ path='D:\_Progs\02Business\DeepBase\Examples\Phase1Demo\Phase1Demo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\Templates\CRUDApp\CRUDApp.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\Templates\DataAnalyzer\DataAnalyzer.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\Templates\DocManager\DocManager.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  @{ path='D:\_Progs\02Business\DeepBase\Examples\VCLDeepShellDemo\VCLDeepShellDemo.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandler;' },
  # FMXPlatformDemo.dpr — SKIPPED (FMX入口)

  # ------ G13 Tests (Test_Mode, InstallAIErrorHandlerForTests) ------
  # DeepBaseTests.dpr already has Bootstrap in uses (via colleague's commit 1bc8f30); only add call.
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DeepBaseTests.dpr'
     usesAnchor=''; usesLine=''
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\InferenceTests.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\MinimalDUnitX.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\SimpleTest.dpr'
     usesAnchor='  System.SysUtils;'; usesLine='  DeepBase.AIErrorHandler.Bootstrap;'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\TestLLMClient.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\TestLLMProxyClient.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\TestNewModules.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  # _tmp_DeepShellTestSolo.dpr — SKIPPED (file does not exist on disk; only .exe/.res/.rsm artifacts left)

  # ------ G14 DebugTests (all Console, Test_Mode) ------
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest2.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest3.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest4.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest5.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\DebugTest6.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },

  # ------ G15 Tests (Test_Mode) ------
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Acceptance\DeepBaseAcceptanceTest.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Architecture\DeepBaseArchitectureTests.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Governance\ConfigRegistrarPBT.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\GUI\DeepBaseGUITests.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\GUI\PageDriverSmoke.dpr'
     usesAnchor='  Vcl.Forms,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Integration\DeepBaseIntegrationTests.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },

  # ------ G16part Tests (Speech / Stress, Test_Mode) ------
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Speech\SpeechSpike.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Speech\TestSpeechHeadless.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' },
  @{ path='D:\_Progs\02Business\DeepBase\Tests\Stress\DeepBaseStressTests.dpr'
     usesAnchor='  System.SysUtils,'; usesLine='  DeepBase.AIErrorHandler.Bootstrap,'
     callAnchor='begin'; callLine='  InstallAIErrorHandlerForTests;' }
)

$results = @()
foreach ($j in $jobs) {
  $name = Split-Path -Leaf $j.path
  $result = [PSCustomObject]@{
    Name = $name; Path = $j.path; UsesOk = $true; CallOk = $false; Error = ''
  }
  try {
    if ($j.usesAnchor -ne '') {
      & $InjectScript -Path $j.path -AnchorAfter $j.usesAnchor -Insert $j.usesLine | Out-Null
    } else {
      $result.UsesOk = 'skip'
    }
    & $InjectScript -Path $j.path -AnchorAfter $j.callAnchor -Insert $j.callLine | Out-Null
    $result.CallOk = $true
  } catch {
    $result.Error = $_.Exception.Message
  }
  $results += $result
  $callIcon = if ($result.CallOk) { 'OK' } else { 'FAIL' }
  Write-Output ("{0,-50} uses={1,-4} call={2}" -f $name, $result.UsesOk, $callIcon)
  if ($result.Error) { Write-Output ('  ERR: ' + $result.Error) }
}

$results | ConvertTo-Json | Set-Content 'D:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_remaining_compile\inject_results.json' -Encoding UTF8
