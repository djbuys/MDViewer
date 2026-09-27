const MARK_CLASS = 'mdv-find';
const CURRENT_CLASS = 'mdv-find-current';
const SHOW_TEXT = 4; // NodeFilter.SHOW_TEXT
const FILTER_ACCEPT = 1;
const FILTER_REJECT = 2;

export class Finder {
  constructor(root) {
    this.root = root;
    this.marks = [];
    this.index = -1;
  }

  clear() {
    for (const mark of this.marks) {
      const parent = mark.parentNode;
      if (!parent) continue;
      parent.replaceChild(mark.ownerDocument.createTextNode(mark.textContent), mark);
      parent.normalize();
    }
    this.marks = [];
    this.index = -1;
  }

  find(query) {
    this.clear();
    const needle = query.toLowerCase();
    if (!needle) return this.result();
    const doc = this.root.ownerDocument;
    const walker = doc.createTreeWalker(this.root, SHOW_TEXT, {
      acceptNode: (node) =>
        node.parentElement && node.parentElement.closest('script, style, svg, .katex-mathml')
          ? FILTER_REJECT
          : FILTER_ACCEPT,
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const text = node.nodeValue;
      const lower = text.toLowerCase();
      let from = 0;
      let at = lower.indexOf(needle, from);
      if (at === -1) continue;
      const frag = doc.createDocumentFragment();
      while (at !== -1) {
        if (at > from) frag.appendChild(doc.createTextNode(text.slice(from, at)));
        const mark = doc.createElement('mark');
        mark.className = MARK_CLASS;
        mark.textContent = text.slice(at, at + needle.length);
        frag.appendChild(mark);
        this.marks.push(mark);
        from = at + needle.length;
        at = lower.indexOf(needle, from);
      }
      if (from < text.length) frag.appendChild(doc.createTextNode(text.slice(from)));
      node.parentNode.replaceChild(frag, node);
    }
    if (this.marks.length > 0) this.select(0);
    return this.result();
  }

  next() {
    if (this.marks.length > 0) this.select((this.index + 1) % this.marks.length);
    return this.result();
  }

  prev() {
    if (this.marks.length > 0) this.select((this.index - 1 + this.marks.length) % this.marks.length);
    return this.result();
  }

  select(i) {
    if (this.index >= 0) this.marks[this.index].classList.remove(CURRENT_CLASS);
    this.index = i;
    const mark = this.marks[i];
    mark.classList.add(CURRENT_CLASS);
    if (typeof mark.scrollIntoView === 'function') mark.scrollIntoView({ block: 'center' });
  }

  result() {
    return { total: this.marks.length, current: this.index + 1 };
  }
}
