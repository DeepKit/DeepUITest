unit DeepFrames.Workflow.VideoCompiler;

/// <summary>
/// Video IR compiler utility — generates video_ir timelines, lint results,
/// and render metrics without embedding fake data in workflow code.
///
/// In Phase 5 (real HyperFrames integration), these methods become workers
/// that call the HyperFrames CLI/API. Until then, they produce deterministic
/// stub data for pipeline validation.
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  TVideoCompiler = class
  public
    /// <summary>Compile a Video IR timeline from shot_document, audio_manifest,
    /// and platform spec into a JSON scene array.</summary>
    class function CompileTimeline(const ShotDocumentId, AudioManifestId,
      PlatformSpecId: string): string; static;

    /// <summary>Lint a compiled Video IR timeline. Returns JSON with
    /// warnings/errors counts.</summary>
    class function Lint(const TimelineJson, PlatformSpecId: string): string; static;

    /// <summary>Return fake render metrics JSON for a completed render job.</summary>
    class function RenderMetrics(const RenderBackend: string;
      DurationSec: Double): string; static;

    /// <summary>Compute estimated duration for the timeline from scene data.</summary>
    class function EstimateDuration(const TimelineJson: string): Double; static;

    /// <summary>Count scenes in the timeline.</summary>
    class function CountScenes(const TimelineJson: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Shared.Consts;

class function TVideoCompiler.CompileTimeline(const ShotDocumentId,
  AudioManifestId, PlatformSpecId: string): string;
var
  Arr: TJSONArray;
  Scene: TJSONObject;
begin
  Arr := TJSONArray.Create;
  try
    Scene := TJSONObject.Create;
    Scene.AddPair('scene_id', 'scene_001');
    Scene.AddPair('template', 'narration');
    Scene.AddPair('duration_sec', TJSONNumber.Create(3.5));
    Scene.AddPair('layers', TJSONObject.Create
      .AddPair('background', TJSONObject.Create
        .AddPair('type', 'image')
        .AddPair('prompt', 'A calm study room with warm lighting'))
      .AddPair('subtitle', TJSONObject.Create
        .AddPair('text', 'First subtitle line')
        .AddPair('position', 'bottom_center')));
    Scene.AddPair('transitions', TJSONObject.Create
      .AddPair('in', 'fade')
      .AddPair('out', 'fade'));
    Arr.AddElement(Scene);

    Scene := TJSONObject.Create;
    Scene.AddPair('scene_id', 'scene_002');
    Scene.AddPair('template', 'narration');
    Scene.AddPair('duration_sec', TJSONNumber.Create(4.0));
    Scene.AddPair('layers', TJSONObject.Create
      .AddPair('background', TJSONObject.Create
        .AddPair('type', 'image')
        .AddPair('prompt', 'Mountain landscape at dawn'))
      .AddPair('subtitle', TJSONObject.Create
        .AddPair('text', 'Second subtitle line')
        .AddPair('position', 'bottom_center')));
    Scene.AddPair('transitions', TJSONObject.Create
      .AddPair('in', 'crossfade')
      .AddPair('out', 'fade'));
    Arr.AddElement(Scene);

    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

class function TVideoCompiler.Lint(const TimelineJson,
  PlatformSpecId: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('passed', TJSONBool.Create(True));
    Obj.AddPair('warnings', TJSONArray.Create);
    Obj.AddPair('errors', TJSONArray.Create);
    Obj.AddPair('checked_layers', TJSONNumber.Create(4));
    Obj.AddPair('safe_zone_violations', TJSONNumber.Create(0));
    Obj.AddPair('platform_spec_id', PlatformSpecId);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TVideoCompiler.RenderMetrics(const RenderBackend: string;
  DurationSec: Double): string;
var
  Obj: TJSONObject;
  FrameCount: Integer;
begin
  FrameCount := Round(DurationSec * 30);
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('render_backend', RenderBackend);
    Obj.AddPair('frames_rendered', TJSONNumber.Create(FrameCount));
    Obj.AddPair('render_time_ms', TJSONNumber.Create(Round(DurationSec * 427)));
    Obj.AddPair('output_width', TJSONNumber.Create(1920));
    Obj.AddPair('output_height', TJSONNumber.Create(1080));
    Obj.AddPair('output_fps', TJSONNumber.Create(30));
    Obj.AddPair('output_codec', 'h264');
    Obj.AddPair('file_size_bytes', TJSONNumber.Create(Round(DurationSec * 699051)));
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

end.