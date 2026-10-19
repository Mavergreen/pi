# Build ingredients

Everything Mavergreen/pi (`dev.mavergreen.pi`, installed at `/usr/local/mavergreen/pi`) depends on, and how a change to it reaches a release.

Pi itself is never shipped: the launcher seeds it on the user's Mac into Pi's own managed-install tree. The package carries the launcher, a 10.9 build of Pi's native addon, the addon-source-id and the requires list.

## Runtime requires

Verified present before launch (`share/pi/requires`); a missing one fails with its release URL.

- node24
- fd
- rg

## Build ingredients

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Pi (`@earendil-works/pi-coding-agent`, npm), the upstream the launcher seeds | `UPSTREAM_VERSION` | ✅ custom manager, `npm` datasource on `@earendil-works/pi-coding-agent` | nothing publishes on the push: the nightly reconcile dispatches `release.yml` once `release-needed.sh` says PUBLISH, which cuts `<new>-mavericks.1` |
| pi-tui tarball, derived: its native sources build the 10.9 addon | Pi's installer release manifest for `UPSTREAM_VERSION`, verified by npm `dist.integrity` | ✅ follows Pi: re-derived whenever `UPSTREAM_VERSION` moves | the addon-source-id is recomputed; a source change rebuilds the addon |
| MacOSX10.9 SDK, CMake modules, compat guard, packaging and signing scripts | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` moves without the pin changing, so nothing repackages by itself |
| Sparkle, in the updater | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there | ❌ untrackable here: shipyard owns that pin | follows shipyard |
| node24, CI only: the runtime `tests/addon-compat-test.sh` loads the built addon with in the release job | `components/node24/version`, a `Mavergreen/nodejs-24` release tag | ✅ custom manager, `github-releases` with `-mavericks.N` versioning | CI tests against the new node24; nothing is shipped from it, so nothing republishes |

No shipped ingredient is pinned in a file of its own: the pi-tui source the addon is built from follows `UPSTREAM_VERSION`, and everything else comes with shipyard. `components/node24/version` is a file, but it pins only what CI tests with, so it stays out of the declared state. So there is no `repackage-on-ingredient-bump` caller; a packaging-only release is a `workflow_dispatch` with `repackage`.

## Declared state

- upstream: UPSTREAM_VERSION

## Conformance deviations

- rosetta:.github/workflows/release.yml: the release job runs on an Apple Silicon (arm64) runner and primes Rosetta ("Ensure this runner can run x86_64 (Rosetta)"), then installs node24's released .pkg, so the tests step can run the x86_64 node24 that loads Pi's addon on 10.9 and have it dlopen the addon this release ships. It cannot run natively: node24 is x86_64-only, the addon under test is the shipped x86_64 one, and the release runner is arm64 with no Intel runner to use instead. Native 10.9 users load the addon natively; only this arm64 CI leg is translated. Reconsider when the check can move to an x86_64 host (the 10.9 box, an Intel runner, or the Mavericks VM runner the family is bringing to GitHub Actions); at the latest before macOS 28 removes Rosetta.
- rosetta:tests/addon-compat-test.sh: runs node24 (x86_64) to `process.dlopen` the built `darwin-platform.node` and checks it exposes isModifierPressed, getText, setText, getImage and getFilePaths, proving the 10.9 addon loads in the runtime that ships it. On the arm64 release runner that execution is translated by Rosetta, and under CI the test fails rather than skips when node24 is absent, so Rosetta is a required dependency there; off CI, a host without an x86_64 node24 says the check was not exercised. It cannot run natively: node24 and the addon are x86_64 by nature. Reconsider when an x86_64 host can run it in CI; at the latest before macOS 28 removes Rosetta.
- on-target: no 10.9 acceptance job yet; exit: a release.yml job on Mavergreen/mavericks-vm@v1 that installs this run's pkg in the guest and runs what it ships, which publish needs

## Upstream release notes

Pi's notes for a version live at `https://github.com/earendil-works/pi/releases/tag/v<version>`; `build/upstream-release-notes-url.sh` prints that link.
