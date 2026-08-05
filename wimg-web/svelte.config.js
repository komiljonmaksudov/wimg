import adapter from "@sveltejs/adapter-static";

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // Static SPA — the app is client-only (`export const ssr = false` in
    // src/routes/+layout.ts) and has no server routes, so there is nothing to
    // run at request time. Output is plain files served by Caddy on the VPS.
    //
    // NOTE: with no runtime server, src/hooks.server.ts no longer executes, so
    // the COOP/COEP headers it used to set must come from the host. They're set
    // in infra/wimg-web.caddy (VPS) and static/_headers (Cloudflare Pages,
    // until that's decommissioned). Without them OPFS/SharedArrayBuffer break.
    adapter: adapter({
      fallback: "index.html", // SPA fallback — client router owns every path
      precompress: true, // emit .br/.gz next to each asset; Caddy serves them
    }),
    version: {
      pollInterval: 5 * 60 * 1000, // check for new deployment every 5 minutes
    },
  },
};

export default config;
