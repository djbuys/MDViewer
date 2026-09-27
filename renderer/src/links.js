const XLINK_NS = 'http://www.w3.org/1999/xlink';

function linkTarget(element) {
  const name = element.localName;
  if (name !== 'a' && name !== 'area') return null;
  return element.getAttribute('href') ?? element.getAttributeNS(XLINK_NS, 'href');
}

// Returns the link target of a click on `target`, or null when the click is
// not on a link. Covers HTML anchors, SVG links (`href` or `xlink:href`) and,
// defensively, image-map areas, so the WebView itself never navigates.
// Walks up to the first `a`/`area` that actually has a target: an anchor
// without one (e.g. an SVG `<a>` nested inside an HTML link) must not hide
// the outer link, which the WebView would otherwise follow.
export function linkHrefFromEvent(target) {
  let node = target && target.nodeType === 1 ? target : target?.parentElement ?? null;
  while (node) {
    const href = linkTarget(node);
    if (href !== null) return href;
    node = node.parentElement;
  }
  return null;
}
