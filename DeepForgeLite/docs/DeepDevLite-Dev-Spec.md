# DeepDevLite 开发规格文�?
**版本**: v1.0  
**技术栈**: Delphi FMX（跨平台�? 
**范围**: 朋友圈卡片生成器 + 完整验证报告  
**导出**: PNG + PDF

---

## 目录

1. 产品概述
2. 整体架构
3. 数据模型
4. 模块一：验证报�?5. 模块二：朋友圈卡片生成器
6. 导出功能（PNG + PDF�?7. 语义库完整数�?8. UI 规范（颜�?/ 字体 / 间距�?
---

## 1. 产品概述

DeepDevLite �?Progee 的轻量入门版，核心流程：

```
用户描述功能契约 �?AI 生成代码 �?自动验证 �?生成验证报告 �?生成朋友圈卡�?```

本文档覆盖后两步的完整实现：**验证报告** �?**朋友圈卡片生成器**�?
---

## 2. 整体架构

### 2.1 窗体结构

```
TFormMain（主窗口�?�?├── TFrameReport（验证报�?Frame�?�?  ├── 报告头部区域
�?  ├── 验证结论区域
�?  ├── 场景明细列表
�?  ├── 证据链区�?�?  └── 底部操作栏（导出 PDF / 分享链接�?�?└── TFrameCardGenerator（朋友圈生成�?Frame�?    ├── 左侧控制面板
    �?  ├── 模块名称输入
    �?  ├── 受众选择�?�?�?    �?  ├── 状态选择�?�?�?    �?  ├── 风格选择�?�?�?    �?  └── 生成按钮 / 换一句按�?    └── 右侧预览面板
        ├── TCardPreview（自定义绘制控件�?        └── 底部操作栏（保存 PNG / 导出 PDF�?```

### 2.2 核心依赖

| 功能 | Delphi 实现方式 |
|------|----------------|
| PNG 导出 | `TBitmap` �?`SaveToFile` |
| PDF 导出 | `TPrinter` + PDF 虚拟打印机，或第三方�?FastReport / Skia |
| 自定义绘�?| `TCanvas`（FMX�? `OnPaint` |
| 圆角矩形 | `Canvas.FillRect` + `Canvas.DrawRect`（设�?XRadius/YRadius）|
| 渐变背景 | `TGradient` 或手�?`Canvas` 绘制 |
| 字体 | FMX `TFont`，中文推荐系统字�?|

---

## 3. 数据模型

### 3.1 验证场景记录

```pascal
type
  TScenarioStatus = (ssPass, ssFail, ssSkip);

  TScenarioRecord = record
    DescZH     : string;         // 中文描述，如"正确账号密码登录"
    DescEN     : string;         // 英文描述，如"Valid credentials �?returns token"
    Status     : TScenarioStatus;
    ResponseMS : Integer;        // 响应时间（毫秒）
  end;
```

### 3.2 验证报告数据

```pascal
type
  TVerificationReport = record
    ProjectNameZH : string;      // 项目名（中文�?    ReportID      : string;      // 报告编号，如"PRG-20260220-0042"
    VerifiedAt    : TDateTime;   // 验证时间
    AIModel       : string;      // AI 模型名，�?claude-sonnet-4"
    AuthorizedBy  : string;      // 授权�?    SealHash      : string;      // SHA-256 哈希
    Scenarios     : array of TScenarioRecord;
    IsSealed      : Boolean;
  end;
```

### 3.3 卡片配置数据

```pascal
type
  TAudience = (auGirlfriend, auBoss, auPeer, auSelf);
  TMood     = (mdSatisfied, mdProud, mdTired, mdFocused);
  TCardTheme = (ctDark, ctLight, ctNight, ctWarm);

  TCardConfig = record
    ModuleName : string;        // 完成的模块名�?    Audience   : TAudience;
    Mood       : TMood;
    Theme      : TCardTheme;
    Headline   : string;        // 当前显示的大标题（可编辑�?    Icon       : string;        // Emoji 图标
    Tag        : string;        // 顶部小标签文�?    SubText    : string;        // 副标�?    StatPass   : string;        // �?3/3"
    StatMS     : string;        // �?253ms"
    StatCoverage: string;       // �?100%"
    GeneratedAt: TDateTime;
  end;
```

### 3.4 语义条目

```pascal
type
  TSemanticEntry = record
    Icon      : string;
    Tag       : string;
    Headlines : array of string;   // 多条候选，随机取一�?    SubText   : string;
  end;
```

---

## 4. 模块一：验证报�?
### 4.1 布局规格

报告为垂直滚动面板，固定宽度 **680px**（可缩放），各区域从上到下依次排列：

```
┌─────────────────────────────────────�? 高度�?90px
�? Header（深绿背�?#0D5C4A�?         �?�? 品牌标识 + 项目�?+ 元信�?         �?├─────────────────────────────────────�? 高度�?90px
�? Verdict（浅绿背�?rgba accent 12%）│
�? 验证结论 + 通过率大数字             �?├─────────────────────────────────────�? 高度自适应
�? Scenarios（白色背景）              �?�? 每条场景一行卡�?                  �?├─────────────────────────────────────�? 高度�?110px
�? Evidence（浅灰背�?#FAFCFB�?      �?�? 验证方式 / 模型 / 封存状�?/ 哈希  �?├─────────────────────────────────────�? 高度�?28px
�? Sealed Banner（深绿背景）          �?�? 封存声明文字                       �?├─────────────────────────────────────�? 高度�?56px
�? Footer（白色）                     �?�? 品牌文字 + 分享链接 + 导出 PDF 按钮�?└─────────────────────────────────────�?```

### 4.2 Header 区域

**背景�?*: `#0D5C4A`  
**内边�?*: 32px 40px 28px

| 元素 | 规格 |
|------|------|
| 品牌标识方块 | 28×28px，圆�?6px，背�?`#00E5A0`，文�?Pg"，字�?Mono 12px，颜�?`#0D5C4A` |
| 品牌�?| "Progee · Verification Report"，Mono 13px，颜�?rgba(255,255,255,0.6) |
| 报告标题（中�?| 字体衬线 26px，颜色白�?|
| 报告标题（英�?| Mono 12px，颜�?rgba(255,255,255,0.45)，大�?|
| 元信息行 | 三列：项目名 / 验证时间 / 报告编号，标�?10px，�?13px Mono |

**装饰圆环**（纯视觉）：右上角两个透明圆环，用 `Canvas.DrawEllipse` 绘制，颜�?rgba(255,255,255,0.08)�?
### 4.3 Verdict 区域

**背景�?*: `rgba(0,229,160,0.12)`（叠加在白色上）  
**内边�?*: 28px 40px

左侧�?- 状态徽章：小圆点（带呼吸动画）+ "验证通过 · VERIFIED"，背�?`#00E5A0`，文�?`#0D5C4A`，Mono 11px
- 主文字（中）�?所有场景通过验证"�?2px 粗体，颜�?`#0D5C4A`
- 副文字（英）�?All scenarios passed · Ready to deliver"，Mono 12px，颜�?muted

右侧�?- 大数字（�?3/3"）：衬线字体斜体 52px，颜�?`#0D5C4A`
- 标签�?场景通过 / Scenarios Passed"，Mono 11px

> **呼吸动画实现**：用 `TTimer`（间�?50ms），对小圆点 `TCircle` �?`Opacity` �?sin 曲线变化，周期约 2 秒�?
### 4.4 Scenarios 区域

**内边�?*: 28px 40px  
**场景列表**: 垂直排列，间�?8px

每条场景卡片�?
```
┌──────────────────────────────────────────�?�? �? 中文描述               响应时间  PASS�?�?     英文描述                             �?└──────────────────────────────────────────�?```

| 元素 | 规格 |
|------|------|
| 卡片背景 | `#FAFCFB`，圆�?8px，边�?1px `#E2EAE7` |
| Emoji 图标 | 14px，左对齐 |
| 中文描述 | 13px 粗体，颜�?`#0F1F1A` |
| 英文描述 | 11px，Mono，颜�?muted |
| 响应时间 | 11px，Mono，右对齐，颜�?muted |
| 状态徽�?PASS | Mono 11px，背�?`rgba(0,229,160,0.15)`，文�?`#0A7A56` |
| 状态徽�?FAIL | Mono 11px，背�?`rgba(239,68,68,0.1)`，文�?`#EF4444` |

**实现方式**：场景列表用 `TVertScrollBox` + 动态创�?`TRectangle`（每条场景一个），内部用 `TLabel` 组合布局�?
### 4.5 Evidence 区域

**背景�?*: `#FAFCFB`  
**内边�?*: 20px 40px 24px  
**布局**: 2列网格，间距 12px

| 字段 | 说明 |
|------|------|
| 验证方式 | "ODD 输出对比验证" |
| AI 模型 | �?claude-sonnet-4" |
| 封存状�?| "�?已封�?SEALED"，颜�?`#0D5C4A` |
| 授权�?| 用户�?|
| SHA-256 哈希 | 跨两列，64位十六进制字符串，Mono 11px，自动换�?|

### 4.6 Sealed Banner

**背景�?*: `#0D5C4A`  
**高度**: 28px  
**文字**: 居中，Mono 11px，颜�?rgba(255,255,255,0.6)  
**内容**: "此报告由 **Progee** 自动生成并封�?· This report is auto-generated and sealed by **Progee**"

### 4.7 Footer

**背景�?*: 白色  
**内边�?*: 20px 40px  
**左侧**: "DeepDevLite · ODD-Native Software Factory · v1.0"，Mono 12px，muted  
**右侧**: 两个按钮�?
| 按钮 | 样式 |
|------|------|
| 🔗 分享链接 | 边框按钮�?px 边框 `#E2EAE7`，悬停变品牌�?|
| �?导出 PDF | 实心按钮，背�?`#0D5C4A`，文字白�?|

### 4.8 报告 ID 生成算法

```pascal
function GenerateReportID(const dt: TDateTime): string;
var
  Y, M, D, H, N, S, MS: Word;
  Seq: Integer;
begin
  DecodeDateTime(dt, Y, M, D, H, N, S, MS);
  Seq := Random(9999) + 1;  // 实际应用中用原子计数�?  Result := Format('PRG-%04d%02d%02d-%04d', [Y, M, D, Seq]);
end;
```

### 4.9 SHA-256 封存哈希

```pascal
// 使用 Delphi 内置 System.Hash
uses System.Hash;

function GenerateSealHash(const Report: TVerificationReport): string;
var
  RawData: string;
begin
  RawData := Report.ReportID
           + Report.ProjectNameZH
           + DateTimeToStr(Report.VerifiedAt)
           + IntToStr(Length(Report.Scenarios));
  Result := THashSHA2.GetHashString(RawData);
end;
```

---

## 5. 模块二：朋友圈卡片生成器

### 5.1 整体布局

窗口分左右两栏，不可调整大小�?
```
┌──────────────────┬─────────────────────────────�?�? 控制面板 300px  �? 预览区域（自适应�?         �?�?                 �?                             �?�? 模块名输�?     �?      卡片预览 360×360       �?�? 受众选择        �?                             �?�? 状态选择        �?      [保存PNG] [导出PDF]    �?�? 风格选择        �?                             �?�? [换一句] [生成] �?                             �?└──────────────────┴─────────────────────────────�?```

### 5.2 控制面板

**背景**: 白色，右�?1px 边框 `#E0E8E4`  
**内边�?*: 24px 20px  
**垂直间距**: 各控件组间距 20px

#### 模块名输�?
```
标签: "完成了什�?（Mono 10px 大写 muted�?控件: TEdit，圆�?8px，边�?#E0E8E4，占位符"例：购物车结算逻辑"
```

#### 受众选择�?×2 网格�?
```
选项: 💕 女朋�?| 💼 老板 | 👨‍�?同行 | �?自我满足
```

实现�?�?`TRectangle` 模拟按钮，互斥选中�?
**未选中状�?*: 边框 `#E0E8E4`，背景透明，文�?muted  
**选中状�?*: 边框 `#0D5C4A`，背�?`rgba(13,92,74,0.06)`，文�?`#0D5C4A` 粗体

点击事件�?
```pascal
procedure TFrameCardGenerator.OnAudienceBtnClick(Sender: TObject);
var
  Btn: TRectangle;
begin
  // 重置所有按�?  ResetAudienceBtns;
  // 激活当前按�?  Btn := Sender as TRectangle;
  SetBtnActive(Btn);
  // 更新状�?  FConfig.Audience := TAudience(Btn.Tag);
end;
```

#### 状态选择�?×2 网格�?
```
选项: 😌 踏实 | 🔥 有点�?| 😪 累但�?| 🎯 专注
```

实现同受众选择，逻辑相同�?
#### 风格选择�?色块�?
```
深绿 #0D5C4A | 极简�?渐变 | 暗夜 #0A0F0E | 深森 渐变
```

实现�?�?`TRectangle`（高�?32px），`Fill.Color` 设对应色，选中时加白色边框�?.5px）�?
#### 操作按钮

```
[🎲 换一句话]  �?轮廓样式
[生成卡片]     �?实心样式，背�?#0D5C4A
```

### 5.3 卡片预览控件（TCardPreview�?
**类型**: 继承 `TControl`，重�?`Paint` 方法，完全自定义绘制�?
**尺寸**: 360×360px（代�?1080×1080 实际导出尺寸�?
```pascal
type
  TCardPreview = class(TControl)
  private
    FConfig: TCardConfig;
  protected
    procedure Paint; override;
  private
    procedure DrawBackground;
    procedure DrawGridPattern;
    procedure DrawTopRow;
    procedure DrawCenter;
    procedure DrawStats;
    procedure DrawBottom;
  public
    property Config: TCardConfig read FConfig write SetConfig;
    procedure Refresh;
  end;
```

#### Paint 方法调用顺序

```pascal
procedure TCardPreview.Paint;
begin
  Canvas.BeginScene;
  try
    DrawBackground;    // 1. 背景�?+ 圆角裁切
    DrawGridPattern;   // 2. 网格纹理
    DrawDecoration;    // 3. 装饰圆环 / 光晕
    DrawTopRow;        // 4. 顶部品牌�?    DrawCenter;        // 5. 中部主体（图�?+ 标题 + 副标题）
    DrawStats;         // 6. 三列统计数字
    DrawBottom;        // 7. 底部模块�?+ 封存徽章
  finally
    Canvas.EndScene;
  end;
end;
```

#### 背景绘制（各主题�?
```pascal
procedure TCardPreview.DrawBackground;
var
  R: TRectF;
begin
  R := LocalRect;
  Canvas.Fill.Kind := TBrushKind.Solid;

  case FConfig.Theme of
    ctDark:
      Canvas.Fill.Color := StringToAlphaColor('#FF0D5C4A');
    ctLight:
      Canvas.Fill.Color := StringToAlphaColor('#FFF7F9F8');
    ctNight:
      Canvas.Fill.Color := StringToAlphaColor('#FF0A0F0E');
    ctWarm:
      begin
        // 渐变背景
        Canvas.Fill.Kind := TBrushKind.Gradient;
        Canvas.Fill.Gradient.Style := TGradientStyle.Linear;
        Canvas.Fill.Gradient.Color  := StringToAlphaColor('#FF1A3C34');
        Canvas.Fill.Gradient.Color1 := StringToAlphaColor('#FF0D5C4A');
      end;
  end;

  Canvas.FillRect(R, 18, 18, AllCorners, 1.0);
end;
```

#### 网格纹理绘制

```pascal
procedure TCardPreview.DrawGridPattern;
const
  GRID_SIZE = 28;
var
  x, y: Single;
  GridColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    GridColor := $0A0D5C4A   // rgba(13,92,74,0.04)
  else
    GridColor := $0A00E5A0;  // rgba(0,229,160,0.04)

  Canvas.Stroke.Color := GridColor;
  Canvas.Stroke.Thickness := 1;

  x := 0;
  while x <= Width do
  begin
    Canvas.DrawLine(PointF(x, 0), PointF(x, Height), 1.0);
    x := x + GRID_SIZE;
  end;

  y := 0;
  while y <= Height do
  begin
    Canvas.DrawLine(PointF(0, y), PointF(Width, y), 1.0);
    y := y + GRID_SIZE;
  end;
end;
```

#### 标题文字绘制

```pascal
procedure TCardPreview.DrawCenter;
var
  TextRect: TRectF;
  HeadlineLines: TArray<string>;
begin
  // 图标
  Canvas.Font.Size := 20;
  TextRect := RectF(26, 90, 90, 140);
  Canvas.FillText(TextRect, FConfig.Icon, False, 1.0, [], TTextAlign.Leading);

  // Tag 标签
  Canvas.Font.Size := 9;
  Canvas.Font.Family := 'Courier New';  // Mono 替代
  Canvas.Fill.Color := GetTagColor;
  TextRect := RectF(26, 148, Width - 26, 162);
  Canvas.FillText(TextRect, UpperCase(FConfig.Tag), False, 1.0, [], TTextAlign.Leading);

  // 大标题（衬线字体，斜体，多行�?  Canvas.Font.Size := 21;
  Canvas.Font.Style := [TFontStyle.fsItalic];
  Canvas.Font.Family := 'Georgia';  // FMX 衬线替代
  Canvas.Fill.Color := GetHeadlineColor;

  HeadlineLines := FConfig.Headline.Split([#10]);
  var LineY := 168.0;
  for var Line in HeadlineLines do
  begin
    TextRect := RectF(26, LineY, Width - 26, LineY + 26);
    Canvas.FillText(TextRect, Line, False, 1.0, [], TTextAlign.Leading);
    LineY := LineY + 26;
  end;

  // 副标�?  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  Canvas.Fill.Color := GetSubColor;
  TextRect := RectF(26, LineY + 4, Width - 26, LineY + 18);
  Canvas.FillText(TextRect, FConfig.SubText, False, 1.0, [], TTextAlign.Leading);
end;
```

#### 三列统计数字

```pascal
procedure TCardPreview.DrawStats;
const
  COL_W = 106.0;
  START_X = 26.0;
  START_Y = 270.0;
var
  i: Integer;
  Stats: array[0..2] of record Num, Label_: string; end;
  ColX: Single;
begin
  Stats[0].Num    := FConfig.StatPass;
  Stats[0].Label_ := '场景' + #10 + '通过';
  Stats[1].Num    := FConfig.StatMS;
  Stats[1].Label_ := '平均' + #10 + '响应';
  Stats[2].Num    := FConfig.StatCoverage;
  Stats[2].Label_ := '契约' + #10 + '覆盖';

  for i := 0 to 2 do
  begin
    ColX := START_X + i * COL_W;

    // 数字
    Canvas.Font.Size := 15;
    Canvas.Font.Family := 'Courier New';
    Canvas.Fill.Color := GetAccentColor;
    Canvas.FillText(RectF(ColX, START_Y, ColX + COL_W - 10, START_Y + 18),
                    Stats[i].Num, False, 1.0, [], TTextAlign.Leading);

    // 标签
    Canvas.Font.Size := 9;
    Canvas.Fill.Color := GetSubColor;
    Canvas.FillText(RectF(ColX, START_Y + 20, ColX + COL_W - 10, START_Y + 38),
                    Stats[i].Label_, False, 0.38, [], TTextAlign.Leading);

    // 分隔线（除最后一列）
    if i < 2 then
    begin
      Canvas.Stroke.Color := GetDividerColor;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawLine(PointF(ColX + COL_W - 10, START_Y),
                      PointF(ColX + COL_W - 10, START_Y + 36), 1.0);
    end;
  end;
end;
```

### 5.4 颜色辅助函数

```pascal
function TCardPreview.GetAccentColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    Result := StringToAlphaColor('#FF0D5C4A')
  else
    Result := StringToAlphaColor('#FF00E5A0');
end;

function TCardPreview.GetHeadlineColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    Result := StringToAlphaColor('#FF0F1F1A')
  else
    Result := TAlphaColors.White;
end;

function TCardPreview.GetTagColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    Result := StringToAlphaColor('#FF0D5C4A')
  else
    Result := StringToAlphaColor('#FF00E5A0');
end;

function TCardPreview.GetSubColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    Result := StringToAlphaColor('#FF0F1F1A')
  else
    Result := TAlphaColors.White;
end;

function TCardPreview.GetDividerColor: TAlphaColor;
begin
  if FConfig.Theme = ctLight then
    Result := $140D5C4A   // rgba(13,92,74,0.08)
  else
    Result := $28FFFFFF;  // rgba(255,255,255,0.16)
end;
```

### 5.5 生成逻辑

```pascal
procedure TFrameCardGenerator.GenerateCard;
var
  Entry: TSemanticEntry;
  Headlines: TArray<string>;
  Idx: Integer;
begin
  // 取语义条�?  Entry := SemanticLibrary[FConfig.Audience][FConfig.Mood];

  // 随机取一条标题（避免重复当前�?  Headlines := Entry.Headlines;
  repeat
    Idx := Random(Length(Headlines));
  until (Length(Headlines) <= 1) or (Headlines[Idx] <> FCardPreview.Config.Headline);

  // 更新配置
  FConfig.Icon       := Entry.Icon;
  FConfig.Tag        := Entry.Tag;
  FConfig.Headline   := Headlines[Idx];
  FConfig.SubText    := Entry.SubText;
  FConfig.ModuleName := edtModule.Text;

  // 刷新预览
  FCardPreview.Config := FConfig;
  FCardPreview.Repaint;
end;

procedure TFrameCardGenerator.ShuffleHeadline;
var
  Entry: TSemanticEntry;
  Headlines: TArray<string>;
  Others: TArray<string>;
  Idx: Integer;
begin
  Entry := SemanticLibrary[FConfig.Audience][FConfig.Mood];
  Headlines := Entry.Headlines;

  // 过滤掉当�?  Others := [];
  for var H in Headlines do
    if H <> FConfig.Headline then
      Others := Others + [H];

  if Length(Others) = 0 then Exit;

  Idx := Random(Length(Others));
  FConfig.Headline := Others[Idx];
  FCardPreview.Config := FConfig;
  FCardPreview.Repaint;
end;
```

---

## 6. 导出功能

### 6.1 导出 PNG

**原理**: �?`TCardPreview` 渲染�?`TBitmap`，然后保存�?
```pascal
procedure TFrameCardGenerator.ExportToPNG;
var
  Bmp: TBitmap;
  SaveDlg: TSaveDialog;
begin
  // 目标尺寸�?080×1080�?倍渲染，再缩放）
  Bmp := TBitmap.Create(1080, 1080);
  try
    Bmp.Canvas.BeginScene;
    try
      // 按比例缩放绘制（3× scale factor�?      Bmp.Canvas.SetMatrix(
        TMatrix.CreateScaling(3.0, 3.0)
      );
      FCardPreview.PaintTo(Bmp.Canvas);
    finally
      Bmp.Canvas.EndScene;
    end;

    SaveDlg := TSaveDialog.Create(nil);
    try
      SaveDlg.Filter := 'PNG 图片|*.png';
      SaveDlg.DefaultExt := 'png';
      SaveDlg.FileName := Format('DeepDevLite_%s_%s',
        [FormatDateTime('yyyymmdd', Now), FConfig.ModuleName]);
      if SaveDlg.Execute then
        Bmp.SaveToFile(SaveDlg.FileName);
    finally
      SaveDlg.Free;
    end;
  finally
    Bmp.Free;
  end;
end;
```

> **注意**: FMX �?`TBitmap.Canvas` 使用硬件加速，`PaintTo` 需确保在主线程调用�?
### 6.2 导出 PDF（验证报告）

**推荐方案**: 使用 Skia4Delphi �?FastReport�?
若使�?**Skia4Delphi**（开源，推荐）：

```pascal
uses
  Skia, Skia.FMX;

procedure TFrameReport.ExportReportToPDF;
var
  PDFDoc  : ISkDocument;
  Canvas  : ISkCanvas;
  Stream  : TFileStream;
  SaveDlg : TSaveDialog;
  PageW, PageH: Single;
begin
  PageW := 680;
  PageH := 900;  // 根据内容动态计�?
  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.Filter := 'PDF 文件|*.pdf';
    SaveDlg.DefaultExt := 'pdf';
    SaveDlg.FileName := Format('DeepDevLite_Report_%s', [FReport.ReportID]);
    if not SaveDlg.Execute then Exit;
  finally
    SaveDlg.Free;
  end;

  Stream := TFileStream.Create(SaveDlg.FileName, fmCreate);
  try
    PDFDoc := TSkDocument.MakePDF(Stream);
    Canvas := PDFDoc.BeginPage(PageW, PageH);
    try
      // �?Canvas 上绘制报告内�?      DrawReportToSkiaCanvas(Canvas, PageW, PageH);
    finally
      PDFDoc.EndPage;
      PDFDoc.Close;
    end;
  finally
    Stream.Free;
  end;
end;
```

**DrawReportToSkiaCanvas** 按报告各区域逐块绘制，参照第 4 节的布局规格�?
### 6.3 卡片导出 PDF（朋友圈卡）

```pascal
procedure TFrameCardGenerator.ExportCardToPDF;
// 原理同上，页面尺寸设为正方形 360×360（或 1080×1080 点）
// �?Skia Canvas 上调�?TCardPreview.PaintToSkia(Canvas)
// 单页 PDF，居中输�?begin
  // �?ExportReportToPDF，页面尺�?360×360
  // 内容调用 FCardPreview.PaintTo �?Skia 版本
end;
```

---

## 7. 语义库完整数�?
语义库定义为二维数组，索引为 `[TAudience][TMood]`�?
```pascal
// 初始化语义库（在 FormCreate 或单�?initialization 中调用）
procedure InitSemanticLibrary;
begin
  // ── 女朋�?──
  SemanticLib[auGirlfriend][mdSatisfied].Icon := '💕';
  SemanticLib[auGirlfriend][mdSatisfied].Tag  := '�?功能已验证交�?;
  SemanticLib[auGirlfriend][mdSatisfied].SubText := 'Verified · 你别担心�?;
  SemanticLib[auGirlfriend][mdSatisfied].Headlines := [
    '今天加班�? + #10 + '但这个功能稳�?,
    '熬夜也值了�? + #10 + '这个跑过�?,
    '你别等我�? + #10 + '我把这个封存完就�?,
    '不是在摸鱼，' + #10 + '是在验证',
    '今晚做了一�? + #10 + '有证明的�?,
    '搞定了，' + #10 + '有报告为�?,
    '这次交出去的' + #10 + '东西我放�?
  ];

  SemanticLib[auGirlfriend][mdProud].Icon := '🔥';
  SemanticLib[auGirlfriend][mdProud].Tag  := '�?又拿下一�?;
  SemanticLib[auGirlfriend][mdProud].SubText := 'Sealed · 等你夸我';
  SemanticLib[auGirlfriend][mdProud].Headlines := [
    '一个人搞定了，' + #10 + '等你�?,
    '这个难点�? + #10 + '今天解决�?,
    '别人靠感觉，' + #10 + '我有验证报告',
    '又一个功能，' + #10 + '有证据地拿下�?,
    '今天效率很高�? + #10 + '你猜猜做了什�?
  ];

  SemanticLib[auGirlfriend][mdTired].Icon := '😌';
  SemanticLib[auGirlfriend][mdTired].Tag  := '�?今晚收工';
  SemanticLib[auGirlfriend][mdTired].SubText := 'ODD certified · 回家�?;
  SemanticLib[auGirlfriend][mdTired].Headlines := [
    '累，但交出去' + #10 + '的东西是干净�?,
    '熬完了，' + #10 + '这次没有遗憾',
    '今晚加班也值了�? + #10 + '功能验证通过',
    '做完了，' + #10 + '可以睡了',
    '辛苦也好�? + #10 + '出了问题再返�?
  ];

  SemanticLib[auGirlfriend][mdFocused].Icon := '🎯';
  SemanticLib[auGirlfriend][mdFocused].Tag  := '�?专注出成�?;
  SemanticLib[auGirlfriend][mdFocused].SubText := 'Verified & sealed';
  SemanticLib[auGirlfriend][mdFocused].Headlines := [
    '今天没分心，' + #10 + '一个功能，做完做好',
    '手机都没看，' + #10 + '这个就出来了',
    '专注的两小时' + #10 + '比摸鱼的一天强',
    '进入状态的感觉' + #10 + '就是这样'
  ];

  // ── 老板 ──
  SemanticLib[auBoss][mdSatisfied].Icon := '�?;
  SemanticLib[auBoss][mdSatisfied].Tag  := '�?交付物已验证';
  SemanticLib[auBoss][mdSatisfied].SubText := 'All scenarios passed · ODD certified';
  SemanticLib[auBoss][mdSatisfied].Headlines := [
    '登录模块' + #10 + '验证通过，可上线',
    '今日交付�? + #10 + '验证报告已出',
    '所有场景通过�? + #10 + '可以提审�?,
    '功能完成�? + #10 + '有据可查',
    '按时按质�? + #10 + '报告已封�?
  ];

  SemanticLib[auBoss][mdProud].Icon := '📊';
  SemanticLib[auBoss][mdProud].Tag  := '�?质量有据可查';
  SemanticLib[auBoss][mdProud].SubText := 'Evidence sealed · Ready to review';
  SemanticLib[auBoss][mdProud].Headlines := [
    '3个场景，100%覆盖' + #10 + '有报告可存档',
    '不是感觉没问题，' + #10 + '是验证过没问�?,
    '这次交付' + #10 + '附带完整证据�?,
    '代码可以换，' + #10 + '验证结果封存�?
  ];

  SemanticLib[auBoss][mdTired].Icon := '🛡�?;
  SemanticLib[auBoss][mdTired].Tag  := '�?今日交付';
  SemanticLib[auBoss][mdTired].SubText := 'Verified · Sealed · Delivered';
  SemanticLib[auBoss][mdTired].Headlines := [
    '功能完成�? + #10 + '验证通过，报告已�?,
    '加班也要�? + #10 + '可交付的东西',
    '今天的成�? + #10 + '有报告为�?,
    '晚了�? + #10 + '但东西是对的'
  ];

  SemanticLib[auBoss][mdFocused].Icon := '🔒';
  SemanticLib[auBoss][mdFocused].Tag  := '�?封存完毕';
  SemanticLib[auBoss][mdFocused].SubText := 'Contract fulfilled · Sealed';
  SemanticLib[auBoss][mdFocused].Headlines := [
    '今日任务完成' + #10 + '所有验收条件通过',
    '契约已履行，' + #10 + '结果已封�?,
    '按契约交付，' + #10 + '无遗�?,
    '今天做的�? + #10 + '明天可以复盘'
  ];

  // ── 同行 ──
  SemanticLib[auPeer][mdSatisfied].Icon := '�?;
  SemanticLib[auPeer][mdSatisfied].Tag  := '�?ODD闭环完成';
  SemanticLib[auPeer][mdSatisfied].SubText := 'Output-Driven · Not code-driven';
  SemanticLib[auPeer][mdSatisfied].Headlines := [
    '契约→验证→封存' + #10 + '今天又走了一�?,
    '不审代码�? + #10 + '只验产出�?,
    'AI写的代码' + #10 + '我用功能测试�?,
    '代码是负债，' + #10 + '产出物才是资�?,
    '这次的交�? + #10 + '有证据链撑着'
  ];

  SemanticLib[auPeer][mdProud].Icon := '🧪';
  SemanticLib[auPeer][mdProud].Tag  := '�?输出驱动验证';
  SemanticLib[auPeer][mdProud].SubText := 'ODD certified · 3/3 passed';
  SemanticLib[auPeer][mdProud].Headlines := [
    '不审查代码，' + #10 + '只验证产出物',
    'AI幻觉�? + #10 + '功能测试一跑就知道',
    '代码谁写的不重要�? + #10 + '跑过了才算数',
    '这才�? + #10 + 'AI原生开�?
  ];

  SemanticLib[auPeer][mdTired].Icon := '🔗';
  SemanticLib[auPeer][mdTired].Tag  := '�?证据链完�?;
  SemanticLib[auPeer][mdTired].SubText := 'Evidence sealed · Tamper-proof';
  SemanticLib[auPeer][mdTired].Headlines := [
    'SHA-256封存�? + #10 + '可追溯，可审�?,
    '有哈希，有时间戳�? + #10 + '有验证记�?,
    '改了也不怕，' + #10 + '历史版本都在',
    '今晚封存�? + #10 + '明天可以继续'
  ];

  SemanticLib[auPeer][mdFocused].Icon := '🏭';
  SemanticLib[auPeer][mdFocused].Tag  := '�?软件工厂产出';
  SemanticLib[auPeer][mdFocused].SubText := 'DeepDevLite · ODD native';
  SemanticLib[auPeer][mdFocused].Headlines := [
    'AI生成�? + #10 + '人类验收，机器封�?,
    '用ODD的方�? + #10 + '做完了这一�?,
    '今天没有' + #10 + '靠感觉上线的代码',
    '方法论有效，' + #10 + '这次是证�?
  ];

  // ── 自我满足 ──
  SemanticLib[auSelf][mdSatisfied].Icon := '�?;
  SemanticLib[auSelf][mdSatisfied].Tag  := '�?今日完成';
  SemanticLib[auSelf][mdSatisfied].SubText := 'Verified · Sealed · Done';
  SemanticLib[auSelf][mdSatisfied].Headlines := [
    '又一个功能，' + #10 + '有证据地交出去了',
    '今天做的�? + #10 + '我自己放�?,
    '这次不是' + #10 + '靠运气过�?,
    '做完了，' + #10 + '而且做对�?,
    '今天也值了',
    '心里有底�? + #10 + '这就够了',
    '加班也值了�? + #10 + '这个功能稳了'
  ];

  SemanticLib[auSelf][mdProud].Icon := '🌟';
  SemanticLib[auSelf][mdProud].Tag  := '�?拿下�?;
  SemanticLib[auSelf][mdProud].SubText := 'ODD certified · I know it works';
  SemanticLib[auSelf][mdProud].Headlines := [
    '心里有底�? + #10 + '这次不是靠运�?,
    '今天有点' + #10 + '超出自己预期',
    '这个难，' + #10 + '但做完了',
    '进展比预期快�? + #10 + '而且质量�?,
    '这种感觉�? + #10 + '就是为了�?
  ];

  SemanticLib[auSelf][mdTired].Icon := '🌙';
  SemanticLib[auSelf][mdTired].Tag  := '�?值得的一�?;
  SemanticLib[auSelf][mdTired].SubText := 'Sealed · Worth it';
  SemanticLib[auSelf][mdTired].Headlines := [
    '累，但做的东�? + #10 + '是真的验证过�?,
    '今天加班也值了',
    '辛苦是真的，' + #10 + '成果也是真的',
    '熬了，但没白�?,
    '累也好过' + #10 + '明天返工'
  ];

  SemanticLib[auSelf][mdFocused].Icon := '🎯';
  SemanticLib[auSelf][mdFocused].Tag  := '�?深度完成';
  SemanticLib[auSelf][mdFocused].SubText := 'Contract �?Verify �?Seal · Done';
  SemanticLib[auSelf][mdFocused].Headlines := [
    '没有绕过任何步骤�? + #10 + '结果在这�?,
    '今天没有' + #10 + '走捷�?,
    '一步一步来�? + #10 + '这才叫做�?,
    '认真对待' + #10 + '每一个验收条�?,
    '方法对了�? + #10 + '结果自然�?
  ];
end;
```

---

## 8. UI 规范

### 8.1 颜色

| 名称 | 十六进制 | FMX AlphaColor | 用�?|
|------|---------|----------------|------|
| Brand | `#0D5C4A` | `$FF0D5C4A` | 主色，按钮，Header |
| Brand Light | `#0F6E58` | `$FF0F6E58` | 悬停状�?|
| Accent | `#00E5A0` | `$FF00E5A0` | 高亮，数字，徽章 |
| Accent Dim | �?| `$1E00E5A0` | 浅绿背景�?2% 透明�?|
| BG | `#F0F4F2` | `$FFF0F4F2` | 窗口背景 |
| Surface | `#FFFFFF` | `$FFFFFFFF` | 卡片/面板背景 |
| Border | `#E0E8E4` | `$FFE0E8E4` | 边框�?|
| Text | `#0F1F1A` | `$FF0F1F1A` | 主文�?|
| Muted | `#7A9088` | `$FF7A9088` | 次要文字 |
| Pass Green | `#0A7A56` | `$FF0A7A56` | PASS 徽章文字 |
| Fail Red | `#EF4444` | `$FFEF4444` | FAIL 徽章文字 |
| Night BG | `#0A0F0E` | `$FF0A0F0E` | 暗夜主题背景 |

### 8.2 字体

| 用�?| FMX 设置 | 备注 |
|------|----------|------|
| 等宽/标签 | `'Courier New'`，Size 按需 | Mono 替代 |
| 衬线/大标�?| `'Georgia'`，Italic | Serif 替代 |
| 主体/按钮 | FMX 默认系统字体 | Sans-serif |
| 中文 | 系统默认（PingFang/微软雅黑�?| 无需额外设置 |

### 8.3 圆角半径

| 元素 | 圆角 |
|------|------|
| 卡片主体 | 18px |
| 报告容器 | 16px |
| 场景卡片 | 8px |
| 按钮 | 8px |
| 品牌标识方块 | 6px |
| 风格色块 | 7px |
| 徽章（PASS/FAIL�?| 4px |
| 封存徽章 | 100px（胶囊） |

### 8.4 间距规范

| 层级 | �?|
|------|----|
| 区域内边距（大） | 28px 40px |
| 区域内边距（小） | 20px 40px |
| 控件组间�?| 20px |
| 列表项间�?| 8px |
| 标签到控�?| 6px |
| 按钮内边�?| 9px 18px |

---

## 附录：开发顺序建�?
1. **第一�?* �?建立数据模型（`TVerificationReport`，`TCardConfig`，`TSemanticEntry`�?2. **第二�?* �?实现 `InitSemanticLibrary`，将语义库硬编码初始�?3. **第三�?* �?实现 `TCardPreview` 自定义控件，先做 Dark 主题，跑通绘制流�?4. **第四�?* �?实现控制面板 UI + 生成逻辑 + 换一句逻辑
5. **第五�?* �?实现 PNG 导出
6. **第六�?* �?实现验证报告 Frame（静态布局先，后接数据�?7. **第七�?* �?实现 PDF 导出（引�?Skia4Delphi�?8. **第八�?* �?补全四种主题，联调细�?