import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { Finder } from '../src/find.js';

function setup(html) {
  const { document } = new JSDOM(`<div id="c">${html}</div>`).window;
  const root = document.getElementById('c');
  return { root, finder: new Finder(root) };
}

test('finds case-insensitive matches across elements and cycles', () => {
  const { root, finder } = setup('<p>Foo bar foo</p><p>FOO<b>x</b></p>');
  assert.deepEqual(finder.find('foo'), { total: 3, current: 1 });
  assert.equal(root.querySelectorAll('mark.mdv-find').length, 3);
  assert.equal(root.querySelectorAll('mark.mdv-find-current').length, 1);
  assert.deepEqual(finder.next(), { total: 3, current: 2 });
  assert.deepEqual(finder.next(), { total: 3, current: 3 });
  assert.deepEqual(finder.next(), { total: 3, current: 1 });
  assert.deepEqual(finder.prev(), { total: 3, current: 3 });
});

test('clear restores the original DOM', () => {
  const { root, finder } = setup('<p>Foo bar foo</p><p>FOO<b>x</b></p>');
  finder.find('foo');
  finder.clear();
  assert.equal(root.innerHTML, '<p>Foo bar foo</p><p>FOO<b>x</b></p>');
  assert.deepEqual(finder.result(), { total: 0, current: 0 });
});

test('empty query and no matches report zero', () => {
  const { finder } = setup('<p>abc</p>');
  assert.deepEqual(finder.find(''), { total: 0, current: 0 });
  assert.deepEqual(finder.find('zzz'), { total: 0, current: 0 });
  assert.deepEqual(finder.next(), { total: 0, current: 0 });
});

test('skips text inside svg and KaTeX MathML', () => {
  const { finder } = setup(
    '<p>node</p><svg><text>node</text></svg><span class="katex-mathml">node</span>',
  );
  assert.deepEqual(finder.find('node'), { total: 1, current: 1 });
});

test('a new search replaces the previous highlights', () => {
  const { root, finder } = setup('<p>alpha beta alpha</p>');
  finder.find('alpha');
  finder.find('beta');
  assert.equal(root.querySelectorAll('mark.mdv-find').length, 1);
});
