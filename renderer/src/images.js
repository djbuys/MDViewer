const ABSOLUTE = /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i;

export function isRelativeResource(src) {
  return !!src && !ABSOLUTE.test(src) && !src.startsWith('#');
}

// Moves relative <img src> into data-mdv-src so the WebView never tries to
// load them directly, and returns the images that need resolving.
export function detachRelativeImages(root) {
  const pending = [];
  for (const img of root.querySelectorAll('img[src]')) {
    const src = img.getAttribute('src');
    if (!isRelativeResource(src)) continue;
    img.removeAttribute('src');
    img.setAttribute('data-mdv-src', src);
    pending.push(img);
  }
  return pending;
}

export async function resolveImages(images, resolve) {
  await Promise.all(
    images.map(async (img) => {
      const src = img.getAttribute('data-mdv-src');
      let dataUri = null;
      try {
        dataUri = await resolve(src);
      } catch (_) {
        dataUri = null;
      }
      if (dataUri) {
        img.setAttribute('src', dataUri);
      } else {
        img.classList.add('mdv-broken-image');
        img.setAttribute('title', `Image not found: ${src}`);
      }
    }),
  );
}
