/**
 * Processing timeline on the Upload page.
 *
 * Driven by the `streamforge:status` and `streamforge:result` events that
 * app.js emits, so the upload logic itself stays untouched. The coupling is the
 * status strings below -- kept in one place so a wording change here is the
 * only edit needed.
 *
 * Honesty note: /status reports Phase 1 only. The Glue ETL and the curated
 * dataset it writes run asynchronously downstream and are not observed by this
 * poll, so they are shown as pending rather than pretended complete.
 */

const OBSERVED = ['upload', 'validation', 'complete'];
const DOWNSTREAM = ['etl', 'curated'];

const STAGE_BY_STATUS = [
  ['secure upload URL', 'upload'],
  ['Uploading encrypted', 'upload'],
  ['Validating rows', 'validation'],
];

let timeline;

function step(stage) {
  return timeline?.querySelector(`[data-stage="${stage}"]`);
}

function setStage(stage, state) {
  const node = step(stage);
  if (!node) return;
  node.classList.remove('is-pending', 'is-active', 'is-done', 'is-failed');
  node.classList.add(`is-${state}`);
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
  // Everything before the current stage is finished by definition.
  for (const earlier of OBSERVED.slice(0, OBSERVED.indexOf(stage))) {
    setStage(earlier, 'done');
  }
  setStage(stage, 'active');
}

function onResult() {
  if (!timeline) return;
  timeline.hidden = false;
  setStage('upload', 'done');
  setStage('validation', 'done');
  setStage('complete', 'done');
  // Left pending on purpose: this response cannot confirm them.
  for (const stage of DOWNSTREAM) setStage(stage, 'pending');
}

export function initTimeline() {
  timeline = document.querySelector('#timeline');
  if (!timeline) return;

  reset();
  for (const stage of DOWNSTREAM) {
    const label = step(stage)?.querySelector('.timeline-label');
    if (label) label.title = 'Runs asynchronously downstream; not reported by the upload status poll.';
  }

  window.addEventListener('streamforge:status', onStatus);
  window.addEventListener('streamforge:result', onResult);
}
