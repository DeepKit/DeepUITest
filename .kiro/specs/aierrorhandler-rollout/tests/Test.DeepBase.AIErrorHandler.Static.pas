{ ============================================================================
  Test.DeepBase.AIErrorHandler.Static

  Property-based tests for spec aierrorhandler-rollout, stage 3 (3.7).

  Properties covered:
    Property 6  (R 1.4, 3.4): Bootstrap 静态约束
                  - interface uses 段不出现 Vcl.Dialogs / Vcl.Controls /
                    FMX.Dialogs / FMX.Controls
                  - implementation 段中不出现对 System.ExceptProc 的赋值

  100 轮独立读源文件并扫描 (每轮可独立失败/成功)。

  备注: 这是纯静态字符串扫描测试,不依赖 Bootstrap 单元的运行时 (但仍 uses
  Bootstrap 是否 RTTI 注册 fixture 不依赖)。
  ============================================================================ }

unit Test.DeepBase.AIErrorHandler.Static;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAIErrorHandlerStaticTests = class
  private
    function ReadBootstrapSource: string;
    function ExtractInterfaceSection(const ASrc: string): string;
    function ExtractImplementationSection(const ASrc: string): string;
  public
    // Feature: aierrorhandler-rollout, Property 6: Bootstrap 静态约束
    [Test]
    procedure Property6_BootstrapStaticConstraints;
  end;

implementation

const
  CSourceCandidates: array[0..1] of string = (
    'd:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.Bootstrap.pas',
    'D:\_Progs\02Business\DeepBase\Core\DeepBase.AIErrorHandler.Bootstrap.pas'
  );

  CForbiddenInterfaceUses: array[0..3] of string = (
    'Vcl.Dialogs',
    'Vcl.Controls',
    'FMX.Dialogs',
    'FMX.Controls'
  );

  // 任何 ExceptProc 赋值的形式都禁止 (System.ExceptProc, ExceptProc 直接引用)
  CForbiddenAssignment: array[0..1] of string = (
    'System.ExceptProc',
    'ExceptProc'
  );

{ TAIErrorHandlerStaticTests }

function TAIErrorHandlerStaticTests.ReadBootstrapSource: string;
var
  P: string;
begin
  for P in CSourceCandidates do
    if TFile.Exists(P) then
      Exit(TFile.ReadAllText(P, TEncoding.UTF8));
  Result := '';
  Assert.Fail('Bootstrap.pas not found at any expected location');
end;

function TAIErrorHandlerStaticTests.ExtractInterfaceSection(
  const ASrc: string): string;
var
  LIfaceIdx, LImplIdx: Integer;
begin
  // interface 关键字到 implementation 关键字之间
  LIfaceIdx := Pos('interface', LowerCase(ASrc));
  LImplIdx := Pos('implementation', LowerCase(ASrc));
  if (LIfaceIdx <= 0) or (LImplIdx <= LIfaceIdx) then
    Result := ''
  else
    Result := Copy(ASrc, LIfaceIdx, LImplIdx - LIfaceIdx);
end;

function TAIErrorHandlerStaticTests.ExtractImplementationSection(
  const ASrc: string): string;
var
  LImplIdx, LEndIdx: Integer;
begin
  LImplIdx := Pos('implementation', LowerCase(ASrc));
  // 'end.' 标志单元结束
  LEndIdx := Pos('end.', LowerCase(ASrc));
  if (LImplIdx <= 0) then
    Exit('');
  if (LEndIdx <= LImplIdx) then
    Result := Copy(ASrc, LImplIdx, MaxInt)
  else
    Result := Copy(ASrc, LImplIdx, LEndIdx - LImplIdx + 4);
end;

// ----------------------------------------------------------------------------
// Property 6: Bootstrap 静态约束
// 100 轮独立扫描;每轮:
//   (a) 读 Bootstrap.pas 全文
//   (b) 提取 interface 段 -> 不含禁用 unit 名
//   (c) 提取 implementation 段 -> 不含 ExceptProc 赋值 (:=)
// ----------------------------------------------------------------------------
procedure TAIErrorHandlerStaticTests.Property6_BootstrapStaticConstraints;
const
  CIterations = 100;
var
  LSrc, LIface, LImpl: string;
  LForbidden: string;
  LAssignment: string;
  LMatch: Boolean;
begin
  for var I := 1 to CIterations do
  begin
    LSrc := ReadBootstrapSource;
    Assert.IsTrue(LSrc.Length > 0,
      Format('Iter %d: Bootstrap.pas 读取应非空', [I]));

    LIface := ExtractInterfaceSection(LSrc);
    LImpl  := ExtractImplementationSection(LSrc);
    Assert.IsTrue(LIface.Length > 0,
      Format('Iter %d: Bootstrap.pas 必须含 interface 段', [I]));
    Assert.IsTrue(LImpl.Length > 0,
      Format('Iter %d: Bootstrap.pas 必须含 implementation 段', [I]));

    // (b) interface 段禁用 unit 名 (大小写不敏感全字匹配)
    for LForbidden in CForbiddenInterfaceUses do
    begin
      LMatch := TRegEx.IsMatch(LIface, '\b' +
        TRegEx.Escape(LForbidden) + '\b',
        [TRegExOption.roIgnoreCase]);
      Assert.IsFalse(LMatch,
        Format('Iter %d: interface uses 段禁止出现 "%s"',
          [I, LForbidden]));
    end;

    // (c) implementation 段禁止 ExceptProc 赋值
    //     允许出现在注释中的字面引用,但禁止 := 赋值
    for LAssignment in CForbiddenAssignment do
    begin
      // 匹配类似 "ExceptProc :=" 或 "System.ExceptProc :=" 形式
      LMatch := TRegEx.IsMatch(LImpl,
        '\b' + TRegEx.Escape(LAssignment) + '\s*:=',
        [TRegExOption.roIgnoreCase]);
      Assert.IsFalse(LMatch,
        Format('Iter %d: implementation 段禁止对 "%s" 赋值',
          [I, LAssignment]));
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAIErrorHandlerStaticTests);

end.
