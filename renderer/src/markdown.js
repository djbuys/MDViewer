import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import katexModule from '@vscode/markdown-it-katex';
import katex from 'katex';
import hljs from 'highlight.js/lib/common';
import GithubSlugger from 'github-slugger';

// @vscode/markdown-it-katex is CommonJS with a `default` export.
const katexPlugin = katexModule.default ?? katexModule;

const FRONT_MATTER = /^﻿?---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;
const KATEX_OPTIONS = { throwOnError: false, errorColor: '#cc0000' };

export function stripFrontMatter(text) {
  return text.replace(FRONT_MATTER, '');
}

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Assigns GitHub-compatible ids to headings and records them in env.headings.
function headingIds(md) {
  md.core.ruler.push('mdv_heading_ids', (state) => {
    const slugger = new GithubSlugger();
    const headings = [];
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (token.type !== 'heading_open') continue;
      const inline = tokens[i + 1];
      const text = (inline.children || [])
        .filter((c) => c.type === 'text' || c.type === 'code_inline')
        .map((c) => c.content)
        .join('');
      const id = slugger.slug(text);
      token.attrSet('id', id);
      headings.push({ id, text, level: Number(token.tag.slice(1)) });
    }
    state.env.headings = headings;
  });
}

export function createMarkdown({ heavyFeatures = true } = {}) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: false,
    highlight: heavyFeatures
      ? (code, lang) => {
          if (lang && hljs.getLanguage(lang)) {
            try {
              return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
            } catch (_) {
              // fall through to markdown-it's default escaping
            }
          }
          return '';
        }
      : null,
  });
  md.use(footnote).use(taskLists, { enabled: false }).use(headingIds);
  if (heavyFeatures) md.use(katexPlugin, KATEX_OPTIONS);

  const defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const lang = token.info.trim().split(/\s+/)[0];
    if (heavyFeatures && lang === 'mermaid') {
      return `<pre class="mermaid">${escapeHtml(token.content)}</pre>\n`;
    }
    if (heavyFeatures && lang === 'math') {
      const math = katex.renderToString(token.content, { ...KATEX_OPTIONS, displayMode: true });
      return `<div class="math-block">${math}</div>\n`;
    }
    return defaultFence(tokens, idx, options, env, self);
  };
  return md;
}

// `style` attributes are intentionally allowed: KaTeX layout depends on them.
export const PURIFY_CONFIG = {
  FORBID_TAGS: ['style', 'iframe', 'object', 'embed', 'form', 'base', 'meta', 'link'],
};

export function renderMarkdown(text, { purify, heavyFeatures = true }) {
  const md = createMarkdown({ heavyFeatures });
  const env = {};
  const raw = md.render(stripFrontMatter(text), env);
  const html = purify.sanitize(raw, PURIFY_CONFIG);
  return { html, headings: env.headings || [] };
}
