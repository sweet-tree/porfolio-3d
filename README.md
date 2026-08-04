# Showcase

A procedural 3D tree, generated and rendered in the browser. Flutter, web only.

**Live: https://porfolio-3d-3gm.pages.dev**

Nothing is downloaded to draw it — the branch structure, the leaf texture and
the per-leaf shading are all generated at runtime. A visitor downloads **1.98 MB**
(Brotli): 0.53 MB of application and 1.45 MB of renderer.

Runs at 60 fps on desktop and **35 fps on an iPhone 11**.

---

## Running it

```bash
make dev-dtd     # development, with live tooling — see below
make build       # release build (WebAssembly)
make serve       # serve the release build locally, with COOP/COEP
make check       # analyze + test
make size        # what a visitor actually downloads
```

### URL switches

| Parameter | Effect |
|---|---|
| `?stats=1` | on-screen FPS, worst FPS, build type, isolation, viewport |
| `?leaves=8000` | canopy instance count |
| `?size=0.8` | leaf size multiplier |

Density is URL-tunable so it can be measured on a real device instead of guessed
at in source.

---

## Architecture

| Path | What |
|---|---|
| `lib/main.dart` | the scene: trunk, canopy, shading, camera framing |
| `lib/src/leaf_texture.dart` | procedural leaf blade (tested) |
| `lib/src/stats_overlay.dart` | `?stats=1` readout |
| `lib/src/query_params.dart` | URL tuning switches |
| `third_party/flutter_scene/` | **patched fork — see below** |
| `docs/reference/` | the design target |
| `web/_headers` | COOP/COEP and cache policy |

### ⚠️ `third_party/flutter_scene` is load-bearing

`pubspec.yaml` has a `dependency_overrides` pointing at a local fork of
`flutter_scene` 0.20.0 with two patches. **Removing it reintroduces a crash that
kills the page on iOS in about five seconds.**

The published version leaks a `ui.Image` every frame on its WebGL2 backend —
harmless on Impeller, fatal on web, where each call allocates a fresh GPU image.
Roughly 680 MB/s at phone pixel ratios, against iOS Safari's ~300–500 MB ceiling.

Full diagnosis, measurements and the fix: [`docs/flutter-scene-web-leak.md`](docs/flutter-scene-web-leak.md).
Not yet reported upstream.

---

## What actually costs frames

**Fill rate — how much of the screen the tree covers.** Not leaf count. The same
scene runs at 57 fps when the tree is small in frame and 27 fps when it fills it.

Consequences:

- Cost scales as `count × size`, coverage as `count × size²`. For a fixed visual
  density, **fewer larger leaves are cheaper**.
- Camera framing is a performance decision, not just composition. Fitting the
  tree to a portrait viewport took 32 fps to 57.
- **Bloom, wind and the alpha leaf texture each cost nothing measurable.** They
  are all on.
- The procedural trunk is free (~300 instances, one draw call).

---

## Development

`flutter run -d chrome` publishes no Dart Tooling Daemon from the CLI, so the
widget tree, runtime errors and agent-driven hot reload are all unavailable
there. `make dev-dtd` uses `-d web-server` instead, which does publish one —
open the URL in Chrome and click the Dart logo
([Dart Debug Extension](https://chromewebstore.google.com/detail/dart-debug-extension/eljbmlghnomdjgdjmbdekegdkbabckhm))
to attach.

`flutter_driver` does not work on web, so screenshots come from Playwright
driving the served build. Playwright's Chromium always takes the WebAssembly
path; to see what iOS sees, drive WebKit directly.

---

## Deployment

Push to `main` → GitHub Action → Cloudflare Pages. Pull requests get their own
preview URL. The Action pins Flutter, runs analyze and tests, builds, and
asserts `_headers` survived before deploying.

Two things that will waste an afternoon if forgotten:

- **Hash-prefixed URLs like `92ff37f1.porfolio-3d-3gm.pages.dev` are frozen
  snapshots.** They never update. Only ever use the plain alias.
- **Flutter's web output is not content-hashed** — `main.dart.wasm` keeps its
  name while its contents change. Never cache it as `immutable`; `web/_headers`
  makes everything revalidate for exactly this reason.

The service worker is deliberately disabled (`web/index.html` is hand-written and
registers none), because it serves the previous build to returning visitors.
