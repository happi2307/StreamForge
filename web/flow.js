/**
 * Layered flow diagrams, built as DOM rather than SVG or a charting library.
 *
 * A CDN copy of Mermaid is blocked by the CloudFront CSP (`default-src 'self'`)
 * and vendoring it would add ~2 MB to a project with no build step, so the
 * diagram content from docs/diagrams/*.md is expressed as data here and drawn
 * with boxes and arrows. Shared by the Architecture and Lineage pages.
 */

import { el } from './ui.js';

/**
 * layers: [{ label?, nodes: [{ id, label, sub?, tone? }] }]
 * onSelect: optional (node) => void, which makes nodes focusable buttons.
 */
export function flowDiagram({ layers, onSelect, orientation = 'vertical' }) {
  const canvas = el('div', { class: `flow flow-${orientation}` });

  layers.forEach((layer, index) => {
    if (index > 0) {
      canvas.append(el('div', { class: 'flow-arrow', 'aria-hidden': 'true', text: '↓' }));
    }

    const row = el('div', { class: 'flow-layer' },
      layer.nodes.map((node) => {
        const content = [
          el('span', { class: 'flow-node-label', text: node.label }),
          node.sub ? el('span', { class: 'flow-node-sub', text: node.sub }) : null,
        ];

        if (!onSelect) {
          return el('div', { class: `flow-node tone-${node.tone || 'default'}` }, content);
        }
        return el('button', {
          class: `flow-node tone-${node.tone || 'default'}`,
          type: 'button',
          'data-node': node.id,
          onclick: () => onSelect(node),
        }, content);
      }));

    canvas.append(layer.label
      ? el('div', { class: 'flow-group' }, [el('p', { class: 'flow-group-label', text: layer.label }), row])
      : row);
  });

  return canvas;
}

/** Wraps a diagram in a zoomable frame, per the "zoom and inspect" requirement. */
export function zoomable(diagram) {
  let scale = 1;
  const stage = el('div', { class: 'zoom-stage' }, diagram);

  const apply = () => { stage.style.transform = `scale(${scale})`; };
  const step = (delta) => { scale = Math.min(2, Math.max(0.5, scale + delta)); apply(); };

  return el('div', { class: 'zoom-frame' }, [
    el('div', { class: 'zoom-controls' }, [
      el('button', { class: 'zoom-button', type: 'button', text: '−', 'aria-label': 'Zoom out', onclick: () => step(-0.15) }),
      el('button', { class: 'zoom-button', type: 'button', text: 'Reset', onclick: () => { scale = 1; apply(); } }),
      el('button', { class: 'zoom-button', type: 'button', text: '+', 'aria-label': 'Zoom in', onclick: () => step(0.15) }),
    ]),
    el('div', { class: 'zoom-viewport' }, stage),
  ]);
}
