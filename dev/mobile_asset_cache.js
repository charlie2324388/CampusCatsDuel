// VERSIONED_ASSETS is filled by build_mobile_cache.py when preparing a web export.
(() => {
  const assets = __VERSIONED_ASSETS__;
  const base = new URL("./", document.baseURI);
  const cacheName = "campus-cats-assets-v1:" + base.pathname;
  let pendingCache;

  function openCache() {
    if (!pendingCache) {
      pendingCache = caches.open(cacheName).catch(() => null);
    }
    return pendingCache;
  }

  async function store(cache, url, copy, asset) {
    // This copy is consumed concurrently with the game. A failed cache write must not
    // delay or cancel the original response, including when the device runs out of space.
    const headers = new Headers(copy.headers);
    headers.set("x-cats-revision-time", String(asset.revision));
    await cache.put(url, new Response(copy.body, {headers}));
    const prefix = new URL("index-", base).href;
    for (const key of await cache.keys()) {
      if (key.url === url || !key.url.startsWith(prefix)) continue;
      const name = key.url.slice(prefix.length);
      if (!/^[a-f0-9]{16}\.(wasm|pck)$/.test(name) || !name.endsWith(asset.suffix)) continue;
      const previous = await cache.match(key);
      const revision = Number(previous?.headers.get("x-cats-revision-time"));
      // A slower, older tab must never evict the assets of a newer release.
      if (previous && revision < asset.revision) await cache.delete(key);
    }
  }

  window.campusCatsFetchAsset = async function(file) {
    const original = new URL(file, document.baseURI);
    const name = original.pathname.slice(base.pathname.length);
    const asset = assets[name];
    if (original.origin !== base.origin || !original.pathname.startsWith(base.pathname)
        || original.search || !Object.prototype.hasOwnProperty.call(assets, name)) {
      return fetch(file);
    }
    const url = new URL(asset.name, base).href;
    let cache;
    try {
      cache = await openCache();
      const hit = cache && await cache.match(url);
      if (hit) return hit;
    } catch {
      // Private browsing or browser storage policy can disallow Cache Storage.
    }
    const response = await fetch(url);
    if (cache && response.status === 200 && response.headers.get("Content-Type")?.split(";")[0] === asset.mime) {
      store(cache, url, response.clone(), asset).catch(() => {});
    }
    return response;
  };
})();