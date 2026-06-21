unit DeepRKey.IPC.Pipe;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepRKey.HookShared;

type
  EPipeError = class(Exception);

  TPipeFrame = record
    Header: TPipeFrameHeader;
    Data: TBytes;
    function ToBytes: TBytes;
    class function FromBytes(const Buf: TBytes; var Offset: Integer;
      out Frame: TPipeFrame): Boolean; static;
  end;

  TPipeFrameHandler = reference to procedure(const Frame: TPipeFrame);

  TRKeyPipeClient = class
  private
    FPipeHandle: THandle;
    FPipeName: string;
    FGUID: string;
    FMessageId: Integer;
    function NextMessageId: UInt32;
  public
    constructor Create(const AGUID: string);
    destructor Destroy; override;
    function Connect(TimeoutMs: UInt32 = 5000): Boolean;
    procedure Disconnect;
    function SendFrame(const Command: TPipeCommand; const Data: TBytes): Boolean;
    function ReceiveFrame(out Frame: TPipeFrame; TimeoutMs: UInt32 = 1000): Boolean;
    function IsConnected: Boolean;
    property PipeName: string read FPipeName;
    property GUID: string read FGUID;
  end;

  TRKeyPipeServer = class
  private
    FPipeHandle: THandle;
    FPipeName: string;
    FRunning: Boolean;
    FOnFrameReceived: TPipeFrameHandler;
    FThread: TThread;
    procedure ClientThread;
  public
    constructor Create(const AGUID: string);
    destructor Destroy; override;
    procedure Start(const AOnFrame: TPipeFrameHandler);
    procedure Stop;
    function SendFrame(const Frame: TPipeFrame): Boolean;
    property PipeName: string read FPipeName;
    property Running: Boolean read FRunning;
  end;

implementation

{ TPipeFrame }

function TPipeFrame.ToBytes: TBytes;
var
  totalLen: Integer;
begin
  totalLen := SizeOf(TPipeFrameHeader) + Length(Data);
  SetLength(Result, totalLen);
  if totalLen > 0 then
  begin
    Move(Header, Result[0], SizeOf(TPipeFrameHeader));
    if Length(Data) > 0 then
      Move(Data[0], Result[SizeOf(TPipeFrameHeader)], Length(Data));
  end;
end;

class function TPipeFrame.FromBytes(const Buf: TBytes; var Offset: Integer;
  out Frame: TPipeFrame): Boolean;
var
  dataLen: Integer;
  computedCrc: UInt32;
begin
  Result := False;
  if Length(Buf) - Offset < SizeOf(TPipeFrameHeader) then
    Exit;

  Move(Buf[Offset], Frame.Header, SizeOf(TPipeFrameHeader));

  // T-448: 验证 Magic
  if Frame.Header.Magic <> RK_PIPE_MAGIC then
    Exit;

  // T-448: 验证 FrameLength 合理性（最小为 header 大小，最大为 header + 64KB）
  if (Frame.Header.FrameLength < SizeOf(TPipeFrameHeader)) or
     (Frame.Header.FrameLength > SizeOf(TPipeFrameHeader) + 65536) then
    Exit;

  // T-448: 验证 Command 范围（0..pcInstallGlobalHook）
  if Frame.Header.Command > Ord(High(TPipeCommand)) then
    Exit;

  // T-448: 验证 CRC32（排除 Crc32 字段本身和 _Padding 字段）
  // Header 结构: Magic(4) + FrameLength(4) + MessageId(4) + Sequence(8) + Command(4) + Crc32(4) + _Padding(4) = 32
  // CRC 计算范围: 前 24 字节（Magic 到 Command）
  computedCrc := ComputeCRC32(Frame.Header, SizeOf(TPipeFrameHeader) - 8);  // 排除 Crc32(4) + _Padding(4)
  if computedCrc <> Frame.Header.Crc32 then
    Exit;

  Inc(Offset, SizeOf(TPipeFrameHeader));

  dataLen := Integer(Frame.Header.FrameLength) - SizeOf(TPipeFrameHeader);
  if dataLen < 0 then
    dataLen := 0;

  if Length(Buf) - Offset < dataLen then
  begin
    Dec(Offset, SizeOf(TPipeFrameHeader));
    Exit;
  end;

  if dataLen > 0 then
  begin
    SetLength(Frame.Data, dataLen);
    Move(Buf[Offset], Frame.Data[0], dataLen);
    Inc(Offset, dataLen);
  end;

  Result := True;
end;

{ TRKeyPipeClient }

constructor TRKeyPipeClient.Create(const AGUID: string);
begin
  FGUID := AGUID;
  FPipeName := Format('%s%s', [RK_PIPE_PREFIX, AGUID]);
  FPipeHandle := INVALID_HANDLE_VALUE;
  FMessageId := 0;
end;

destructor TRKeyPipeClient.Destroy;
begin
  Disconnect;
  inherited;
end;

function TRKeyPipeClient.NextMessageId: UInt32;
begin
  Result := UInt32(InterlockedIncrement(FMessageId));
end;

function TRKeyPipeClient.Connect(TimeoutMs: UInt32): Boolean;
begin
  if FPipeHandle <> INVALID_HANDLE_VALUE then
    Exit(True);

  FPipeHandle := CreateFile(PChar(FPipeName), GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_EXISTING, 0, 0);

  if FPipeHandle = INVALID_HANDLE_VALUE then
  begin
    if not WaitNamedPipe(PChar(FPipeName), TimeoutMs) then
      Exit(False);
    FPipeHandle := CreateFile(PChar(FPipeName), GENERIC_READ or GENERIC_WRITE,
      0, nil, OPEN_EXISTING, 0, 0);
  end;

  Result := FPipeHandle <> INVALID_HANDLE_VALUE;
end;

procedure TRKeyPipeClient.Disconnect;
begin
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
end;

function TRKeyPipeClient.IsConnected: Boolean;
begin
  Result := FPipeHandle <> INVALID_HANDLE_VALUE;
end;

function TRKeyPipeClient.SendFrame(const Command: TPipeCommand;
  const Data: TBytes): Boolean;
var
  frame: TPipeFrame;
  frameLen: UInt32;
  bytes: TBytes;
  written: DWORD;
begin
  Result := False;
  if not IsConnected then
    Exit;

  FillChar(frame.Header, SizeOf(TPipeFrameHeader), 0);
  frame.Header.Magic := RK_PIPE_MAGIC;
  frame.Header.MessageId := NextMessageId;
  frame.Header.Sequence := 0;
  frame.Header.Command := UInt32(Command);
  frame.Data := Data;

  frameLen := SizeOf(TPipeFrameHeader) + UInt32(Length(Data));
  frame.Header.FrameLength := frameLen;

  // T-448: CRC32 计算排除 Crc32 字段本身和 _Padding 字段（前 24 字节）
  // Header 结构: Magic(4) + FrameLength(4) + MessageId(4) + Sequence(8) + Command(4) + Crc32(4) + _Padding(4) = 32
  frame.Header.Crc32 := ComputeCRC32(frame.Header, SizeOf(TPipeFrameHeader) - 8);

  bytes := frame.ToBytes;
  Result := WriteFile(FPipeHandle, bytes[0], Length(bytes), written, nil);
end;

function TRKeyPipeClient.ReceiveFrame(out Frame: TPipeFrame;
  TimeoutMs: UInt32): Boolean;
var
  buf: TBytes;
  bytesRead: DWORD;
  bytesAvailable: DWORD;
  offset: Integer;
  startTime: DWORD;
  elapsed: DWORD;
begin
  Result := False;
  if not IsConnected then
    Exit;

  // T-448: 实现实际超时（使用 PeekNamedPipe 检查数据可用性）
  startTime := GetTickCount;

  // 等待数据可用或超时
  while True do
  begin
    elapsed := GetTickCount - startTime;
    if elapsed >= TimeoutMs then
      Exit;  // 超时

    // 检查是否有数据可读
    if not PeekNamedPipe(FPipeHandle, nil, 0, nil, @bytesAvailable, nil) then
      Exit;  // 管道错误

    if bytesAvailable >= SizeOf(TPipeFrameHeader) then
      Break;  // 有足够数据读取 header

    // 短暂等待后重试
    Sleep(1);
  end;

  // 读取数据
  SetLength(buf, 4096);
  if not ReadFile(FPipeHandle, buf[0], Length(buf), bytesRead, nil) then
    Exit;

  if bytesRead < SizeOf(TPipeFrameHeader) then
    Exit;

  SetLength(buf, bytesRead);
  offset := 0;
  Result := TPipeFrame.FromBytes(buf, offset, Frame);
end;

{ TRKeyPipeServer }

constructor TRKeyPipeServer.Create(const AGUID: string);
begin
  FPipeName := Format('%s%s', [RK_PIPE_PREFIX, AGUID]);
  FPipeHandle := INVALID_HANDLE_VALUE;
  FRunning := False;
end;

destructor TRKeyPipeServer.Destroy;
begin
  Stop;
  inherited;
end;

procedure TRKeyPipeServer.Start(const AOnFrame: TPipeFrameHandler);
begin
  if FRunning then
    Exit;

  FOnFrameReceived := AOnFrame;
  FRunning := True;
  FThread := TThread.CreateAnonymousThread(ClientThread);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TRKeyPipeServer.Stop;
begin
  FRunning := False;
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
  if FThread <> nil then
  begin
    WaitForSingleObject(FThread.Handle, 2000);
    FreeAndNil(FThread);
  end;
end;

procedure TRKeyPipeServer.ClientThread;
var
  buf: array[0..8191] of Byte;
  bytesRead: DWORD;
  frameBytes: TBytes;
  frame: TPipeFrame;
  offset: Integer;
begin
  while FRunning do
  begin
    FPipeHandle := CreateNamedPipe(PChar(FPipeName),
      PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES,
      SizeOf(TPipeFrameHeader) + 4096,
      SizeOf(TPipeFrameHeader) + 4096,
      0, nil);

    if FPipeHandle = INVALID_HANDLE_VALUE then
    begin
      Sleep(100);
      Continue;
    end;

    if ConnectNamedPipe(FPipeHandle, nil) then
    begin
      while FRunning do
      begin
        if not ReadFile(FPipeHandle, buf, SizeOf(buf), bytesRead, nil) then
          Break;

        SetLength(frameBytes, bytesRead);
        Move(buf, frameBytes[0], bytesRead);

        offset := 0;
        if TPipeFrame.FromBytes(frameBytes, offset, frame) then
          if Assigned(FOnFrameReceived) then
            FOnFrameReceived(frame);
      end;
    end;

    DisconnectNamedPipe(FPipeHandle);
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;

    // T-010b: 防止紧密循环导致 CPU 高占用
    // Sleep(10) 防止 Pipe Server 空转，但不会严重影响 Helper32 重连
    Sleep(10);
  end;
end;

function TRKeyPipeServer.SendFrame(const Frame: TPipeFrame): Boolean;
var
  bytes: TBytes;
  written: DWORD;
  frameToSend: TPipeFrame;
begin
  Result := False;
  if FPipeHandle = INVALID_HANDLE_VALUE then
    Exit;

  // T-448: 确保 CRC32 已计算（如果为 0 则计算）
  frameToSend := Frame;
  if frameToSend.Header.Crc32 = 0 then
  begin
    // CRC32 计算排除 Crc32 字段本身和 _Padding 字段（前 24 字节）
    frameToSend.Header.Crc32 := ComputeCRC32(frameToSend.Header, SizeOf(TPipeFrameHeader) - 8);
  end;

  bytes := frameToSend.ToBytes;
  Result := WriteFile(FPipeHandle, bytes[0], Length(bytes), written, nil);
end;

end.