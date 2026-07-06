unit DeepAxis.Pipeline.SendQueue;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.DateUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Pipeline.Boundary;

type
  /// <summary>
  ///   发送队列项状态
  /// </summary>
  TSendStatus = (ssPending, ssPasting, ssSent, ssFailed, ssSkipped);

  /// <summary>
  ///   发送队列项
  /// </summary>
  TSendQueueItem = record
    ItemId: string;
    ContactId: string;
    ContactName: string;
    Script: string;
    BoundaryClass: TBoundaryClass;
    Status: TSendStatus;
    CreatedAt: TDateTime;
    SentAt: TDateTime;
    RetryCount: Integer;
    ErrorMessage: string;
  end;

  /// <summary>
  ///   发送队列。P0: 内存队列，不依赖 UIA。
  ///   P2+: 接入 UIA 引擎执行实际粘贴/发送。
  /// </summary>
  TSendQueue = class
  private
    FItems: TList<TSendQueueItem>;
    FLock: TObject;
    FMaxRetry: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>添加一条发送任务</summary>
    function Enqueue(const AContactId, AContactName, AScript: string;
      ABoundaryClass: TBoundaryClass): string;

    /// <summary>获取下一条待处理的任务</summary>
    function Dequeue: TSendQueueItem;

    /// <summary>标记任务状态</summary>
    procedure UpdateStatus(const AItemId: string; AStatus: TSendStatus;
      const AError: string = '');

    /// <summary>获取所有任务</summary>
    function GetAll: TArray<TSendQueueItem>;

    /// <summary>获取待处理任务数</summary>
    function GetPendingCount: Integer;

    /// <summary>获取已完成任务数</summary>
    function GetSentCount: Integer;

    /// <summary>获取失败任务数</summary>
    function GetFailedCount: Integer;

    /// <summary>获取统计摘要</summary>
    function GetSummary: string;

    /// <summary>清空队列</summary>
    procedure Clear;
  end;

implementation

{ TSendQueue }

constructor TSendQueue.Create;
begin
  inherited Create;
  FItems := TList<TSendQueueItem>.Create;
  FLock := TObject.Create;
  FMaxRetry := 3;
end;

destructor TSendQueue.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

function TSendQueue.Enqueue(const AContactId, AContactName, AScript: string;
  ABoundaryClass: TBoundaryClass): string;
var
  LItem: TSendQueueItem;
begin
  TMonitor.Enter(FLock);
  try
    LItem.ItemId := GenerateId;
    LItem.ContactId := AContactId;
    LItem.ContactName := AContactName;
    LItem.Script := AScript;
    LItem.BoundaryClass := ABoundaryClass;
    LItem.Status := ssPending;
    LItem.CreatedAt := Now;
    LItem.SentAt := 0;
    LItem.RetryCount := 0;
    LItem.ErrorMessage := '';
    FItems.Add(LItem);
    Result := LItem.ItemId;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.Dequeue: TSendQueueItem;
var
  I: Integer;
  LItem: TSendQueueItem;
begin
  TMonitor.Enter(FLock);
  try
    for I := 0 to FItems.Count - 1 do
      if FItems[I].Status = ssPending then
      begin
        LItem := FItems[I];
        LItem.Status := ssPasting;
        FItems[I] := LItem;
        Result := LItem;
        Exit;
      end;
    Result := Default(TSendQueueItem);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSendQueue.UpdateStatus(const AItemId: string; AStatus: TSendStatus;
  const AError: string);
var
  I: Integer;
  LItem: TSendQueueItem;
begin
  TMonitor.Enter(FLock);
  try
    for I := 0 to FItems.Count - 1 do
      if FItems[I].ItemId = AItemId then
      begin
        LItem := FItems[I];
        LItem.Status := AStatus;
        LItem.ErrorMessage := AError;
        if AStatus = ssSent then
          LItem.SentAt := Now;
        if AStatus = ssFailed then
        begin
          Inc(LItem.RetryCount);
          if LItem.RetryCount < FMaxRetry then
            LItem.Status := ssPending;
        end;
        FItems[I] := LItem;
        Exit;
      end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.GetAll: TArray<TSendQueueItem>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FItems.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.GetPendingCount: Integer;
var
  LItem: TSendQueueItem;
begin
  Result := 0;
  TMonitor.Enter(FLock);
  try
    for LItem in FItems do
      if LItem.Status = ssPending then
        Inc(Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.GetSentCount: Integer;
var
  LItem: TSendQueueItem;
begin
  Result := 0;
  TMonitor.Enter(FLock);
  try
    for LItem in FItems do
      if LItem.Status = ssSent then
        Inc(Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.GetFailedCount: Integer;
var
  LItem: TSendQueueItem;
begin
  Result := 0;
  TMonitor.Enter(FLock);
  try
    for LItem in FItems do
      if LItem.Status = ssFailed then
        Inc(Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSendQueue.GetSummary: string;
var
  LItem: TSendQueueItem;
  LPending, LSent, LFailed: Integer;
begin
  LPending := 0; LSent := 0; LFailed := 0;
  TMonitor.Enter(FLock);
  try
    for LItem in FItems do
      case LItem.Status of
        ssPending: Inc(LPending);
        ssSent:    Inc(LSent);
        ssFailed:  Inc(LFailed);
      end;
    Result := Format('待处理: %d  已完成: %d  失败: %d  总计: %d',
      [LPending, LSent, LFailed, FItems.Count]);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSendQueue.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FItems.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.