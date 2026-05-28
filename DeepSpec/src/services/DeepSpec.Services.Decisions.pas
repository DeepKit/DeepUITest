{ ============================================================================
  DeepSpec.Services.Decisions

  Manages decision write-back. Loads existing decisions, appends new ones,
  and serializes back to YAML per protocol §9.
  ============================================================================ }

unit DeepSpec.Services.Decisions;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  DeepSpec.Models;

type
  TDeepSpecDecisionsService = class(TInterfacedObject)
  private
    FBasePath: string;
    FDecisions: TList<TSpecDecision>;
    FNextSeq: Integer;
    function GenerateNextId: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Initialize(const ADeepSpecPath: string);
    procedure Load;
    procedure Save;

    function AddDecision(ADecisionType: TDecisionType;
      const ATitle, ADecisionText, ARationale: string;
      const ATargetNodes: TArray<string>): string;

    function FindById(const AId: string): TSpecDecision;
    function GetAccepted: TArray<TSpecDecision>;
    procedure AcceptDecision(const AId: string);
    procedure RejectDecision(const AId: string);

    /// <summary>
    /// Read pending-decisions.yaml (produced by the WebView2 JS Bridge),
    /// convert each entry to a formal decision via AddDecision, set its
    /// status to accepted/rejected based on the recorded action, then delete
    /// the pending file. Returns the count of promoted entries.
    /// </summary>
    function PromotePending: Integer;

    /// <summary>
    /// Apply state machine transitions to all trees for accepted/rejected
    /// decisions. Reads each tree, updates matching nodes via
    /// TSpecEnums.TryTransition*, writes back.
    /// </summary>
    procedure ApplyNodeStatusTransitions(
      const ATreeRelPath: string;
      AReadTree: TFunc<string, TList<TSpecNode>>;
      AWriteTree: TProc<string, TList<TSpecNode>>); overload;
    procedure ApplyNodeStatusTransitions(
      const ATreeRelPath: string;
      ANodes: TList<TSpecNode>); overload;

    property Decisions: TList<TSpecDecision> read FDecisions;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  DeepSpec.Yaml.Writer,
  DeepSpec.Yaml.Parser;

constructor TDeepSpecDecisionsService.Create;
begin
  inherited Create;
  FDecisions := TList<TSpecDecision>.Create;
  FNextSeq := 1;
end;

destructor TDeepSpecDecisionsService.Destroy;
begin
  FDecisions.Free;
  inherited;
end;

procedure TDeepSpecDecisionsService.Initialize(const ADeepSpecPath: string);
begin
  FBasePath := TPath.Combine(ADeepSpecPath, 'decisions');
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

function TDeepSpecDecisionsService.GenerateNextId: string;
begin
  Result := Format('dec-%.4d', [FNextSeq]);
  Inc(FNextSeq);
end;

procedure TDeepSpecDecisionsService.Load;
var
  LParser: TYamlParser;
  LRoot: TYamlNode;
begin
  FDecisions.Clear;
  FNextSeq := 1;

  var LPath := TPath.Combine(FBasePath, 'requirement-decisions.yaml');
  if not TFile.Exists(LPath) then Exit;

  LParser := TYamlParser.Create;
  try
    LRoot := LParser.ParseFile(LPath);
    try
      var LDecSeq := LRoot.GetSeq('decisions');
      if LDecSeq = nil then Exit;

      for var I := 0 to LDecSeq.SeqCount - 1 do
      begin
        var LItem := LDecSeq.SeqItem(I);
        if LItem = nil then Continue;

        var LDec: TSpecDecision;
        LDec := Default(TSpecDecision);
        LDec.Id := LItem.GetString('id', '');
        LDec.Title := LItem.GetString('title', '');
        LDec.DecisionText := LItem.GetString('decision', '');
        LDec.Rationale := LItem.GetString('rationale', '');
        LDec.AiInstruction := LItem.GetString('ai_instruction', '');
        LDec.Release := LItem.GetString('release', '');
        LDec.SupersededBy := LItem.GetString('superseded_by', '');

        var LStatusStr := LItem.GetString('status', 'proposed');
        if LStatusStr = 'accepted' then LDec.Status := dsAccepted
        else if LStatusStr = 'rejected' then LDec.Status := dsRejected
        else if LStatusStr = 'superseded' then LDec.Status := dsSuperseded
        else if LStatusStr = 'rolled_back' then LDec.Status := dsRolledBack
        else if LStatusStr = 'withdrawn' then LDec.Status := dsWithdrawn
        else LDec.Status := dsProposed;

        var LDeciderStr := LItem.GetString('decided_by', 'system');
        if LDeciderStr = 'human' then LDec.DecidedBy := dbHuman else LDec.DecidedBy := dbSystem;

        FDecisions.Add(LDec);

        // Track sequence number to avoid collisions
        if LDec.Id.StartsWith('dec-') then
        begin
          var LSeqNum := StrToIntDef(LDec.Id.Substring(4), 0);
          if LSeqNum >= FNextSeq then
            FNextSeq := LSeqNum + 1;
        end;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;
end;

procedure TDeepSpecDecisionsService.Save;
var
  LWriter: TYamlWriter;
begin
  LWriter := TYamlWriter.Create;
  try
    LWriter.WriteDecisionsFile(FDecisions);
    TFile.WriteAllText(TPath.Combine(FBasePath, 'requirement-decisions.yaml'),
      LWriter.ToString, TEncoding.UTF8);
  finally
    LWriter.Free;
  end;
end;

function TDeepSpecDecisionsService.AddDecision(ADecisionType: TDecisionType;
  const ATitle, ADecisionText, ARationale: string;
  const ATargetNodes: TArray<string>): string;
var
  LDec: TSpecDecision;
begin
  LDec := Default(TSpecDecision);
  LDec.Id := GenerateNextId;
  LDec.DecisionType := ADecisionType;
  LDec.Title := ATitle;
  LDec.DecisionText := ADecisionText;
  LDec.Rationale := ARationale;
  LDec.TargetNodes := ATargetNodes;
  LDec.CreatedAt := Now;
  LDec.UpdatedAt := Now;
  LDec.DecidedBy := dbHuman;
  LDec.Confidence := clHigh;
  LDec.Status := dsProposed;

  FDecisions.Add(LDec);
  Result := LDec.Id;
  Save;
end;

function TDeepSpecDecisionsService.FindById(const AId: string): TSpecDecision;
begin
  for var LDec in FDecisions do
    if LDec.Id = AId then
      Exit(LDec);
  Result := Default(TSpecDecision);
end;

function TDeepSpecDecisionsService.GetAccepted: TArray<TSpecDecision>;
var
  LResult: TList<TSpecDecision>;
begin
  LResult := TList<TSpecDecision>.Create;
  try
    for var LDec in FDecisions do
      if LDec.Status = dsAccepted then
        LResult.Add(LDec);
    Result := LResult.ToArray;
  finally
    LResult.Free;
  end;
end;

procedure TDeepSpecDecisionsService.AcceptDecision(const AId: string);
begin
  for var I := 0 to FDecisions.Count - 1 do
    if FDecisions[I].Id = AId then
    begin
      var LDec := FDecisions[I];
      LDec.Status := dsAccepted;
      LDec.UpdatedAt := Now;
      FDecisions[I] := LDec;
      Save;
      Exit;
    end;
end;

procedure TDeepSpecDecisionsService.RejectDecision(const AId: string);
begin
  for var I := 0 to FDecisions.Count - 1 do
    if FDecisions[I].Id = AId then
    begin
      var LDec := FDecisions[I];
      LDec.Status := dsRejected;
      LDec.UpdatedAt := Now;
      FDecisions[I] := LDec;
      Save;
      Exit;
    end;
end;

function TDeepSpecDecisionsService.PromotePending: Integer;
var
  LParser: TYamlParser;
  LRoot, LSeq: TYamlNode;
  LPath, LAction, LNodeId, LNodeTitle, LDecId, LTitle: string;
  LDecType: TDecisionType;
begin
  Result := 0;
  LPath := TPath.Combine(FBasePath, 'pending-decisions.yaml');
  if not TFile.Exists(LPath) then Exit;

  LParser := TYamlParser.Create;
  try
    LRoot := LParser.ParseFile(LPath);
    if LRoot = nil then Exit;
    try
      LSeq := LRoot.GetSeq('pending_decisions');
      if LSeq = nil then Exit;

      for var I := 0 to LSeq.SeqCount - 1 do
      begin
        var LItem := LSeq.SeqItem(I);
        if LItem = nil then Continue;

        LAction := LItem.GetString('action', '');
        LNodeId := LItem.GetString('node_id', '');
        LNodeTitle := LItem.GetString('node_title', '');

        if (LNodeId = '') or
           ((LAction <> 'node-confirm') and (LAction <> 'node-reject')) then
          Continue;

        if LAction = 'node-confirm' then
        begin
          LDecType := dtConfirm;
          LTitle := 'Confirm: ' + LNodeTitle;
        end
        else
        begin
          LDecType := dtReject;
          LTitle := 'Reject: ' + LNodeTitle;
        end;

        LDecId := AddDecision(LDecType, LTitle,
          LAction + ' (target: ' + LNodeId + ')',
          'Recorded via WebView2 JS Bridge', [LNodeId]);

        if LAction = 'node-confirm' then
          AcceptDecision(LDecId)
        else
          RejectDecision(LDecId);

        Inc(Result);
      end;
    finally
      LRoot.Free;
    end;
  finally
    LParser.Free;
  end;

  // Clear pending file once promoted
  if Result > 0 then
    TFile.Delete(LPath);
end;

procedure TDeepSpecDecisionsService.ApplyNodeStatusTransitions(
  const ATreeRelPath: string;
  AReadTree: TFunc<string, TList<TSpecNode>>;
  AWriteTree: TProc<string, TList<TSpecNode>>);
var
  LNodes: TList<TSpecNode>;
  LChanged: Boolean;
  LError: string;
begin
  LNodes := AReadTree(ATreeRelPath);
  if LNodes = nil then Exit;
  try
    LChanged := False;
    for var I := 0 to LNodes.Count - 1 do
    begin
      var LNode := LNodes[I];

      // Find accepted/rejected decisions targeting this node
      for var LDec in FDecisions do
      begin
        if LDec.Status <> dsAccepted then Continue;
        var LTargetsNode := False;
        for var LT in LDec.TargetNodes do
          if LT = LNode.Id then begin LTargetsNode := True; Break; end;
        if not LTargetsNode then Continue;

        case LDec.DecisionType of
          dtConfirm:
          begin
            // Confirm: gen draft/generated → confirmed, review unreviewed → accepted
            if TSpecEnums.TryTransitionGen(LNode.GenStatus, gsConfirmed, LError) then
              LChanged := True
            else
              OutputDebugString(PChar('DeepSpec: ' + LError));
            if TSpecEnums.TryTransitionReview(LNode.ReviewStatus, rsAccepted, LError) then
              LChanged := True
            else
              OutputDebugString(PChar('DeepSpec: ' + LError));
            // Also update legacy Status
            LNode.Status := nsConfirmed;
          end;
          dtReject:
          begin
            // Reject: gen → skipped, review → rejected
            if TSpecEnums.TryTransitionGen(LNode.GenStatus, gsSkipped, LError) then
              LChanged := True
            else
              OutputDebugString(PChar('DeepSpec: ' + LError));
            if TSpecEnums.TryTransitionReview(LNode.ReviewStatus, rsRejected, LError) then
              LChanged := True
            else
              OutputDebugString(PChar('DeepSpec: ' + LError));
            LNode.Status := nsRejected;
          end;
        end;
      end;

      LNodes[I] := LNode;
    end;

    if LChanged then
      AWriteTree(ATreeRelPath, LNodes);
  finally
    LNodes.Free;
  end;
end;

procedure TDeepSpecDecisionsService.ApplyNodeStatusTransitions(
  const ATreeRelPath: string; ANodes: TList<TSpecNode>);
var
  LChanged: Boolean;
  LError: string;
begin
  if ANodes = nil then Exit;
  LChanged := False;
  for var I := 0 to ANodes.Count - 1 do
  begin
    var LNode := ANodes[I];
    for var LDec in FDecisions do
    begin
      if LDec.Status <> dsAccepted then Continue;
      var LTargetsNode := False;
      for var LT in LDec.TargetNodes do
        if LT = LNode.Id then begin LTargetsNode := True; Break; end;
      if not LTargetsNode then Continue;
      case LDec.DecisionType of
        dtConfirm:
        begin
          if TSpecEnums.TryTransitionGen(LNode.GenStatus, gsConfirmed, LError) then
            LChanged := True;
          if TSpecEnums.TryTransitionReview(LNode.ReviewStatus, rsAccepted, LError) then
            LChanged := True;
          LNode.Status := nsConfirmed;
        end;
        dtReject:
        begin
          if TSpecEnums.TryTransitionGen(LNode.GenStatus, gsSkipped, LError) then
            LChanged := True;
          if TSpecEnums.TryTransitionReview(LNode.ReviewStatus, rsRejected, LError) then
            LChanged := True;
          LNode.Status := nsRejected;
        end;
      end;
    end;
    ANodes[I] := LNode;
  end;
end;

end.
