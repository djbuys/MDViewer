import DOMPurify from 'dompurify';
import { renderMarkdown } from './markdown.js';
import { Finder } from './find.js';
import { detachRelativeImages, resolveImages } from './images.js';

const content = document.getElementById('content');
const finder = new Finder(content);
const state = {
  markdown: '',
  options: { theme: 'light', fontScale: 1, heavyFeatures: true },
  generation: 0,
};

function callHost(name, payload) {
  const bridge = window.flutter_inappwebview;
  if (!bridge || typeof bridge.callHandler !== 'function') {
    console.log(`[mdv] ${name}`, payload);
    return Promise.resolve(null);
  }
  return bridge.callHandler(name, payload);
}

function applyTheme(theme) {
  const dark = theme === 'dark';
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.getElementById('md-light').disabled = dark;
  document.getElementById('md-dark').disabled = !dark;
  document.getElementById('hl-light').disabled = dark;
  document.getElementById('hl-dark').disabled = !dark;
}

async function renderMermaid(generation) {
  const blocks = content.querySelectorAll('pre.mermaid');
  if (blocks.length === 0 || !window.mermaid) return;
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: state.options.theme === 'dark' ? 'dark' : 'default',
  });
  for (const [i, block] of [...blocks].entries()) {
    if (generation !== state.generation) return;
    try {
      const { svg } = await window.mermaid.render(`mdv-mermaid-${generation}-${i}`, block.textContent);
      const wrapper = document.createElement('div');
      wrapper.className = 'mermaid-diagram';
      wrapper.innerHTML = svg;
      block.replaceWith(wrapper);
    } catch (err) {
      const error = document.createElement('div');
      error.className = 'mdv-mermaid-error';
      error.textContent = `Mermaid error: ${err && err.message ? err.message : err}`;
      block.after(error);
    }
  }
}

async function render(markdown, options = {}) {
  const generation = ++state.generation;
  state.markdown = markdown;
  state.options = { ...state.options, ...options };
  applyTheme(state.options.theme);
  document.documentElement.style.setProperty('--mdv-font-scale', String(state.options.fontScale));
  try {
    finder.clear();
    const { html, headings } = renderMarkdown(markdown, {
      purify: DOMPurify,
      heavyFeatures: state.options.heavyFeatures,
    });
    const template = document.createElement('template');
    template.innerHTML = html;
    const images = detachRelativeImages(template.content);
    content.replaceChildren(template.content);
    callHost('headingsChanged', headings);
    await Promise.all([
      resolveImages(images, (path) => callHost('resolveResource', { path })),
      state.options.heavyFeatures ? renderMermaid(generation) : Promise.resolve(),
    ]);
    if (generation !== state.generation) return;
    if (typeof state.options.restoreScrollY === 'number') {
      window.scrollTo(0, state.options.restoreScrollY);
    }
    callHost('rendered', { generation });
  } catch (err) {
    callHost('renderError', { message: String(err && err.stack ? err.stack : err) });
  }
}

// Every link click goes to the host; the WebView itself never navigates.
document.addEventListener('click', (event) => {
  const anchor = event.target.closest('a[href]');
  if (!anchor) return;
  event.preventDefault();
  callHost('linkClicked', { href: anchor.getAttribute('href') });
});

function reportFind(result) {
  callHost('findResult', result);
  return result;
}

window.mdv = {
  render,
  scrollToHeading(id) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ block: 'start' });
    return !!el;
  },
  getScrollPosition() {
    return window.scrollY;
  },
  setScrollPosition(y) {
    window.scrollTo(0, y);
  },
  find(query) {
    return reportFind(finder.find(query));
  },
  findNext() {
    return reportFind(finder.next());
  },
  findPrev() {
    return reportFind(finder.prev());
  },
  clearFind() {
    finder.clear();
    return reportFind({ total: 0, current: 0 });
  },
  print() {
    window.print();
  },
};
