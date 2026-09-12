/** Interactive lineage graph. Selecting a stage reveals what it does. */

import { cachedApi } from '../api.js';
import { pageHeader, panel, stateBlock, el, clear, formatNumber } from '../ui.js';
import { flowDiagram, zoomable } from '../flow.js';

export async function render(target) {
  const data = await cachedApi('/api/lineage');
  const stages = data.stages || [];

  target.append(pageHeader(
    'Lineage',
    'The path a row takes from upload to dashboard. Select any stage to see its purpose, inputs, outputs and transformations.',
  ));

  if (!stages.length) {
    target.append(stateBlock('empty', 'No lineage available until a batch has been processed.'));
    return;
  }

  const details = el('div', { class: 'stage-details' });

  const diagram = flowDiagram({
    layers: stages.map((stage) => ({
      nodes: [{
        id: stage.id,
        label: stage.label,
        sub: stage.records !== null && stage.records !== undefined
          ? `${formatNumber(stage.records)} ${stage.unit || 'records'}`
          : undefined,
        tone: stage.id === 'portal' ? 'accent' : 'default',
      }],
    })),
    onSelect: (node) => selectStage(node.id),
  });

  target.append(panel('Pipeline graph', [zoomable(diagram)]));
  target.append(panel('Stage detail', [details]));

  function selectStage(id) {
    const stage = stages.find((s) => s.id === id);
    if (!stage) return;

    for (const node of diagram.querySelectorAll('.flow-node')) {
      node.classList.toggle('is-selected', node.dataset.node === id);
    }

    clear(details).append(
      el('h4', { class: 'stage-title', text: stage.label }),
      el('p', { class: 'stage-purpose', text: stage.purpose }),
      el('dl', { class: 'detail-list' }, [
        el('dt', { text: 'Input' }), el('dd', { text: stage.input || '—' }),
        el('dt', { text: 'Output' }), el('dd', { text: stage.output || '—' }),
        el('dt', { text: 'Volume' }), el('dd', {
          text: stage.records === null || stage.records === undefined
            ? 'Not reported by this stage'
            : `${formatNumber(stage.records)} ${stage.unit || 'records'}`,
        }),
        el('dt', { text: 'Execution time' }), el('dd', {
          text: stage.duration_ms ? `${Math.round(stage.duration_ms)} ms` : '—',
        }),
        el('dt', { text: 'Transformations' }), el('dd', {},
          stage.transformations && stage.transformations.length
            ? el('ul', { class: 'stage-rules' }, stage.transformations.map((t) => el('li', { text: t })))
            : el('span', { text: 'None — this stage moves data without altering it.' })),
      ]),
    );
  }

  selectStage('validation');
}
