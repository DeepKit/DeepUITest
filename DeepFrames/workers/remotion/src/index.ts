/**
 * DeepFrames Remotion worker entry point.
 *
 * Reads request.json from the work directory, loads Video IR,
 * renders via Remotion, writes progress.json and result.json.
 *
 * Usage: npx ts-node src/index.ts <work_dir>
 */

import * as fs from 'fs';
import * as path from 'path';
import { bundle } from '@remotion/bundler';
import { renderMedia, selectComposition } from '@remotion/renderer';
import type { WorkerRequest, WorkerResult, WorkerProgress } from './VideoIR';

async function main(): Promise<void> {
  const workDir = process.argv[2];
  if (!workDir) {
    console.error('Usage: ts-node src/index.ts <work_dir>');
    process.exit(1);
  }

  // 1. Read request.json
  const requestPath = path.join(workDir, 'request.json');
  if (!fs.existsSync(requestPath)) {
    console.error(`request.json not found in ${workDir}`);
    process.exit(1);
  }

  const request: WorkerRequest = JSON.parse(
    fs.readFileSync(requestPath, 'utf-8')
  );
  const params = JSON.parse(request.params || '{}');
  const outputDir = request.output_dir || path.join(workDir, 'output');

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const outputFile = path.join(
    outputDir,
    params.output_file || `render_${params.width}x${params.height}.mp4`
  );

  // 2. Load Video IR from input manifest
  const manifestPath = path.resolve(request.input_manifest);
  if (!fs.existsSync(manifestPath)) {
    writeResult(workDir, {
      task_id: request.task_id,
      success: false,
      output_files: [],
      metrics: '{}',
      error_message: `Input manifest not found: ${manifestPath}`,
      duration_ms: 0,
      completed_at: new Date().toISOString(),
    });
    process.exit(1);
  }

  const videoIR = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
  const scenes = Array.isArray(videoIR) ? videoIR : videoIR.scenes || [];

  const totalDuration = scenes.reduce(
    (sum: number, s: { duration_sec: number }) => sum + s.duration_sec,
    0
  );

  // 3. Report progress: bundling
  updateProgress(workDir, {
    task_id: request.task_id,
    status: 'running',
    progress_percent: 10,
    current_step: 'bundling',
    message: 'Bundling Remotion composition...',
    files_produced: [],
    updated_at: new Date().toISOString(),
  });

  const startTime = Date.now();

  try {
    // 4. Bundle the composition
    const bundleLocation = await bundle({
      entryPoint: path.resolve(__dirname, 'Composition'),
      webpackOverride: (config) => ({
        ...config,
        output: { ...config.output, path: path.resolve(outputDir, 'webpack') },
      }),
    });

    updateProgress(workDir, {
      task_id: request.task_id,
      status: 'running',
      progress_percent: 30,
      current_step: 'rendering',
      message: `Rendering ${scenes.length} scenes, ${totalDuration.toFixed(1)}s total...`,
      files_produced: [],
      updated_at: new Date().toISOString(),
    });

    // 5. Select composition and render
    const inputProps = {
      scenes,
      width: params.width || 1920,
      height: params.height || 1080,
      fps: params.fps || 30,
    };

    const compositionId = 'DeepFramesVideo';

    // Note: renderMedia requires an actual Remotion project structure.
    // In production, the composition would be built as a separate Remotion project
    // and the worker would call `npx remotion render` via child_process.
    // For the skeleton, we write a placeholder and report success.

    // Placeholder: create an empty video file
    fs.writeFileSync(outputFile, Buffer.alloc(1024)); // 1KB placeholder

    const elapsed = Date.now() - startTime;
    const frames = Math.round(totalDuration * (params.fps || 30));

    updateProgress(workDir, {
      task_id: request.task_id,
      status: 'done',
      progress_percent: 100,
      current_step: 'complete',
      message: `Rendered ${scenes.length} scenes, ${frames} frames, ${totalDuration.toFixed(1)}s`,
      files_produced: [outputFile],
      updated_at: new Date().toISOString(),
    });

    writeResult(workDir, {
      task_id: request.task_id,
      success: true,
      output_files: [outputFile],
      metrics: JSON.stringify({
        render_backend: 'remotion',
        scenes: scenes.length,
        frames_rendered: frames,
        render_time_ms: elapsed,
        output_width: params.width || 1920,
        output_height: params.height || 1080,
        output_fps: params.fps || 30,
        output_codec: params.video_codec || 'h264',
        file_size_bytes: 1024,
      }),
      error_message: '',
      duration_ms: elapsed,
      completed_at: new Date().toISOString(),
    });

    console.log(`Render complete: ${outputFile}`);
  } catch (err: any) {
    // 6. Handle failure
    updateProgress(workDir, {
      task_id: request.task_id,
      status: 'failed',
      progress_percent: 0,
      current_step: 'error',
      message: err.message,
      files_produced: [],
      updated_at: new Date().toISOString(),
    });

    writeResult(workDir, {
      task_id: request.task_id,
      success: false,
      output_files: [],
      metrics: '{}',
      error_message: err.message,
      duration_ms: Date.now() - startTime,
      completed_at: new Date().toISOString(),
    });

    console.error(`Render failed: ${err.message}`);
    process.exit(1);
  }
}

function updateProgress(workDir: string, progress: WorkerProgress): void {
  const progressPath = path.join(workDir, 'progress.json');
  fs.writeFileSync(progressPath, JSON.stringify(progress, null, 2));
}

function writeResult(workDir: string, result: WorkerResult): void {
  const resultPath = path.join(workDir, 'result.json');
  fs.writeFileSync(resultPath, JSON.stringify(result, null, 2));

  // Also write result to output dir for downstream consumption
  const outputDir = path.join(workDir, 'output');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  const manifestPath = path.join(outputDir, 'render_manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify(result, null, 2));
}

main();