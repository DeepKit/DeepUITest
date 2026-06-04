/**
 * Video IR contract types — must stay in sync with Delphi
 * DeepFrames.Workflow.VideoCompiler output format.
 *
 * These types are read-only from the worker's perspective.
 * The worker consumes request.json → Video IR → renders → writes result.json.
 */

export interface VideoIRScene {
  scene_id: string;
  template: 'narration' | 'dialogue' | 'action' | 'title' | 'subtitle_only';
  duration_sec: number;
  layers: {
    background: {
      type: 'image';
      prompt: string;
    };
    subtitle?: {
      text: string;
      position: 'bottom_center' | 'top_center' | 'center';
    };
  };
  transitions: {
    in: string;   // 'fade' | 'crossfade' | 'cut'
    out: string;
  };
}

export interface WorkerRequest {
  schema_version: string;
  task_id: string;
  task_type: string;
  input_manifest: string;
  output_dir: string;
  params: string;       // JSON: { width, height, fps, video_codec, audio_codec }
}

export interface RenderParams {
  width: number;
  height: number;
  fps: number;
  video_codec: string;
  audio_codec: string;
  output_file: string;
}

export interface WorkerResult {
  task_id: string;
  success: boolean;
  output_files: string[];
  metrics: string;
  error_message: string;
  duration_ms: number;
  completed_at: string;
}

export interface WorkerProgress {
  task_id: string;
  status: 'running' | 'done' | 'failed' | 'cancelled';
  progress_percent: number;
  current_step: string;
  message: string;
  files_produced: string[];
  updated_at: string;
}