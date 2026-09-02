import { defineConfig } from 'vitest/config'

// Node 22.4+ ships a global `localStorage` (the --webstorage flag, on by
// default as of Node 24+). It shadows jsdom's window.localStorage in the
// test process, silently breaking storage-backed tests (e.g. clear() is
// missing). `--no-experimental-webstorage` disables it so jsdom's own
// Storage implementation populates globalThis as expected — but the flag
// itself doesn't exist before Node 22.4, and an unrecognized Node CLI flag
// crashes the process outright, so only pass it on Node versions that
// support it (CI pins Node 20 — see .github/workflows/frontend-ci.yml).
const [nodeMajor, nodeMinor] = process.versions.node.split('.').map(Number)
const supportsWebstorageFlag = nodeMajor > 22 || (nodeMajor === 22 && nodeMinor >= 4)

// Kept separate from vite.config.js so the dev/build server config stays
// minimal and test-only options never leak into the app bundle.
export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.js'],
    css: false,
    // NOTE: in Vitest 4 this must be a top-level `execArgv`, not nested
    // under `poolOptions.forks` — the old nested form is silently ignored
    // (see the "test.poolOptions was removed in Vitest 4" deprecation
    // warning), which was letting this workaround silently do nothing.
    execArgv: supportsWebstorageFlag ? ['--no-experimental-webstorage'] : [],
  },
})
