/**
 * POC 3e — Node.js Worker for DeepFrames Worker Protocol v0
 *
 * Contract:
 *   Input:  {workdir}/request.json  (task_id, task_type, params, ...)
 *   Output: {workdir}/progress.json (heartbeat + progress %)
 *   Output: {workdir}/result.json   (success, output_files, metrics, ...)
 *
 * Usage: node worker.js <workdir>
 */

const fs = require('fs');
const path = require('path');

function nowISO() {
  return new Date().toISOString();
}

function writeProgress(workdir, taskId, status, progress, message, step, files) {
  const doc = {
    schema_version: '1.0.0',
    task_id: taskId,
    status: status,
    progress_percent: progress,
    current_step: step || '',
    message: message || '',
    files_produced: files || [],
    updated_at: nowISO()
  };
  fs.writeFileSync(path.join(workdir, 'progress.json'), JSON.stringify(doc, null, 2), 'utf-8');
}

function writeResult(workdir, taskId, success, outputFiles, error, duration) {
  const doc = {
    schema_version: '1.0.0',
    task_id: taskId,
    success: success,
    output_files: outputFiles || [],
    metrics: JSON.stringify({ frames: 60, fps: 30, codec: 'h264' }),
    error_message: error || '',
    duration_ms: duration || 0,
    completed_at: nowISO()
  };
  fs.writeFileSync(path.join(workdir, 'result.json'), JSON.stringify(doc, null, 2), 'utf-8');
}

async function main() {
  const workdir = process.argv[2];
  if (!workdir) {
    console.error('Usage: node worker.js <workdir>');
    process.exit(1);
  }

  // Validate workdir exists
  if (!fs.existsSync(workdir)) {
    console.error(`Work directory not found: ${workdir}`);
    process.exit(1);
  }

  // Read request.json
  const requestPath = path.join(workdir, 'request.json');
  if (!fs.existsSync(requestPath)) {
    console.error(`request.json not found in ${workdir}`);
    process.exit(1);
  }

  const request = JSON.parse(fs.readFileSync(requestPath, 'utf-8'));
  const { task_id, task_type, heartbeat_interval_ms } = request;

  console.log(`[Worker] PID ${process.pid} started, task_id=${task_id}, type=${task_type}`);
  const t0 = Date.now();

  // Simulate 6-step rendering pipeline with heartbeat
  const steps = [
    'init', 'load_assets', 'render_frame_0', 'render_frame_30',
    'encode_video', 'write_output'
  ];

  for (let i = 0; i < steps.length; i++) {
    // Check cancel signal
    if (fs.existsSync(path.join(workdir, 'cancel'))) {
      console.log(`[Worker] Cancel signal received, stopping`);
      writeProgress(workdir, task_id, 'cancelled', Math.round((i / steps.length) * 100),
        'Cancelled by main program', steps[i]);
      writeResult(workdir, task_id, false, [], 'Cancelled', Date.now() - t0);
      process.exit(0);
    }

    const pct = Math.round(((i + 1) / steps.length) * 100);
    writeProgress(workdir, task_id, i < steps.length - 1 ? 'running' : 'done', pct,
      `Worker step ${i + 1}/${steps.length}: ${steps[i]}`, steps[i]);

    console.log(`[Worker] ${pct}% — ${steps[i]}`);
    await new Promise(r => setTimeout(r, 500)); // simulate work
  }

  // Write success result
  const outputFile = path.join(workdir, 'output', `render_${task_id}.mp4`);
  fs.mkdirSync(path.join(workdir, 'output'), { recursive: true });
  fs.writeFileSync(outputFile, `mock-render-${task_id}`); // placeholder

  const duration = Date.now() - t0;
  writeResult(workdir, task_id, true, [outputFile], '', duration);
  writeProgress(workdir, task_id, 'done', 100, 'Complete', 'done', [outputFile]);

  console.log(`[Worker] Done in ${duration}ms, output: ${outputFile}`);
}

main().catch(err => {
  console.error('[Worker] Error:', err.message);
  process.exit(1);
});
