import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import createDOMPurify from 'dompurify';
import { renderMarkdown, stripFrontMatter } from '../src/markdown.js';

const purify = createDOMPurify(new JSDOM('').window);
const render = (text, options = {}) => renderMarkdown(text, { purify, ...options });

test('strips YAML front matter only at the start', () => {
  assert.equal(stripFrontMatter('---\ntitle: x\n---\n# Hi\n'), '# Hi\n');
  assert.equal(stripFrontMatter('# Hi\n---\na: b\n---\n'), '# Hi\n---\na: b\n---\n');
  assert.equal(stripFrontMatter('﻿---\na: 1\n...\nbody'), 'body');
});

test('front matter is not rendered', () => {
  const { html } = render('---\ntitle: Secret\n---\n# Visible\n');
  assert.ok(!html.includes('Secret'));
  assert.ok(html.includes('Visible'));
});

test('headings get GitHub-style unique ids and are reported', () => {
  const { html, headings } = render('# Hello World\n## Hello World\n### `code` & More!\n');
  assert.deepEqual(headings, [
    { id: 'hello-world', text: 'Hello World', level: 1 },
    { id: 'hello-world-1', text: 'Hello World', level: 2 },
    { id: 'code--more', text: 'code & More!', level: 3 },
  ]);
  assert.ok(html.includes('<h1 id="hello-world">'));
  assert.ok(html.includes('<h2 id="hello-world-1">'));
});

test('renders GFM tables, strikethrough and autolinks', () => {
  const { html } = render('| a | b |\n|---|---|\n| 1 | 2 |\n\n~~gone~~ https://example.com\n');
  assert.ok(html.includes('<table>'));
  assert.ok(html.includes('<td>1</td>'));
  assert.ok(html.includes('<s>gone</s>'));
  assert.ok(html.includes('<a href="https://example.com">https://example.com</a>'));
});

test('renders task lists as disabled checkboxes', () => {
  const { html } = render('- [x] done\n- [ ] todo\n');
  assert.match(html, /<input class="task-list-item-checkbox" checked="" disabled="" type="checkbox">/);
  assert.match(html, /<input class="task-list-item-checkbox" disabled="" type="checkbox">/);
});

test('renders footnotes', () => {
  const { html } = render('Text[^1]\n\n[^1]: The note\n');
  assert.ok(html.includes('class="footnote-ref"'));
  assert.ok(html.includes('The note'));
});

test('renders inline, block and fenced maths with KaTeX (keeping inline styles)', () => {
  const { html } = render('$E=mc^2$\n\n$$\\frac{1}{2}$$\n\n```math\nx^2\n```\n');
  assert.equal((html.match(/class="katex"/g) || []).length, 3);
  assert.ok(html.includes('class="math-block"'));
  assert.match(html, /style="height:/);
});

test('KaTeX errors render in the error colour instead of throwing', () => {
  const { html } = render('$\\notacommand{x}$');
  assert.ok(html.includes('#cc0000'));
});

test('mermaid fences become pre.mermaid with escaped source', () => {
  const { html } = render('```mermaid\ngraph TD; A-->B\n```\n');
  assert.ok(html.includes('<pre class="mermaid">graph TD; A--&gt;B\n</pre>'));
});

test('code fences are syntax highlighted', () => {
  const { html } = render('```js\nconst a = 1;\n```\n');
  assert.ok(html.includes('<span class="hljs-keyword">const</span>'));
});

test('heavyFeatures=false disables highlighting, maths and mermaid', () => {
  const { html } = render('$x$\n\n```mermaid\ngraph TD; A-->B\n```\n\n```js\nconst a = 1;\n```\n', {
    heavyFeatures: false,
  });
  assert.ok(!html.includes('katex'));
  assert.ok(!html.includes('class="mermaid"'));
  assert.ok(!html.includes('hljs-keyword'));
  assert.ok(html.includes('language-mermaid'));
});

test('sanitizes scripts, event handlers, javascript: URLs and frames', () => {
  const { html } = render(
    '<script>alert(1)</script>\n\n<img src="x.png" onerror="alert(1)">\n\n' +
      '<a href="javascript:alert(1)">bad</a>\n\n<iframe src="https://evil.example"></iframe>\n\n' +
      '[md-bad](javascript:alert(1))\n\n<style>body{display:none}</style>\n',
  );
  assert.ok(!html.includes('<script'));
  assert.ok(!html.includes('onerror'));
  // markdown-it leaves `[x](javascript:...)` as literal text; what matters is no such href.
  assert.ok(!/href="javascript:/i.test(html));
  assert.ok(!html.includes('<iframe'));
  assert.ok(!html.includes('<style'));
});

test('image maps are stripped so every link goes through the click handler', () => {
  const { html } = render(
    '<map name="m"><area href="https://evil.example" shape="rect" coords="0,0,10,10"></map>\n\n<img src="x.png" usemap="#m">\n',
  );
  assert.ok(!/<map/i.test(html));
  assert.ok(!/<area/i.test(html));
  assert.ok(!html.includes('evil.example'));
});

test('keeps relative image and link URLs for the host to resolve', () => {
  const { html } = render('![pic](img/a.png)\n\n[next](other.md#part)\n');
  assert.ok(html.includes('<img src="img/a.png" alt="pic">'));
  assert.ok(html.includes('<a href="other.md#part">next</a>'));
});
