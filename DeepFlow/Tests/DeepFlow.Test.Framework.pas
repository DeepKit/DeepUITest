{ ============================================================================
  UniFlow.Test.Framework - Lightweight Test Framework

  Version: 1.0
  Description: Simple test framework for UniFlow unit and integration tests

  Usage:
    TMyTest = class(TTestCase)
    published
      procedure TestSomething;
    end;

    procedure TMyTest.TestSomething;
    begin
      AssertEquals(1 + 1, 2, 'Basic math');
      AssertTrue(True, 'Should be true');
    end;

    // Run tests
    var Runner := TTestRunner.Create;
    Runner.AddTest(TMyTest);
    Runner.RunAll;
  ============================================================================ }

unit UniFlow.Test.Framework;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  System.JSON,
  System.Diagnostics;

type
  /// <summary>
  /// Test result status
  /// </summary>
  TTestStatus = (tsPassed, tsFailed, tsSkipped, tsError);

  /// <summary>
  /// Single test result
  /// </summary>
  TTestResult = record
    TestName: string;
    ClassName: string;
    Status: TTestStatus;
    Message: string;
    DurationMs: Int64;
    StackTrace: string;

    function StatusStr: string;
  end;

  /// <summary>
  /// Test suite results
  /// </summary>
  TTestSuiteResult = record
    TotalTests: Integer;
    Passed: Integer;
    Failed: Integer;
    Skipped: Integer;
    Errors: Integer;
    TotalDurationMs: Int64;
    Results: TArray<TTestResult>;

    procedure AddResult(const R: TTestResult);
    function GetSummary: string;
    function ToJSON: TJSONObject;
  end;

  /// <summary>
  /// Test assertion exception
  /// </summary>
  ETestAssertionFailed = class(Exception);
  ETestSkipped = class(Exception);

  /// <summary>
  /// Base test case class
  /// </summary>
  TTestCase = class
  private
    FCurrentTestName: string;
  protected
    procedure SetUp; virtual;
    procedure TearDown; virtual;

    // Assertions
    procedure AssertTrue(Condition: Boolean; const Msg: string = '');
    procedure AssertFalse(Condition: Boolean; const Msg: string = '');
    procedure AssertEquals(Expected, Actual: Integer; const Msg: string = ''); overload;
    procedure AssertEquals(Expected, Actual: Int64; const Msg: string = ''); overload;
    procedure AssertEquals(const Expected, Actual: string; const Msg: string = ''); overload;
    procedure AssertEquals(Expected, Actual: Double; Epsilon: Double = 0.0001; const Msg: string = ''); overload;
    procedure AssertNotEquals(Expected, Actual: Integer; const Msg: string = ''); overload;
    procedure AssertNotEquals(const Expected, Actual: string; const Msg: string = ''); overload;
    procedure AssertNull(Obj: TObject; const Msg: string = '');
    procedure AssertNotNull(Obj: TObject; const Msg: string = '');
    procedure AssertContains(const SubStr, Str: string; const Msg: string = '');
    procedure AssertStartsWith(const Prefix, Str: string; const Msg: string = '');
    procedure AssertEndsWith(const Suffix, Str: string; const Msg: string = '');
    procedure AssertRaises(ExceptionClass: ExceptClass; Proc: TProc; const Msg: string = '');
    procedure AssertNoRaise(Proc: TProc; const Msg: string = '');
    procedure AssertGreaterThan(Value, Threshold: Integer; const Msg: string = '');
    procedure AssertLessThan(Value, Threshold: Integer; const Msg: string = '');
    procedure Fail(const Msg: string);
    procedure Skip(const Msg: string);
  public
    property CurrentTestName: string read FCurrentTestName;
  end;

  TTestCaseClass = class of TTestCase;

  /// <summary>
  /// Test runner
  /// </summary>
  TTestRunner = class
  private
    FTestClasses: TList<TTestCaseClass>;
    FResults: TTestSuiteResult;
    FVerbose: Boolean;
    FStopOnFirstFailure: Boolean;

    procedure Log(const Msg: string);
    function RunTestMethod(TestCase: TTestCase; const MethodName: string): TTestResult;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddTest(TestClass: TTestCaseClass);
    procedure AddTests(const TestClasses: array of TTestCaseClass);
    function RunAll: TTestSuiteResult;
    function RunSingle(TestClass: TTestCaseClass; const MethodName: string): TTestResult;
    procedure Clear;

    property Verbose: Boolean read FVerbose write FVerbose;
    property StopOnFirstFailure: Boolean read FStopOnFirstFailure write FStopOnFirstFailure;
    property Results: TTestSuiteResult read FResults;
  end;

function StatusToString(Status: TTestStatus): string;

implementation

function StatusToString(Status: TTestStatus): string;
begin
  case Status of
    tsPassed: Result := 'PASS';
    tsFailed: Result := 'FAIL';
    tsSkipped: Result := 'SKIP';
    tsError: Result := 'ERROR';
  else
    Result := 'UNKNOWN';
  end;
end;

{ TTestResult }

function TTestResult.StatusStr: string;
begin
  Result := StatusToString(Status);
end;

{ TTestSuiteResult }

procedure TTestSuiteResult.AddResult(const R: TTestResult);
begin
  SetLength(Results, Length(Results) + 1);
  Results[High(Results)] := R;
  Inc(TotalTests);
  TotalDurationMs := TotalDurationMs + R.DurationMs;

  case R.Status of
    tsPassed: Inc(Passed);
    tsFailed: Inc(Failed);
    tsSkipped: Inc(Skipped);
    tsError: Inc(Errors);
  end;
end;

function TTestSuiteResult.GetSummary: string;
begin
  Result := Format('Tests: %d | Passed: %d | Failed: %d | Skipped: %d | Errors: %d | Time: %dms',
    [TotalTests, Passed, Failed, Skipped, Errors, TotalDurationMs]);
end;

function TTestSuiteResult.ToJSON: TJSONObject;
var
  ResultsArray: TJSONArray;
  R: TTestResult;
  RObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('total', TotalTests);
  Result.AddPair('passed', Passed);
  Result.AddPair('failed', Failed);
  Result.AddPair('skipped', Skipped);
  Result.AddPair('errors', Errors);
  Result.AddPair('duration_ms', TotalDurationMs);

  ResultsArray := TJSONArray.Create;
  for R in Results do
  begin
    RObj := TJSONObject.Create;
    RObj.AddPair('name', R.TestName);
    RObj.AddPair('class', R.ClassName);
    RObj.AddPair('status', R.StatusStr);
    RObj.AddPair('duration_ms', R.DurationMs);
    if not R.Message.IsEmpty then
      RObj.AddPair('message', R.Message);
    ResultsArray.Add(RObj);
  end;
  Result.AddPair('results', ResultsArray);
end;

{ TTestCase }

procedure TTestCase.SetUp;
begin
  // Override in subclass
end;

procedure TTestCase.TearDown;
begin
  // Override in subclass
end;

procedure TTestCase.AssertTrue(Condition: Boolean; const Msg: string);
begin
  if not Condition then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.Create('Expected True but got False')
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertFalse(Condition: Boolean; const Msg: string);
begin
  if Condition then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.Create('Expected False but got True')
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertEquals(Expected, Actual: Integer; const Msg: string);
begin
  if Expected <> Actual then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected %d but got %d', [Expected, Actual])
    else
      raise ETestAssertionFailed.CreateFmt('%s (Expected %d, got %d)', [Msg, Expected, Actual]);
  end;
end;

procedure TTestCase.AssertEquals(Expected, Actual: Int64; const Msg: string);
begin
  if Expected <> Actual then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected %d but got %d', [Expected, Actual])
    else
      raise ETestAssertionFailed.CreateFmt('%s (Expected %d, got %d)', [Msg, Expected, Actual]);
  end;
end;

procedure TTestCase.AssertEquals(const Expected, Actual: string; const Msg: string);
begin
  if Expected <> Actual then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected "%s" but got "%s"', [Expected, Actual])
    else
      raise ETestAssertionFailed.CreateFmt('%s (Expected "%s", got "%s")', [Msg, Expected, Actual]);
  end;
end;

procedure TTestCase.AssertEquals(Expected, Actual: Double; Epsilon: Double; const Msg: string);
begin
  if Abs(Expected - Actual) > Epsilon then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected %.4f but got %.4f', [Expected, Actual])
    else
      raise ETestAssertionFailed.CreateFmt('%s (Expected %.4f, got %.4f)', [Msg, Expected, Actual]);
  end;
end;

procedure TTestCase.AssertNotEquals(Expected, Actual: Integer; const Msg: string);
begin
  if Expected = Actual then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected value different from %d', [Actual])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertNotEquals(const Expected, Actual: string; const Msg: string);
begin
  if Expected = Actual then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected value different from "%s"', [Actual])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertNull(Obj: TObject; const Msg: string);
begin
  if Assigned(Obj) then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.Create('Expected nil but got object')
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertNotNull(Obj: TObject; const Msg: string);
begin
  if not Assigned(Obj) then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.Create('Expected object but got nil')
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertContains(const SubStr, Str: string; const Msg: string);
begin
  if not Str.Contains(SubStr) then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('"%s" does not contain "%s"', [Str, SubStr])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertStartsWith(const Prefix, Str: string; const Msg: string);
begin
  if not Str.StartsWith(Prefix) then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('"%s" does not start with "%s"', [Str, Prefix])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertEndsWith(const Suffix, Str: string; const Msg: string);
begin
  if not Str.EndsWith(Suffix) then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('"%s" does not end with "%s"', [Str, Suffix])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertRaises(ExceptionClass: ExceptClass; Proc: TProc; const Msg: string);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    Proc;
  except
    on E: Exception do
    begin
      if E is ExceptionClass then
        Raised := True
      else
        raise ETestAssertionFailed.CreateFmt('Expected %s but got %s: %s',
          [ExceptionClass.ClassName, E.ClassName, E.Message]);
    end;
  end;

  if not Raised then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected exception %s but none raised', [ExceptionClass.ClassName])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertNoRaise(Proc: TProc; const Msg: string);
begin
  try
    Proc;
  except
    on E: Exception do
    begin
      if Msg.IsEmpty then
        raise ETestAssertionFailed.CreateFmt('Unexpected exception: %s', [E.Message])
      else
        raise ETestAssertionFailed.CreateFmt('%s: %s', [Msg, E.Message]);
    end;
  end;
end;

procedure TTestCase.AssertGreaterThan(Value, Threshold: Integer; const Msg: string);
begin
  if Value <= Threshold then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected %d > %d', [Value, Threshold])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.AssertLessThan(Value, Threshold: Integer; const Msg: string);
begin
  if Value >= Threshold then
  begin
    if Msg.IsEmpty then
      raise ETestAssertionFailed.CreateFmt('Expected %d < %d', [Value, Threshold])
    else
      raise ETestAssertionFailed.Create(Msg);
  end;
end;

procedure TTestCase.Fail(const Msg: string);
begin
  raise ETestAssertionFailed.Create(Msg);
end;

procedure TTestCase.Skip(const Msg: string);
begin
  raise ETestSkipped.Create(Msg);
end;

{ TTestRunner }

constructor TTestRunner.Create;
begin
  inherited;
  FTestClasses := TList<TTestCaseClass>.Create;
  FVerbose := True;
  FStopOnFirstFailure := False;
end;

destructor TTestRunner.Destroy;
begin
  FTestClasses.Free;
  inherited;
end;

procedure TTestRunner.Log(const Msg: string);
begin
  if FVerbose then
    Writeln(Msg);
end;

procedure TTestRunner.AddTest(TestClass: TTestCaseClass);
begin
  FTestClasses.Add(TestClass);
end;

procedure TTestRunner.AddTests(const TestClasses: array of TTestCaseClass);
var
  TC: TTestCaseClass;
begin
  for TC in TestClasses do
    AddTest(TC);
end;

procedure TTestRunner.Clear;
begin
  FTestClasses.Clear;
  FResults := Default(TTestSuiteResult);
end;

function TTestRunner.RunTestMethod(TestCase: TTestCase; const MethodName: string): TTestResult;
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Method: TRttiMethod;
  Stopwatch: TStopwatch;
begin
  Result.TestName := MethodName;
  Result.ClassName := TestCase.ClassName;
  Result.Status := tsPassed;
  Result.Message := '';
  Result.StackTrace := '';

  Stopwatch := TStopwatch.StartNew;
  try
    TestCase.FCurrentTestName := MethodName;
    TestCase.SetUp;
    try
      RttiContext := TRttiContext.Create;
      try
        RttiType := RttiContext.GetType(TestCase.ClassType);
        Method := RttiType.GetMethod(MethodName);
        if Assigned(Method) then
          Method.Invoke(TestCase, []);
      finally
        RttiContext.Free;
      end;
    finally
      TestCase.TearDown;
    end;
  except
    on E: ETestSkipped do
    begin
      Result.Status := tsSkipped;
      Result.Message := E.Message;
    end;
    on E: ETestAssertionFailed do
    begin
      Result.Status := tsFailed;
      Result.Message := E.Message;
    end;
    on E: Exception do
    begin
      Result.Status := tsError;
      Result.Message := E.ClassName + ': ' + E.Message;
    end;
  end;
  Stopwatch.Stop;
  Result.DurationMs := Stopwatch.ElapsedMilliseconds;
end;

function TTestRunner.RunAll: TTestSuiteResult;
var
  TestClass: TTestCaseClass;
  TestCase: TTestCase;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Method: TRttiMethod;
  TestResult: TTestResult;
begin
  FResults := Default(TTestSuiteResult);
  Log('');
  Log('==================== UniFlow Test Suite ====================');
  Log('');

  for TestClass in FTestClasses do
  begin
    Log('--- ' + TestClass.ClassName + ' ---');
    TestCase := TestClass.Create;
    try
      RttiContext := TRttiContext.Create;
      try
        RttiType := RttiContext.GetType(TestClass);
        for Method in RttiType.GetMethods do
        begin
          // Run methods starting with 'Test'
          if Method.Visibility = mvPublished then
          begin
            if Method.Name.StartsWith('Test') then
            begin
              TestResult := RunTestMethod(TestCase, Method.Name);
              FResults.AddResult(TestResult);

              case TestResult.Status of
                tsPassed: Log('  [PASS] ' + TestResult.TestName);
                tsFailed: Log('  [FAIL] ' + TestResult.TestName + ' - ' + TestResult.Message);
                tsSkipped: Log('  [SKIP] ' + TestResult.TestName + ' - ' + TestResult.Message);
                tsError: Log('  [ERR!] ' + TestResult.TestName + ' - ' + TestResult.Message);
              end;

              if FStopOnFirstFailure and (TestResult.Status in [tsFailed, tsError]) then
              begin
                Log('');
                Log('Stopped on first failure.');
                Break;
              end;
            end;
          end;
        end;
      finally
        RttiContext.Free;
      end;
    finally
      TestCase.Free;
    end;
    Log('');

    if FStopOnFirstFailure and (FResults.Failed > 0) then
      Break;
  end;

  Log('============================================================');
  Log(FResults.GetSummary);
  Log('============================================================');

  Result := FResults;
end;

function TTestRunner.RunSingle(TestClass: TTestCaseClass; const MethodName: string): TTestResult;
var
  TestCase: TTestCase;
begin
  TestCase := TestClass.Create;
  try
    Result := RunTestMethod(TestCase, MethodName);
  finally
    TestCase.Free;
  end;
end;

end.
