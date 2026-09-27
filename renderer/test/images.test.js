import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { isRelativeResource, detachRelativeImages, resolveImages } from '../src/images.js';

test('classifies relative resources', () => {
  assert.equal(isRelativeResource('a.png'), true);
  assert.equal(isRelativeResource('../img/a.png'), true);
  assert.equal(isRelativeResource('/root.png'), true);
  assert.equal(isRelativeResource('https://x/y.png'), false);
  assert.equal(isRelativeResource('data:image/png;base64,AA=='), false);
  assert.equal(isRelativeResource('//cdn.example/a.png'), false);
  assert.equal(isRelativeResource(''), false);
});

test('detaches only relative images and resolves them', async () => {
  const { document } = new JSDOM(
    '<div id="c"><img src="a.png" alt="A"><img src="https://x/y.png"><img src="missing.png" alt="M"></div>',
  ).window;
  const root = document.getElementById('c');
  const images = detachRelativeImages(root);
  assert.equal(images.length, 2);
  assert.equal(images[0].hasAttribute('src'), false);
  assert.equal(images[0].getAttribute('data-mdv-src'), 'a.png');

  const asked = [];
  await resolveImages(images, async (path) => {
    asked.push(path);
    return path === 'a.png' ? 'data:image/png;base64,AA==' : null;
  });
  assert.deepEqual(asked, ['a.png', 'missing.png']);
  assert.equal(images[0].getAttribute('src'), 'data:image/png;base64,AA==');
  assert.equal(images[1].classList.contains('mdv-broken-image'), true);
  assert.equal(images[1].getAttribute('title'), 'Image not found: missing.png');
  assert.equal(root.querySelector('img[src^="https"]').getAttribute('src'), 'https://x/y.png');
});

test('a throwing resolver marks the image broken', async () => {
  const { document } = new JSDOM('<div id="c"><img src="a.png"></div>').window;
  const images = detachRelativeImages(document.getElementById('c'));
  await resolveImages(images, async () => {
    throw new Error('boom');
  });
  assert.equal(images[0].classList.contains('mdv-broken-image'), true);
});
