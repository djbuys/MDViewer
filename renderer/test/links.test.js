import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { linkHrefFromEvent } from '../src/links.js';

function page(html) {
  const { document } = new JSDOM(`<body>${html}</body>`).window;
  return document;
}

test('HTML anchors report their href, also when a child was clicked', () => {
  const doc = page('<p><a id="a" href="docs/b.md"><strong id="inner">B</strong></a></p>');
  assert.equal(linkHrefFromEvent(doc.getElementById('a')), 'docs/b.md');
  assert.equal(linkHrefFromEvent(doc.getElementById('inner')), 'docs/b.md');
  assert.equal(linkHrefFromEvent(doc.getElementById('inner').firstChild), 'docs/b.md');
});

test('SVG links report href and xlink:href', () => {
  const doc = page(
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">' +
      '<a id="plain" href="https://example.com/a"><text id="t1">a</text></a>' +
      '<a id="xlink" xlink:href="https://example.com/b"><rect id="r" width="1" height="1"/></a>' +
      '</svg>',
  );
  assert.equal(linkHrefFromEvent(doc.getElementById('t1')), 'https://example.com/a');
  assert.equal(linkHrefFromEvent(doc.getElementById('r')), 'https://example.com/b');
});

test('image-map areas are routed too', () => {
  const doc = page('<map name="m"><area id="area" href="evil.html" shape="rect" coords="0,0,1,1"></map>');
  assert.equal(linkHrefFromEvent(doc.getElementById('area')), 'evil.html');
});

test('clicks outside links, and anchors without a target, report null', () => {
  const doc = page('<p id="p">text <a id="named" name="x">anchor</a></p>');
  assert.equal(linkHrefFromEvent(doc.getElementById('p')), null);
  assert.equal(linkHrefFromEvent(doc.getElementById('named')), null);
  assert.equal(linkHrefFromEvent(null), null);
});
