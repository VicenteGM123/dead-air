// DEAD AIR web build: cross-origin isolation service worker (the coi-serviceworker approach).
// The threaded Godot build needs SharedArrayBuffer, i.e. a cross-origin isolated page (COOP + COEP headers), and
// GitHub Pages cannot send custom headers. This worker re-serves every request of its scope (the godot-web/ folder)
// with those headers; web/shell.html registers it and reloads once it controls the page. No caching: the browser's
// HTTP cache works as usual, so a new build is picked up on the next load. Copied next to index.html by
// godot/web/export_web.sh.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
	const req = event.request;
	if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') {
		return;
	}
	event.respondWith(fetch(req).then((res) => {
		if (res.status === 0) {
			return res;   // opaque response: pass it through untouched
		}
		const headers = new Headers(res.headers);
		headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
		headers.set('Cross-Origin-Opener-Policy', 'same-origin');
		headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
		return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
	}).catch((err) => {
		console.error('[coi-sw] fetch failed', err);
		return Response.error();
	}));
});
