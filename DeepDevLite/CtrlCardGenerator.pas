unit CtrlCardGenerator;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.UITypes, System.Types, FMX.Types, FMX.Graphics,
  uModels;

type
  TSemanticLibrary = class
  private
    FLib: array[TAudience, TMood] of TSemanticEntry;
    procedure Initialize;
  public
    constructor Create;
    function GetEntry(AAudience: TAudience; AMood: TMood): TSemanticEntry;
  end;

  TCardGeneratorController = class
  private
    FSemanticLib: TSemanticLibrary;
    function GetBackgroundColor(ATheme: TCardTheme): TAlphaColor;
    function GetAccentColor(ATheme: TCardTheme): TAlphaColor;
    function GetTextColor(ATheme: TCardTheme): TAlphaColor;
    function GetSubTextColor(ATheme: TCardTheme): TAlphaColor;
  public
    constructor Create;
    destructor Destroy; override;
    
    function GenerateCard(var AConfig: TCardConfig): Boolean;
    function ShuffleHeadline(var AConfig: TCardConfig): Boolean;
    function ExportToPNG(const AConfig: TCardConfig; const FilePath: string): Boolean;
  end;

function CardGeneratorController: TCardGeneratorController;
function SemanticLibrary: TSemanticLibrary;

implementation

var
  GCardGeneratorController: TCardGeneratorController = nil;
  GSemanticLibrary: TSemanticLibrary = nil;

function CardGeneratorController: TCardGeneratorController;
begin
  if not Assigned(GCardGeneratorController) then
    GCardGeneratorController := TCardGeneratorController.Create;
  Result := GCardGeneratorController;
end;

function SemanticLibrary: TSemanticLibrary;
begin
  if not Assigned(GSemanticLibrary) then
    GSemanticLibrary := TSemanticLibrary.Create;
  Result := GSemanticLibrary;
end;

{ TSemanticLibrary }

constructor TSemanticLibrary.Create;
begin
  inherited;
  Initialize;
end;

procedure TSemanticLibrary.Initialize;
begin
  FLib[auGirlfriend, mdSatisfied].Icon := '💕';
  FLib[auGirlfriend, mdSatisfied].Tag := '✓ 功能已验证交付';
  FLib[auGirlfriend, mdSatisfied].SubText := 'Verified · 你别担心我';
  FLib[auGirlfriend, mdSatisfied].Headlines := [
    '今天加班，' + #10 + '但这个功能稳了',
    '熬夜也值了，' + #10 + '这个跑过了',
    '你别等我，' + #10 + '我把这个封存完就回',
    '不是在摸鱼，' + #10 + '是在验证',
    '今晚做了一件' + #10 + '有证明的事',
    '搞定了，' + #10 + '有报告为证'
  ];

  FLib[auGirlfriend, mdProud].Icon := '🔥';
  FLib[auGirlfriend, mdProud].Tag := '✓ 又拿下一个';
  FLib[auGirlfriend, mdProud].SubText := 'Sealed · 等你夸我';
  FLib[auGirlfriend, mdProud].Headlines := [
    '一个人搞定了，' + #10 + '等你夸',
    '这个难点，' + #10 + '今天解决了',
    '别人靠感觉，' + #10 + '我有验证报告',
    '又一个功能，' + #10 + '有证据地拿下了'
  ];

  FLib[auGirlfriend, mdTired].Icon := '😌';
  FLib[auGirlfriend, mdTired].Tag := '✓ 今晚收工';
  FLib[auGirlfriend, mdTired].SubText := 'ODD certified · 回家了';
  FLib[auGirlfriend, mdTired].Headlines := [
    '累，但交出去' + #10 + '的东西是干净的',
    '熬完了，' + #10 + '这次没有遗憾',
    '今晚加班也值了，' + #10 + '功能验证通过',
    '做完了，' + #10 + '可以睡了'
  ];

  FLib[auGirlfriend, mdFocused].Icon := '🎯';
  FLib[auGirlfriend, mdFocused].Tag := '✓ 专注出成果';
  FLib[auGirlfriend, mdFocused].SubText := 'Verified & sealed';
  FLib[auGirlfriend, mdFocused].Headlines := [
    '今天没分心，' + #10 + '一个功能，做完做好',
    '手机都没看，' + #10 + '这个就出来了',
    '专注的两小时' + #10 + '比摸鱼的一天强'
  ];

  FLib[auBoss, mdSatisfied].Icon := '✅';
  FLib[auBoss, mdSatisfied].Tag := '✓ 交付物已验证';
  FLib[auBoss, mdSatisfied].SubText := 'All scenarios passed · ODD certified';
  FLib[auBoss, mdSatisfied].Headlines := [
    '登录模块' + #10 + '验证通过，可上线',
    '今日交付，' + #10 + '验证报告已出',
    '所有场景通过，' + #10 + '可以提审了',
    '功能完成，' + #10 + '有据可查'
  ];

  FLib[auBoss, mdProud].Icon := '📊';
  FLib[auBoss, mdProud].Tag := '✓ 质量有据可查';
  FLib[auBoss, mdProud].SubText := 'Evidence sealed · Ready to review';
  FLib[auBoss, mdProud].Headlines := [
    '3个场景，100%覆盖' + #10 + '有报告可存档',
    '不是感觉没问题，' + #10 + '是验证过没问题',
    '这次交付' + #10 + '附带完整证据链',
    '代码可以换，' + #10 + '验证结果封存了'
  ];

  FLib[auBoss, mdTired].Icon := '🛡️';
  FLib[auBoss, mdTired].Tag := '✓ 今日交付';
  FLib[auBoss, mdTired].SubText := 'Verified · Sealed · Delivered';
  FLib[auBoss, mdTired].Headlines := [
    '功能完成，' + #10 + '验证通过，报告已出',
    '加班也要有' + #10 + '可交付的东西',
    '今天的成果' + #10 + '有报告为证'
  ];

  FLib[auBoss, mdFocused].Icon := '🔒';
  FLib[auBoss, mdFocused].Tag := '✓ 封存完毕';
  FLib[auBoss, mdFocused].SubText := 'Contract fulfilled · Sealed';
  FLib[auBoss, mdFocused].Headlines := [
    '今日任务完成' + #10 + '所有验收条件通过',
    '契约已履行，' + #10 + '结果已封存',
    '按契约交付，' + #10 + '无遗漏'
  ];

  FLib[auPeer, mdSatisfied].Icon := '⚡';
  FLib[auPeer, mdSatisfied].Tag := '✓ ODD闭环完成';
  FLib[auPeer, mdSatisfied].SubText := 'Output-Driven · Not code-driven';
  FLib[auPeer, mdSatisfied].Headlines := [
    '契约→验证→封存' + #10 + '今天又走了一遍',
    '不审代码，' + #10 + '只验产出物',
    'AI写的代码' + #10 + '我用功能测试验',
    '代码是负债，' + #10 + '产出物才是资产'
  ];

  FLib[auPeer, mdProud].Icon := '🧪';
  FLib[auPeer, mdProud].Tag := '✓ 输出驱动验证';
  FLib[auPeer, mdProud].SubText := 'ODD certified · 3/3 passed';
  FLib[auPeer, mdProud].Headlines := [
    '不审查代码，' + #10 + '只验证产出物',
    'AI幻觉？' + #10 + '功能测试一跑就知道',
    '代码谁写的不重要，' + #10 + '跑过了才算数',
    '这才叫' + #10 + 'AI原生开发'
  ];

  FLib[auPeer, mdTired].Icon := '🔗';
  FLib[auPeer, mdTired].Tag := '✓ 证据链完整';
  FLib[auPeer, mdTired].SubText := 'Evidence sealed · Tamper-proof';
  FLib[auPeer, mdTired].Headlines := [
    'SHA-256封存，' + #10 + '可追溯，可审计',
    '有哈希，有时间戳，' + #10 + '有验证记录',
    '改了也不怕，' + #10 + '历史版本都在'
  ];

  FLib[auPeer, mdFocused].Icon := '🏭';
  FLib[auPeer, mdFocused].Tag := '✓ 软件工厂产出';
  FLib[auPeer, mdFocused].SubText := 'DeepDevLite · ODD native';
  FLib[auPeer, mdFocused].Headlines := [
    'AI生成，' + #10 + '人类验收，机器封存',
    '用ODD的方式' + #10 + '做完了这一个',
    '今天没有' + #10 + '靠感觉上线的代码'
  ];

  FLib[auSelf, mdSatisfied].Icon := '✦';
  FLib[auSelf, mdSatisfied].Tag := '✓ 今日完成';
  FLib[auSelf, mdSatisfied].SubText := 'Verified · Sealed · Done';
  FLib[auSelf, mdSatisfied].Headlines := [
    '又一个功能，' + #10 + '有证据地交出去了',
    '今天做的事' + #10 + '我自己放心',
    '这次不是' + #10 + '靠运气过的',
    '做完了，' + #10 + '而且做对了',
    '今天也值了'
  ];

  FLib[auSelf, mdProud].Icon := '🌟';
  FLib[auSelf, mdProud].Tag := '✓ 拿下了';
  FLib[auSelf, mdProud].SubText := 'ODD certified · I know it works';
  FLib[auSelf, mdProud].Headlines := [
    '心里有底，' + #10 + '这次不是靠运气',
    '今天有点' + #10 + '超出自己预期',
    '这个难，' + #10 + '但做完了',
    '进展比预期快，' + #10 + '而且质量在'
  ];

  FLib[auSelf, mdTired].Icon := '🌙';
  FLib[auSelf, mdTired].Tag := '✓ 值得的一天';
  FLib[auSelf, mdTired].SubText := 'Sealed · Worth it';
  FLib[auSelf, mdTired].Headlines := [
    '累，但做的东西' + #10 + '是真的验证过的',
    '今天加班也值了',
    '辛苦是真的，' + #10 + '成果也是真的'
  ];

  FLib[auSelf, mdFocused].Icon := '🎯';
  FLib[auSelf, mdFocused].Tag := '✓ 深度完成';
  FLib[auSelf, mdFocused].SubText := 'Contract → Verify → Seal · Done';
  FLib[auSelf, mdFocused].Headlines := [
    '没有绕过任何步骤，' + #10 + '结果在这里',
    '今天没有' + #10 + '走捷径',
    '一步一步来，' + #10 + '这才叫做完'
  ];
end;

function TSemanticLibrary.GetEntry(AAudience: TAudience; AMood: TMood): TSemanticEntry;
begin
  Result := FLib[AAudience, AMood];
end;

{ TCardGeneratorController }

constructor TCardGeneratorController.Create;
begin
  inherited;
  FSemanticLib := SemanticLibrary;
end;

destructor TCardGeneratorController.Destroy;
begin
  inherited;
end;

function TCardGeneratorController.GenerateCard(var AConfig: TCardConfig): Boolean;
var
  Entry: TSemanticEntry;
  Headlines: TArray<string>;
  Idx: Integer;
begin
  Result := False;
  
  Entry := FSemanticLib.GetEntry(AConfig.Audience, AConfig.Mood);
  
  AConfig.Icon := Entry.Icon;
  AConfig.Tag := Entry.Tag;
  AConfig.SubText := Entry.SubText;
  
  Headlines := Entry.Headlines;
  if Length(Headlines) > 0 then
  begin
    Idx := Random(Length(Headlines));
    AConfig.Headline := Headlines[Idx];
    Result := True;
  end;
  
  AConfig.GeneratedAt := Now;
end;

function TCardGeneratorController.ShuffleHeadline(var AConfig: TCardConfig): Boolean;
var
  Entry: TSemanticEntry;
  Headlines: TArray<string>;
  Others: TArray<string>;
  H: string;
  Idx: Integer;
begin
  Result := False;
  
  Entry := FSemanticLib.GetEntry(AConfig.Audience, AConfig.Mood);
  Headlines := Entry.Headlines;
  
  SetLength(Others, 0);
  for H in Headlines do
  begin
    if H <> AConfig.Headline then
    begin
      SetLength(Others, Length(Others) + 1);
      Others[High(Others)] := H;
    end;
  end;
  
  if Length(Others) = 0 then
    Exit;
  
  Idx := Random(Length(Others));
  AConfig.Headline := Others[Idx];
  Result := True;
end;

function TCardGeneratorController.ExportToPNG(const AConfig: TCardConfig;
  const FilePath: string): Boolean;
var
  Bitmap: TBitmap;
  W, H: Integer;
  BgColor, AccentColor, TextColor, SubTextColor: TAlphaColor;
  
  function MakeRect(ALeft, ATop, ARight, ABottom: Single): TRectF;
  begin
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Right := ARight;
    Result.Bottom := ABottom;
  end;
  
  procedure DrawCenteredText(const AText: string; ATop, AFontSize: Integer; AColor: TAlphaColor; ABold: Boolean);
  var
    TextWidth, TextHeight: Single;
    Lines: TStringList;
    LineTop: Single;
    I: Integer;
    R: TRectF;
  begin
    Bitmap.Canvas.Font.Size := AFontSize;
    if ABold then
      Bitmap.Canvas.Font.Style := [TFontStyle.fsBold]
    else
      Bitmap.Canvas.Font.Style := [];
    
    Lines := TStringList.Create;
    try
      Lines.Text := AText;
      LineTop := ATop;
      
      for I := 0 to Lines.Count - 1 do
      begin
        if Lines[I] = '' then
        begin
          LineTop := LineTop + AFontSize * 1.2;
          Continue;
        end;
        
        TextWidth := Bitmap.Canvas.TextWidth(Lines[I]);
        TextHeight := Bitmap.Canvas.TextHeight(Lines[I]);
        
        R := MakeRect((W - TextWidth) / 2, LineTop, (W + TextWidth) / 2, LineTop + TextHeight);
        
        Bitmap.Canvas.Fill.Color := AColor;
        Bitmap.Canvas.FillText(R, Lines[I], False, 1, [], TTextAlign.Center);
        
        LineTop := LineTop + AFontSize * 1.3;
      end;
    finally
      Lines.Free;
    end;
  end;
  
  procedure DrawGridPattern;
  var
    X, Y: Integer;
    GridColor: TAlphaColor;
    P1, P2: TPointF;
  begin
    GridColor := $15FFFFFF;
    Bitmap.Canvas.Stroke.Color := GridColor;
    Bitmap.Canvas.Stroke.Thickness := 0.5;
    
    Y := 0;
    while Y < H do
    begin
      P1.X := 0;
      P1.Y := Y;
      P2.X := W;
      P2.Y := Y;
      Bitmap.Canvas.DrawLine(P1, P2, 1);
      Inc(Y, 40);
    end;
    
    X := 0;
    while X < W do
    begin
      P1.X := X;
      P1.Y := 0;
      P2.X := X;
      P2.Y := H;
      Bitmap.Canvas.DrawLine(P1, P2, 1);
      Inc(X, 40);
    end;
  end;
  
  procedure DrawStats;
  var
    StatWidth, StatTop: Single;
    R: TRectF;
  begin
    StatWidth := W / 3;
    StatTop := H - 200;
    
    Bitmap.Canvas.Font.Size := 48;
    Bitmap.Canvas.Font.Style := [TFontStyle.fsBold];
    
    Bitmap.Canvas.Fill.Color := AccentColor;
    
    R := MakeRect(0, StatTop, StatWidth, StatTop + 60);
    Bitmap.Canvas.FillText(R, AConfig.StatPass, False, 1, [], TTextAlign.Center);
    
    R := MakeRect(StatWidth, StatTop, StatWidth * 2, StatTop + 60);
    Bitmap.Canvas.FillText(R, AConfig.StatMS, False, 1, [], TTextAlign.Center);
    
    R := MakeRect(StatWidth * 2, StatTop, W, StatTop + 60);
    Bitmap.Canvas.FillText(R, AConfig.StatCoverage, False, 1, [], TTextAlign.Center);
    
    Bitmap.Canvas.Font.Size := 24;
    Bitmap.Canvas.Font.Style := [];
    Bitmap.Canvas.Fill.Color := SubTextColor;
    
    R := MakeRect(0, StatTop + 70, StatWidth, StatTop + 100);
    Bitmap.Canvas.FillText(R, 'SCENARIOS', False, 1, [], TTextAlign.Center);
    
    R := MakeRect(StatWidth, StatTop + 70, StatWidth * 2, StatTop + 100);
    Bitmap.Canvas.FillText(R, 'RESPONSE', False, 1, [], TTextAlign.Center);
    
    R := MakeRect(StatWidth * 2, StatTop + 70, W, StatTop + 100);
    Bitmap.Canvas.FillText(R, 'COVERAGE', False, 1, [], TTextAlign.Center);
  end;

var
  R: TRectF;
begin
  Result := False;
  
  W := 1080;
  H := 1080;
  
  BgColor := GetBackgroundColor(AConfig.Theme);
  AccentColor := GetAccentColor(AConfig.Theme);
  TextColor := GetTextColor(AConfig.Theme);
  SubTextColor := GetSubTextColor(AConfig.Theme);
  
  Bitmap := TBitmap.Create(W, H);
  try
    Bitmap.Canvas.BeginScene;
    try
      R := MakeRect(0, 0, W, H);
      Bitmap.Canvas.Fill.Color := BgColor;
      Bitmap.Canvas.FillRect(R, 0, 0, [], 1);
      
      DrawGridPattern;
      
      Bitmap.Canvas.Font.Size := 72;
      DrawCenteredText(AConfig.Icon, 80, 72, AccentColor, False);
      
      Bitmap.Canvas.Font.Size := 28;
      DrawCenteredText(UpperCase(AConfig.Tag), 180, 28, AccentColor, True);
      
      Bitmap.Canvas.Font.Size := 42;
      DrawCenteredText(AConfig.Headline, 280, 42, TextColor, True);
      
      Bitmap.Canvas.Font.Size := 24;
      DrawCenteredText(AConfig.SubText, 550, 24, SubTextColor, False);
      
      Bitmap.Canvas.Font.Size := 20;
      DrawCenteredText(AConfig.ModuleName, 650, 20, SubTextColor, False);
      
      DrawStats;
      
      Bitmap.Canvas.Font.Size := 18;
      Bitmap.Canvas.Font.Style := [];
      Bitmap.Canvas.Fill.Color := SubTextColor;
      R := MakeRect(0, H - 60, W, H - 30);
      Bitmap.Canvas.FillText(R, 'DeepDevLite · ODD Native Software Factory', False, 1, [], TTextAlign.Center);
      
    finally
      Bitmap.Canvas.EndScene;
    end;
    
    Bitmap.SaveToFile(FilePath);
    Result := True;
  finally
    Bitmap.Free;
  end;
end;

function TCardGeneratorController.GetBackgroundColor(ATheme: TCardTheme): TAlphaColor;
begin
  case ATheme of
    ctDark: Result := $FF0D5C4A;
    ctLight: Result := $FFF7F9F8;
    ctNight: Result := $FF0A0F0E;
    ctWarm: Result := $FF1A3C34;
  else
    Result := $FF0D5C4A;
  end;
end;

function TCardGeneratorController.GetAccentColor(ATheme: TCardTheme): TAlphaColor;
begin
  case ATheme of
    ctDark: Result := $FF00E5A0;
    ctLight: Result := $FF0D5C4A;
    ctNight: Result := $FF00E5A0;
    ctWarm: Result := $FF00E5A0;
  else
    Result := $FF00E5A0;
  end;
end;

function TCardGeneratorController.GetTextColor(ATheme: TCardTheme): TAlphaColor;
begin
  case ATheme of
    ctDark: Result := $FFFFFFFF;
    ctLight: Result := $FF0F1F1A;
    ctNight: Result := $FFFFFFFF;
    ctWarm: Result := $FFFFFFFF;
  else
    Result := $FFFFFFFF;
  end;
end;

function TCardGeneratorController.GetSubTextColor(ATheme: TCardTheme): TAlphaColor;
begin
  case ATheme of
    ctDark: Result := $AAFFFFFF;
    ctLight: Result := $FF7A9088;
    ctNight: Result := $AAFFFFFF;
    ctWarm: Result := $AAFFFFFF;
  else
    Result := $AAFFFFFF;
  end;
end;

end.
