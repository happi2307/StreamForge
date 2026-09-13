/**
 * Processing timeline on the Upload page.
 *
 * Upload and Validation come from the `streamforge:status` and
 * `streamforge:result` events app.js emits, so the upload logic stays
 * untouched. The coupling is the status strings below, kept in one place.
 *
 * Glue ETL and Curated are genuinely asynchronous and are not reported by the
 * upload status poll, so once a batch completes this polls /api/etl for the
 * real Glue run state. Without that the two stages could never light up and a
 * working pipeline looked exactly like a broken one.
 */

import { api } from './api.js';

const OBSERVED = ['upload', 'validation', 'complete'];
const DOWNSTREAM = ['etl', 'curated'];

const STAGE_BY_STATUS = [
  ['secure upload URL', 'upload'],
  ['Uploading encrypted', 'upload'],
  ['Validating rows', 'validation'],
];

// The trigger batches events before starting Glue, so the run does not appear
// instantly. Poll well past that window, then stop rather than spin forever.
const POLL_INTERVAL_MS = 15_000;
const POLL_LIMIT_MS = 8 * 60_000;

let timeline;
let poller = null;

function step(stage) {
  return timeline?.querySelector(`[data-stage="${stage}"]`);
}

function setStage(stage, state, note) {
  const node = step(stage);
  if (!node) return;
  node.classList.remove('is-pending', 'is-active', 'is-done', 'is-failed');
  node.classList.add(`is-${state}`);
  const label = node.querySelector('.timeline-label');
  if (label && note !== undefined) label.title = note;
}

function reset() {
  for (const stage of [...OBSERVED, ...DOWNSTREAM]) setStage(stage, 'pending');
}

function stageFor(text) {
  const match = STAGE_BY_STATUS.find(([needle]) => text.includes(needle));
  return match ? match[1] : null;
}

function onStatus({ detail }) {
  if (!timeline) return;
  const { text, state } = detail;

  if (state === 'error') {
    const active = timeline.querySelector('.is-active');
    if (active) setStage(active.dataset.stage, 'failed');
    return;
  }

  const stage = stageFor(text);
  if (!stage) return;

  timeline.hidden = false;
  for (const earlier of OBSERVED.slice(0, OBSERVED.indexOf(stage))) {
    setStage(earlier, 'done');
  }
  setStage(stage, 'active');
}

function onResult({ detail }) {
  if (!timeline) return;
  timeline.hidden = false;
  setStage('upload', 'done');
  setStage('validation', 'done');
  setStage('complete', 'done');

  // Anything the Glue job did before this batch landed is not about this batch.
  const since = Date.parse(detail?.processed_timestamp || '') || Date.now();
  watchDownstream(since);
}

/** Poll the real Glue run state until it resolves or we give up. */
function watchDownstream(since) {
  if (poller) clearTimeout(poller);
  const deadline = Date.now() + POLL_LIMIT_MS;

  // Show it as in-progress straight away. The trigger batches events before
  // starting Glue, so there is a gap where the run does not exist yet -- left
  // grey, that gap is indistinguishable from "never runs", which is exactly
  // how it kept being read.
  setStage('etl', 'active', 'Waiting for the Glue trigger to fire.');
  setStage('curated', 'pending', 'Written once the Glue run finishes.');

  const tick = async () => {
    let data;
    try {
      data = await api('/api/etl');
    } catch {
      // Transient failure or a signed-out session: stop quietly rather than
      // claiming the pipeline failed.
      setStage('etl', 'pending', 'Could not read the Glue run state.');
      return;
    }

    // The run that belongs to this batch is the first one started after it.
    const run = (data.runs || [])
      .filter((r) => Date.parse(r.started || '') >= since - 30_000)
      .sort((a, b) => Date.parse(a.started) - Date.parse(b.started))[0];

    if (run && ['RUNNING', 'STARTING'].includes(run.state)) {
      setStage('etl', 'active', `Glue run in progress${run.trigger ? ` (${run.trigger})` : ''}.`);
    } else if (run && run.state === 'SUCCEEDED') {
      setStage('etl', 'done', `Glue run succeeded in ${run.seconds ?? '?'}s.`);
      const curatedAt = Date.parse(data.curated?.latest || '') || 0;
      if (curatedAt >= since - 30_000) {
        setStage('curated', 'done', `${data.curated.object_count} objects in the curated zone.`);
      } else {
        setStage('curated', 'pending', 'Run succeeded but wrote no new curated objects.');
      }
      return;
    } else if (run && ['FAILED', 'STOPPED', 'TIMEOUT'].includes(run.state)) {
      setStage('etl', 'failed', run.error || `Glue run ${run.state.toLowerCase()}.`);
      setStage('curated', 'pending');
      return;
    }

    if (Date.now() < deadline) {
      poller = setTimeout(tick, POLL_INTERVAL_MS);
    } else {
      setStage('etl', 'pending', 'No Glue run observed within 8 minutes.');
    }
  };

  poller = setTimeout(tick, 5_000);
}

export function initTimeline() {
  timeline = document.querySelector('#timeline');
  if (!timeline) return;

  reset();
  setStage('etl', 'pending', 'Runs asynchronously after the clean output is written.');
  setStage('curated', 'pending', 'Written by the Glue transform.');

  window.addEventListener('streamforge:status', onStatus);
  window.addEventListener('streamforge:result', onResult);
}
