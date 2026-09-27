import { build } from 'esbuild';
import { cp, mkdir, rm } from 'node:fs/promises';

const out = process.argv[2] ?? '../assets/renderer';
const nm = 'node_modules';

await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });

await build({
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'iife',
  minify: true,
  target: ['es2020'],
  outfile: `${out}/renderer.bundle.js`,
  legalComments: 'none',
});

const copies = [
  ['static/index.html', 'index.html'],
  ['static/app.css', 'app.css'],
  [`${nm}/mermaid/dist/mermaid.min.js`, 'mermaid.min.js'],
  [`${nm}/github-markdown-css/github-markdown-light.css`, 'github-markdown-light.css'],
  [`${nm}/github-markdown-css/github-markdown-dark.css`, 'github-markdown-dark.css'],
  [`${nm}/highlight.js/styles/github.min.css`, 'hljs-github.css'],
  [`${nm}/highlight.js/styles/github-dark.min.css`, 'hljs-github-dark.css'],
  [`${nm}/katex/dist/katex.min.css`, 'katex/katex.min.css'],
];
for (const [from, to] of copies) {
  await cp(from, `${out}/${to}`);
}
// Only woff2 fonts are needed by every supported WebView.
await cp(`${nm}/katex/dist/fonts`, `${out}/katex/fonts`, {
  recursive: true,
  filter: (src) => !/\.(ttf|woff)$/.test(src),
});
console.log(`renderer built into ${out}`);
