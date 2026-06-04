unit DeepFrames.Workflow.VideoCompiler;

/// <summary>
/// Video IR compiler — generates video_ir timelines, lint results,
/// and render metrics. Supports multi-aspect-ratio output for P7.4
/// (16:9 horizontal, 9:16 vertical, 3:4, 1:1).
///
/// In Phase 5 (real HyperFrames integration), these methods become workers
/// that call the HyperFrames CLI/API. Until then, they produce deterministic
/// stub data for pipeline validation.
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  /// <summary>Aspect ratio descriptor — width + height + fps.</summary>
  TVideoAspect = record
    Width: Integer;
    Height: Integer;
    Fps: Double;
    AspectLabel: string;  // '16:9', '9:16', '3:4', '1:1'
    function IsVertical: Boolean;
    function IsHorizontal: Boolean;
    function IsSquare: Boolean;
  end;

  TVideoCompiler = class
  public
    /// <summary>Predefined aspect ratios.</summary>
    class function Aspect16x9: TVideoAspect; static;
    class function Aspect9x16: TVideoAspect; static;
    class function Aspect3x4: TVideoAspect; static;
    class function Aspect1x1: TVideoAspect; static;

    /// <summary>Build a TVideoAspect from a TPlatformSpec.</summary>
    class function AspectFromSpec(const ASpec: TPlatformSpec): TVideoAspect; static;

    /// <summary>Compile a Video IR timeline into a JSON scene array.</summary>
    class function CompileTimeline(const ShotDocumentId, AudioManifestId: string;
      const AAspect: TVideoAspect): string; static;

    /// <summary>Lint a compiled Video IR timeline. Returns JSON with
    /// warnings/errors counts.</summary>
    class function Lint(const TimelineJson: string;
      const AAspect: TVideoAspect): string; static;

    /// <summary>Return render metrics JSON for a completed render job.</summary>
    class function RenderMetrics(const RenderBackend: string;
      DurationSec: Double; const AAspect: TVideoAspect): string; static;

    /// <summary>Compute estimated duration for the timeline from scene data.</summary>
    class function EstimateDuration(const TimelineJson: string): Double; static;

    /// <summary>Count scenes in the timeline.</summary>
    class function CountScenes(const TimelineJson: string): Integer; static;

    /// <summary>Estimate output file size based on aspect ratio and duration.</summary>
    class function EstimateFileSize(DurationSec: Double;
      const AAspect: TVideoAspect): Int64; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Shared.Consts;

{ TVideoAspect }

function TVideoAspect.IsVertical: Boolean;
begin
  Result := Height > Width;
end;

function TVideoAspect.IsHorizontal: Boolean;
begin
  Result := Width > Height;
end;

function TVideoAspect.IsSquare: Boolean;
begin
  Result := Width = Height;
end;

{ TVideoCompiler }

class function TVideoCompiler.Aspect16x9: TVideoAspect;
begin
  Result.Width := 1920;
  Result.Height := 1080;
  Result.Fps := 30;
  Result.AspectLabel := '16:9';
end;

class function TVideoCompiler.Aspect9x16: TVideoAspect;
begin
  Result.Width := 1080;
  Result.Height := 1920;
  Result.Fps := 30;
  Result.AspectLabel := '9:16';
end;

class function TVideoCompiler.Aspect3x4: TVideoAspect;
begin
  Result.Width := 1080;
  Result.Height := 1440;
  Result.Fps := 30;
  Result.AspectLabel := '3:4';
end;

class function TVideoCompiler.Aspect1x1: TVideoAspect;
begin
  Result.Width := 1080;
  Result.Height := 1080;
  Result.Fps := 30;
  Result.AspectLabel := '1:1';
end;

class function TVideoCompiler.AspectFromSpec(const ASpec: TPlatformSpec): TVideoAspect;
begin
  Result.Width := ASpec.Width;
  Result.Height := ASpec.Height;
  Result.Fps := ASpec.Fps;
  if ASpec.AspectRatio <> '' then
    Result.AspectLabel := ASpec.AspectRatio
  else if (Result.Width = 1920) and (Result.Height = 1080) then
    Result.AspectLabel := '16:9'
  else if (Result.Width = 1080) and (Result.Height = 1920) then
    Result.AspectLabel := '9:16'
  else if (Result.Width = 1080) and (Result.Height = 1440) then
    Result.AspectLabel := '3:4'
  else
    Result.AspectLabel := Format('%d:%d', [Result.Width, Result.Height]);
end;

class function TVideoCompiler.CompileTimeline(const ShotDocumentId,
  AudioManifestId: string; const AAspect: TVideoAspect): string;
var
  Arr: TJSONArray;
  Scene: TJSONObject;

  function MakeScene(const AId: string; ADur: Double;
    const ATemplate, ABgPrompt, ASubtitle, ATransition: string): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('scene_id', AId);
    Result.AddPair('template', ATemplate);
    Result.AddPair('duration_sec', TJSONNumber.Create(ADur));
    var Layers := TJSONObject.Create
      .AddPair('background', TJSONObject.Create
        .AddPair('type', 'image')
        .AddPair('prompt', ABgPrompt));
    if ASubtitle <> '' then
      Layers.AddPair('subtitle', TJSONObject.Create
        .AddPair('text', ASubtitle)
        .AddPair('position', 'bottom_center'));
    Result.AddPair('layers', Layers);
    Result.AddPair('transitions', TJSONObject.Create
      .AddPair('in', ATransition)
      .AddPair('out', 'fade'));
  end;
begin
  Arr := TJSONArray.Create;
  try
    // Scene 1 — warm indoor
    Arr.AddElement(MakeScene('scene_001', 3.5, 'narration',
      'A calm study room with warm lighting', 'First subtitle line', 'fade'));
    // Scene 2 — landscape
    Arr.AddElement(MakeScene('scene_002', 4.0, 'narration',
      'Mountain landscape at dawn', 'Second subtitle line', 'crossfade'));

    // Scene 3 — close-up (vertical-aware: tighter framing)
    if AAspect.IsVertical then
      Arr.AddElement(MakeScene('scene_003', 3.0, 'closeup',
        'Close-up portrait shot, centered, soft bokeh background',
        'Third subtitle line', 'fade'))
    else
      Arr.AddElement(MakeScene('scene_003', 3.0, 'narration',
        'Wide angle city skyline at sunset',
        'Third subtitle line', 'fade'));

    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

class function TVideoCompiler.Lint(const TimelineJson: string;
  const AAspect: TVideoAspect): string;
var
  Obj: TJSONObject;
  SceneCount: Integer;
begin
  SceneCount := CountScenes(TimelineJson);
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('passed', TJSONBool.Create(True));
    Obj.AddPair('warnings', TJSONArray.Create);
    Obj.AddPair('errors', TJSONArray.Create);
    Obj.AddPair('checked_layers', TJSONNumber.Create(SceneCount * 2)); // bg + sub per scene
    Obj.AddPair('safe_zone_violations', TJSONNumber.Create(0));
    Obj.AddPair('aspect', AAspect.AspectLabel);
    Obj.AddPair('canvas', TJSONObject.Create
      .AddPair('width', TJSONNumber.Create(AAspect.Width))
      .AddPair('height', TJSONNumber.Create(AAspect.Height)));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TVideoCompiler.RenderMetrics(const RenderBackend: string;
  DurationSec: Double; const AAspect: TVideoAspect): string;
var
  Obj: TJSONObject;
  FrameCount: Integer;
  PixelsPerFrame: Int64;
  BitrateKbps: Integer;
  EstimatedSize: Int64;
begin
  FrameCount := Round(DurationSec * AAspect.Fps);

  // Bitrate scales with pixel count
  PixelsPerFrame := Int64(AAspect.Width) * AAspect.Height;
  if PixelsPerFrame > 2000000 then
    BitrateKbps := 8000   // 1920×1080+
  else if PixelsPerFrame > 1500000 then
    BitrateKbps := 6000   // 1080×1440
  else
    BitrateKbps := 5000;  // 1080×1080

  // File size = bitrate × duration / 8
  EstimatedSize := Round(DurationSec * BitrateKbps * 1000 / 8);

  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('render_backend', RenderBackend);
    Obj.AddPair('frames_rendered', TJSONNumber.Create(FrameCount));
    Obj.AddPair('render_time_ms', TJSONNumber.Create(Round(DurationSec * 427)));
    Obj.AddPair('output_width', TJSONNumber.Create(AAspect.Width));
    Obj.AddPair('output_height', TJSONNumber.Create(AAspect.Height));
    Obj.AddPair('output_fps', TJSONNumber.Create(AAspect.Fps));
    Obj.AddPair('output_codec', 'h264');
    Obj.AddPair('bitrate_kbps', TJSONNumber.Create(BitrateKbps));
    Obj.AddPair('file_size_bytes', TJSONNumber.Create(EstimatedSize));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TVideoCompiler.EstimateDuration(const TimelineJson: string): Double;
var
  Arr: TJSONArray;
  Total: Double;
  I: Integer;
  Scene: TJSONObject;
begin
  Total := 0;
  Arr := TJSONObject.ParseJSONValue(TimelineJson) as TJSONArray;
  if Arr <> nil then
  try
    for I := 0 to Arr.Count - 1 do
    begin
      Scene := Arr.Items[I] as TJSONObject;
      if Scene <> nil then
        Total := Total + Scene.GetValue<Double>('duration_sec');
    end;
  finally
    Arr.Free;
  end;
  Result := Total;
end;

class function TVideoCompiler.CountScenes(const TimelineJson: string): Integer;
var
  Arr: TJSONArray;
begin
  Result := 0;
  Arr := TJSONObject.ParseJSONValue(TimelineJson) as TJSONArray;
  if Arr <> nil then
  try
    Result := Arr.Count;
  finally
    Arr.Free;
  end;
end;

class function TVideoCompiler.EstimateFileSize(DurationSec: Double;
  const AAspect: TVideoAspect): Int64;
var
  Pixels: Int64;
  BitrateKbps: Integer;
begin
  Pixels := Int64(AAspect.Width) * AAspect.Height;
  if Pixels > 2000000 then BitrateKbps := 8000
  else if Pixels > 1500000 then BitrateKbps := 6000
  else BitrateKbps := 5000;
  Result := Round(DurationSec * BitrateKbps * 1000 / 8);
end;

end.