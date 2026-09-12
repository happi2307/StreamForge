/**
 * Hash router for the portal.
 *
 * Every page has a container already in index.html. The Upload page is left
 * alone -- app.js owns that markup and queries it at load -- so it has no
 * module and is never re-rendered. Other pages lazy-import their module the
 * first time they are opened.
 */

import { SessionError } from './api.js';
import { stateBlock, clear, el } from './ui.js';
import { initTimeline } from './timeline.js';

const ROUTES = {
  dashboard: { title: 'Dashboard', load: () => import('./pages/dashboard.js') },
  pipeline: { title: 'Pipeline', load: () => import('./pages/pipeline.js') },
  upload: { title: 'Upload' },
  lake: { title: 'Data Lake', load: () => import('./pages/lake.js') },
  warehouse: { title: 'Warehouse', load: () => import('./pages/warehouse.js') },
  analytics: { title: 'Analytics', load: () => import('./pages/analytics.js') },
  lineage: { title: 'Lineage', load: () => import('./pages/lineage.js') },
  metadata: { title: 'Metadata', load: () => import('./pages/metadata.js') },
  monitoring: { title: 'Monitoring', load: () => import('./pages/monitoring.js') },
  cost: { title: 'Cost', load: () => import('./pages/cost.js') },
  architecture: { title: 'Architecture', load: () => import('./pages/architecture.js') },
  infrastructure: { title: 'Infrastructure', load: () => import('./pages/infrastructure.js') },
};

const DEFAULT_ROUTE = 'upload';

const title = document.querySelector('#page-title');
const sidebar = document.querySelector('#sidebar');
const navToggle = document.querySelector('#nav-toggle');

/** Routes whose module has already run, so revisiting does not re-fetch. */
const rendered = new Set();

function currentRoute() {
  const name = location.hash.replace(/^#\/?/, '').split('?')[0];
  return ROUTES[name] ? name : DEFAULT_ROUTE;
}

function container(name) {
  return document.querySelector(`#page-${name}`);
}

function showOnly(name) {
  for (const page of document.querySelectorAll('.page')) {
    page.hidden = page.id !== `page-${name}`;
  }
  for (const link of document.querySelectorAll('.nav-link')) {
    const active = link.dataset.route === name;
    link.classList.toggle('is-active', active);
    if (active) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
}

async function renderPage(name) {
  const route = ROUTES[name];
  const target = container(name);
  if (!route.load || !target || rendered.has(name)) return;

  clear(target).append(stateBlock('loading', `Loading ${route.title.toLowerCase()}…`));

  try {
    const module = await route.load();
    clear(target);
    await module.render(target);
    rendered.add(name);
  } catch (error) {
    clear(target);
    if (error instanceof SessionError) {
      target.append(stateBlock('signed-out', error.message,
        el('a', { class: 'button button-secondary', href: '#/upload', text: 'Go to sign in' })));
    } else {
      target.append(stateBlock('error', error.message || 'Something went wrong.',
        el('button', {
          class: 'button button-secondary',
          type: 'button',
          text: 'Retry',
          onclick: () => { rendered.delete(name); renderPage(name); },
        })));
    }
  }
}

function navigate() {
  const name = currentRoute();
  showOnly(name);
  title.textContent = ROUTES[name].title;
  document.title = `StreamForge | ${ROUTES[name].title}`;
  sidebar.classList.remove('is-open');
  navToggle.setAttribute('aria-expanded', 'false');
  renderPage(name);
}

navToggle.addEventListener('click', () => {
  const open = sidebar.classList.toggle('is-open');
  navToggle.setAttribute('aria-expanded', String(open));
});

// A fresh sign-in invalidates whatever the pages rendered while signed out.
// navigate() rather than renderPage() so the correct container is shown too.
window.addEventListener('streamforge:signedin', () => {
  rendered.clear();
  navigate();
});

window.addEventListener('hashchange', navigate);
initTimeline();
navigate();
