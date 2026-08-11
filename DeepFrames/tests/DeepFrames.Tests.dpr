program DeepFrames.Tests;

/// <summary>
/// DeepFrames unit test runner.
/// Compile: dcc64 -B -Q -U"..\src\App;..\src\Domain;..\src\Persistence;..\src\Workflow;..\src\Shared;..\src\Provider" DeepFrames.Tests.dpr
/// Run: DeepFrames.Tests.exe
/// </summary>

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  DeepFrames.Tests.Core in 'DeepFrames.Tests.Core.pas',
  DeepFrames.Tests.Integration in 'DeepFrames.Tests.Integration.pas',
  DeepFrames.Tests.RealIntegration in 'DeepFrames.Tests.RealIntegration.pas';

type
  PEXCEPTION_RECORD = ^TExceptionRecord;
  TExceptionRecord = packed record
    ExceptionCode: Cardinal;
    ExceptionFlags: Cardinal;
    ExceptionRecord: PEXCEPTION_RECORD;
    ExceptionAddress: Pointer;
    NumberParameters: Cardinal;
    ExceptionInformation: array[0..14] of Pointer;
  end;
  PEXCEPTION_POINTERS = ^TExceptionPointers;
  TExceptionPointers = packed record
    ExceptionRecord: PEXCEPTION_RECORD;
    ContextRecord: Pointer;
  end;
  TVectoredHandler = function(ExceptionInfo: Pointer): LongBool; stdcall;

function AddVectoredExceptionHandler(FirstHandler: Cardinal;
  Handler: TVectoredHandler): Pointer; stdcall; external 'kernel32';

function RtlCaptureStackBackTrace(FramesToSkip, FramesToCapture: Cardinal;
  BackTrace: PPointer; BackTraceHash: PCardinal): Word; stdcall; external 'kernel32';

var
  GLogged: Boolean = False;

function CrashVectoredHandler(ExceptionInfo: Pointer): LongBool; stdcall;
const
  EXCEPTION_ACCESS_VIOLATION = $C0000005;
type
  TContextAmd64 = packed record
    P1Home, P2Home, P3Home, P4Home, P5Home, P6Home: UInt64;
    ContextFlags: Cardinal;
    MxCsr: Cardinal;
    SegCs: Word; SegDs: Word; SegEs: Word; SegFs: Word; SegGs: Word; SegSs: Word;
    EFlags: Cardinal;
    Dr0, Dr1, Dr2, Dr3, Dr6, Dr7: UInt64;
    Rax, Rcx, Rdx, Rbx, Rsp, Rbp, Rsi, Rdi: UInt64;
    R8, R9, R10, R11, R12, R13, R14, R15: UInt64;
    Rip: UInt64;
  end;
  PContextAmd64 = ^TContextAmd64;
var
  EP: PEXCEPTION_POINTERS;
  Addr: Pointer;
  Base: UInt64;
  Rva: UInt64;
  Ctx: PContextAmd64;
  Sp, ScanEnd, V: UInt64;
  P: ^UInt64;
  Hits, I: Integer;
  Hbuf: array[0..17] of AnsiChar; // 16 hex digits + CRLF + nul
  Hdst: PAnsiChar;
  StdOut: THandle;
  Written: Cardinal;
const
  Hxd: array[0..15] of AnsiChar = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
  procedure EmitHex(Tag: PAnsiChar; Value: UInt64);
  var
    T: array[0..31] of AnsiChar;
    N, J: Integer;
  begin
    // Write "<TAG>XXXXXXXX\r\n" directly to the console handle — no heap,
    // no RTL string manager, so it survives a corrupted heap at finalization.
    N := 0;
    while Tag^ <> #0 do begin T[N] := Tag^; Inc(N); Inc(Tag); end;
    for J := 15 downto 0 do
    begin
      T[N] := Hxd[(Value shr (J*4)) and $F];
      Inc(N);
    end;
    T[N] := #13; Inc(N); T[N] := #10; Inc(N);
    WriteFile(StdOut, T[0], N, Written, nil);
  end;
begin
  Result := False;
  try
    EP := PEXCEPTION_POINTERS(ExceptionInfo);
    if (EP <> nil) and (EP.ExceptionRecord <> nil) and (not GLogged) then
    begin
      if EP.ExceptionRecord^.ExceptionCode = EXCEPTION_ACCESS_VIOLATION then
      begin
        GLogged := True;
        StdOut := GetStdHandle(STD_OUTPUT_HANDLE);
        Addr := EP.ExceptionRecord^.ExceptionAddress;
        Base := UInt64(GetModuleHandle(nil));
        Rva := UInt64(Addr) - Base;
        EmitHex('AV rva=', Rva);
        Ctx := PContextAmd64(EP.ContextRecord);
        if Ctx <> nil then
        begin
          Sp := Ctx^.Rsp;
          EmitHex('rsp=', Sp);
          ScanEnd := Sp + $4000;
          P := Pointer(Sp);
          Hits := 0;
          while (UInt64(P) < ScanEnd) and (Hits < 32) do
          begin
            try
              V := P^;
              if (V > Base + $1000) and (V < Base + $6915F8) then
              begin
                EmitHex('ret ', V - Base);
                Inc(Hits);
              end;
            except
            end;
            P := Pointer(UInt64(P) + SizeOf(UInt64));
          end;
        end;
        EmitHex('end', 0);
      end;
    end;
  except
  end;
end;

begin
  AddVectoredExceptionHandler(1, @CrashVectoredHandler);
  WriteLn('All tests complete.');
end.
