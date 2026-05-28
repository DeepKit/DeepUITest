{ ============================================================================
  DeepSpec.Services.Context

  Pluggable context assembly pipeline with token budget trimming.
  Collects context from multiple sources (scan, docs, trees, decisions)
  and assembles a prompt-ready context within a configurable token budget.
  ============================================================================ }

unit DeepSpec.Services.Context;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Models;

type
  TContextSourceKind = (
    cskProjectMeta,   // project name, type, scan stats
    cskAiRules,       // .cursorrules, .clauderc, etc.
    cskDocs,          // documentation files
    cskCodeStructure, // file listing / skeleton
    cskExistingTrees, // current tree YAML nodes
    cskDecisions,     // accepted decisions
    cskIssues         // known issues
  );

  TContextChunk = record
    SourceKind: TContextSourceKind;
    Label_: string;
    Content: string;
    TokenEstimate: Integer;
    Priority: Integer; // 0 = highest, trimmed last
  end;

  IContextSource = interface
    ['{F8E2A1D0-4B3C-4D9E-8F1A-5C6D7E8F9A0B}']
    function Collect: TArray<TContextChunk>;
  end;

  TContextAssembler = class
  private
    FSources: TList<IContextSource>;
    FTokenBudget: Integer;
    class function EstimateTokens(const AText: string): Integer; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddSource(const ASource: IContextSource);
    procedure SetTokenBudget(ATokenCount: Integer);
    function Assemble: string;
    property TokenBudget: Integer read FTokenBudget write FTokenBudget;
  end;

  // Built-in sources
  TTreeContextSource = class(TInterfacedObject, IContextSource)
  private
    FNodes: TList<TSpecNode>;
    FTreeLabel: string;
    FPriority: Integer;
  public
    constructor Create(const ALabel: string; ANodes: TList<TSpecNode>;
      APriority: Integer = 3);
    function Collect: TArray<TContextChunk>;
  end;

  TDecisionContextSource = class(TInterfacedObject, IContextSource)
  private
    FDecisions: TList<TSpecDecision>;
  public
    constructor Create(ADecisions: TList<TSpecDecision>);
    function Collect: TArray<TContextChunk>;
  end;

  TStringContextSource = class(TInterfacedObject, IContextSource)
  private
    FKind: TContextSourceKind;
    FLabel_: string;
    FContent: string;
    FPriority: Integer;
  public
    constructor Create(AKind: TContextSourceKind; const ALabel, AContent: string;
      APriority: Integer = 5);
    function Collect: TArray<TContextChunk>;
  end;

implementation

uses
  System.Generics.Defaults;

{ TContextAssembler }

constructor TContextAssembler.Create;
begin
  inherited Create;
  FSources := TList<IContextSource>.Create;
  FTokenBudget := 8000; // default
end;

destructor TContextAssembler.Destroy;
begin
  FSources.Free;
  inherited;
end;

procedure TContextAssembler.AddSource(const ASource: IContextSource);
begin
  FSources.Add(ASource);
end;

procedure TContextAssembler.SetTokenBudget(ATokenCount: Integer);
begin
  FTokenBudget := ATokenCount;
end;

class function TContextAssembler.EstimateTokens(const AText: string): Integer;
begin
  // Rough estimate: ~4 chars per token for English, ~2 for CJK
  Result := Length(AText) div 3;
end;

function TContextAssembler.Assemble: string;
var
  LAllChunks: TList<TContextChunk>;
  LSb: TStringBuilder;
  LUsedTokens, I: Integer;
begin
  // Collect all chunks from all sources
  LAllChunks := TList<TContextChunk>.Create;
  try
    for var LSource in FSources do
    begin
      var LChunks := LSource.Collect;
      for var LChunk in LChunks do
        LAllChunks.Add(LChunk);
    end;

    // Sort by priority (lower = more important, kept when trimming)
    LAllChunks.Sort(TComparer<TContextChunk>.Construct(
      function(const A, B: TContextChunk): Integer
      begin
        Result := A.Priority - B.Priority;
      end));

    // Build output within budget
    LSb := TStringBuilder.Create;
    try
      LUsedTokens := 0;
      for I := 0 to LAllChunks.Count - 1 do
      begin
        var LChunk := LAllChunks[I];
        if LUsedTokens + LChunk.TokenEstimate > FTokenBudget then
        begin
          // Truncate this chunk to fit remaining budget
          var LRemaining := FTokenBudget - LUsedTokens;
          if LRemaining > 100 then
          begin
            var LChars := LRemaining * 3;
            if LChars > Length(LChunk.Content) then LChars := Length(LChunk.Content);
            LSb.AppendLine('## ' + LChunk.Label_ + ' (truncated)');
            LSb.AppendLine(LChunk.Content.Substring(0, LChars));
            LSb.AppendLine('... [truncated to fit token budget]');
            LSb.AppendLine('');
          end;
          Break;
        end;

        LSb.AppendLine('## ' + LChunk.Label_);
        LSb.AppendLine(LChunk.Content);
        LSb.AppendLine('');
        LUsedTokens := LUsedTokens + LChunk.TokenEstimate;
      end;

      Result := LSb.ToString;
    finally
      LSb.Free;
    end;
  finally
    LAllChunks.Free;
  end;
end;

{ TTreeContextSource }

constructor TTreeContextSource.Create(const ALabel: string;
  ANodes: TList<TSpecNode>; APriority: Integer);
begin
  inherited Create;
  FTreeLabel := ALabel;
  FNodes := ANodes;
  FPriority := APriority;
end;

function TTreeContextSource.Collect: TArray<TContextChunk>;
var
  LSb: TStringBuilder;
begin
  if (FNodes = nil) or (FNodes.Count = 0) then Exit(nil);

  LSb := TStringBuilder.Create;
  try
    for var LNode in FNodes do
    begin
      LSb.AppendLine('- ' + LNode.Id + ': ' + LNode.Title +
        ' [' + TSpecEnums.NodeStatusToStr(LNode.Status) + ']');
      if LNode.Summary <> '' then
        LSb.AppendLine('  ' + LNode.Summary);
    end;

    var LChunk: TContextChunk;
    LChunk.SourceKind := cskExistingTrees;
    LChunk.Label_ := FTreeLabel + ' (' + FNodes.Count.ToString + ' nodes)';
    LChunk.Content := LSb.ToString;
    LChunk.TokenEstimate := Length(LChunk.Content) div 3;
    LChunk.Priority := FPriority;
    Result := TArray<TContextChunk>.Create(LChunk);
  finally
    LSb.Free;
  end;
end;

{ TDecisionContextSource }

constructor TDecisionContextSource.Create(ADecisions: TList<TSpecDecision>);
begin
  inherited Create;
  FDecisions := ADecisions;
end;

function TDecisionContextSource.Collect: TArray<TContextChunk>;
var
  LSb: TStringBuilder;
begin
  if (FDecisions = nil) or (FDecisions.Count = 0) then Exit(nil);

  LSb := TStringBuilder.Create;
  try
    for var LDec in FDecisions do
    begin
      if LDec.Status <> dsAccepted then Continue;
      LSb.AppendLine('- ' + LDec.Id + ': ' + LDec.Title);
      if LDec.Rationale <> '' then
        LSb.AppendLine('  Rationale: ' + LDec.Rationale);
    end;

    if LSb.Length = 0 then Exit(nil);

    var LChunk: TContextChunk;
    LChunk.SourceKind := cskDecisions;
    LChunk.Label_ := 'Accepted Decisions';
    LChunk.Content := LSb.ToString;
    LChunk.TokenEstimate := Length(LChunk.Content) div 3;
    LChunk.Priority := 2; // high priority
    Result := TArray<TContextChunk>.Create(LChunk);
  finally
    LSb.Free;
  end;
end;

{ TStringContextSource }

constructor TStringContextSource.Create(AKind: TContextSourceKind;
  const ALabel, AContent: string; APriority: Integer);
begin
  inherited Create;
  FKind := AKind;
  FLabel_ := ALabel;
  FContent := AContent;
  FPriority := APriority;
end;

function TStringContextSource.Collect: TArray<TContextChunk>;
var
  LChunk: TContextChunk;
begin
  if FContent = '' then Exit(nil);
  LChunk.SourceKind := FKind;
  LChunk.Label_ := FLabel_;
  LChunk.Content := FContent;
  LChunk.TokenEstimate := Length(FContent) div 3;
  LChunk.Priority := FPriority;
  Result := TArray<TContextChunk>.Create(LChunk);
end;

end.
