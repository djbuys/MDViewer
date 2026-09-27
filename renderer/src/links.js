const XLINK_NS = 'http://www.w3.org/1999/xlink';

// Returns the link target of a click on `target`, or null when the click is
// not on a link. Covers HTML anchors, SVG links (`href` or `xlink:href`) and,
// defensively, image-map areas, so the WebView itself never navigates.
export function linkHrefFromEvent(target) {
  let node = target;
  if (node && typeof node.closest !== 'function') node = node.parentElement;
  if (!node || typeof node.closest !== 'function') return null;
  const link = node.closest('a, area');
  if (!link) return null;
  const href = link.getAttribute('href') ?? link.getAttributeNS(XLINK_NS, 'href');
  return href === null ? null : href;
}
