# flutter_scene 0.20.0 leaks a `ui.Image` every frame on the WebGL2 backend

**Status:** diagnosed, patched locally, confirmed fixed on real hardware.
**Not yet reported upstream.**
**Found:** 2026-08-04 · Flutter 3.44.7 stable · flutter_scene 0.20.0

---

## Summary

On the web backend, `flutter_scene` allocates a new GPU-backed `ui.Image` every
frame and never disposes it. Desktop garbage collection absorbs the churn. iOS
Safari, which caps WebGL memory at roughly 300–500 MB, kills the tab after about
five seconds — regardless of what the scene contains.

A three-line change fixes it.

## Symptom

A `flutter_scene` app on iOS renders normally for ~5 seconds, then Safari
terminates the page ("Safari cannot open the page"). It reproduces with a scene
containing **two** billboard instances, so it is unrelated to scene complexity.

Not affected by: leaf/instance count, bloom, per-frame animation, the procedural
trunk, or COOP/COEP headers. Reproduced in both Safari and Chrome on iOS — which
are the same engine, since iOS requires WebKit.

## Root cause

`lib/src/scene.dart`, in `_presentView` (~line 1173):

```dart
final image = swapchainColor.asImage();
final srcRect = ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height);
final paint = ui.Paint()..filterQuality = view.filterQuality ?? filterQuality;
canvas.drawImageRect(image, srcRect, drawArea, paint);
// image is never disposed
```

On Impeller this is harmless — `asImage()` wraps the existing texture.

On the WebGL2 shim it is not. `Texture.asImage()` reaches
`GpuContext.snapshotTextureSync` (`lib/src/gpu/web/gpu_context.dart`), which does:

1. `_blitTextureToCanvas(texture)` — creates and deletes a framebuffer
2. `_canvas.transferToImageBitmap()` — **allocates a fresh GPU-backed ImageBitmap**
3. wraps that bitmap in a `ui.Image`

So every frame mints a new viewport-sized GPU allocation whose release is left to
the garbage collector.

## Measurements

Instrumented by patching `WebGL2RenderingContext.prototype` factory methods in
`index.html` before Flutter loads, then counting over a fixed window.

Release wasm build, 200 billboard instances, bloom off, wind off, trunk off:

| GL call | Per frame |
|---|---|
| `createTexture` | 1 |
| `deleteTexture` | 1 (GC, lagging) |
| `createFramebuffer` | 2 |
| `deleteFramebuffer` | 2 |
| `createBuffer` | 0 |

Allocation volume, measured via `texStorage2D` / `texImage2D` sizes:

| Viewport | Per frame | At 60 fps |
|---|---|---|
| 390×844 @ dpr 1 | 1.26 MB | **~75 MB/s** |
| 390×844 @ dpr 3 (phone) | ~11.3 MB | **~680 MB/s** |

Against [iOS Safari's ~300–500 MB WebGL ceiling](https://bugnet.io/blog/how-to-fix-unity-webgl-build-crashing-on-safari-ios),
death in ~5 seconds is the expected outcome.

## Control — WebKit is not at fault

A hand-written WebGL2 page (no Flutter): 4,000 instanced alpha-blended quads,
instance buffer re-uploaded every frame, same phone.

**Result: 60 fps, stable for 60+ seconds.**

The difference is that the control allocates its buffers once and reuses them.
This rules out "iOS can't sustain WebGL2".

## The fix

Hold each frame's presented image and dispose it at the start of the next frame.
Disposing immediately after `drawImageRect` would be unsafe — the recorded
picture is rasterized later — so release is deferred by one frame.

```dart
// field on Scene
ui.Image? _previousPresentedImage;

// in _presentView, before minting this frame's image
_previousPresentedImage?.dispose();

final image = swapchainColor.asImage();
final srcRect = ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height);
final paint = ui.Paint()..filterQuality = view.filterQuality ?? filterQuality;
canvas.drawImageRect(image, srcRect, drawArea, paint);
_previousPresentedImage = image;
```

`Scene.dispose()` should also release `_previousPresentedImage` — **not yet done
in our local fork.**

## Verification

iPhone 11, iOS, Chrome (WebKit), JavaScript build (no WasmGC), no cross-origin
isolation — i.e. the slowest available path.

| Build | Result |
|---|---|
| flutter_scene 0.20.0 | tab killed in ~5 s, even with 2 instances |
| Patched | **stable indefinitely at 20,000 instances** with bloom + trunk |

Desktop shows no regression: GL counts identical, deletes become deterministic
(1.000/frame patched vs 1.019/frame via finalizer).

## Local setup

Fork at `scratchpad/flutter_scene_patched`, wired via:

```yaml
dependency_overrides:
  flutter_scene:
    path: ../flutter_scene_patched
```

⚠️ **Removing this override reintroduces the iOS crash.**

---

# Second finding: instance buffer re-uploaded every frame

`BillboardGeometry.bind()` re-uploads the entire instance array through a
transient buffer on **every** frame, whether or not anything changed:

```dart
final liveBytes = ByteData.sublistView(_instanceData, 0, _instanceCount * 14);
pass.bindVertexBuffer(instanceTransients.emplace(liveBytes), slot: 1);
```

At 20,000 instances that is 1.12 MB/frame — ~67 MB/s at 60 fps, for a batch that
may be completely static.

**Patched** in the same fork with a dirty flag plus a persistent `DeviceBuffer`,
re-uploading only when `setInstance`/`commit` touched the data.

**Measured effect: ~1 fps on iPhone 11.** Real and correct, but marginal — it is
dwarfed by the renderer's own traffic (see below). Worth upstreaming as a
tidiness/efficiency fix, not as a performance claim.

| Build | GL upload per frame | Desktop FPS |
|---|---|---|
| Original | 17.08 MB | 60 |
| Dirty-flag patch | 16.01 MB | 60 |

The 1.07 MB delta is exactly the instance data (20,000 × 14 × 4).

---

# ❌ False lead, recorded so nobody repeats it

I measured "~16 MB/frame of GL uploads" and initially attributed it to
`flutter_scene`. **It is not flutter_scene.** It is Flutter's own web renderer.

| App | Big GL uploads/frame |
|---|---|
| Plain Flutter, animating `CustomPaint`, **no flutter_scene** | **81.73 MB** |
| flutter_scene, 200 leaves, no bloom/trunk | 16.00 MB |

The figure was also constant at 16.00 MB across 200 vs 20,000 leaves, bloom on/off
and trunk on/off — content-independent, which should have been the tell.

**Cause of the error:** instrumenting `WebGL2RenderingContext.prototype` patches
the class globally, so it counts Flutter's renderer context *and* the shim's.

**Rule:** when instrumenting WebGL under Flutter, always measure a plain-Flutter
control first.

---

# The remaining architectural win (not attempted)

The engine already exposes a zero-copy path that `flutter_scene` does not use:

```dart
// CanvasKit renderer
skImage = canvasKit.MakeLazyImageFromTextureSourceWithInfo(object, info);  // transferOwnership: true
// vs. the copy path
final bitmap = await createImageBitmap(object, ...);                       // transferOwnership: false
```

Skwasm mirrors this via `imageCreateFromTextureSource`.

`flutter_scene` calls `OffscreenCanvas.transferToImageBitmap()` itself, which by
definition detaches and allocates. Using `createImageFromTextureSource(...,
transferOwnership: true)` would wrap the canvas directly.

**Blocker:** that API is `async` on both renderers, while `asImage()` must be
synchronous inside `paint()`. A fix needs a **ring of OffscreenCanvases plus one
frame of latency** — the same pattern `Surface` already uses for swapchain
textures (`_maxFramesInFlight = 2`).

**Beyond that**, the correct web architecture is a platform view
(`HtmlElementView`) so the browser compositor displays the WebGL canvas directly,
with no per-frame handoff at all. This is what Toyota's
[Fluorite](https://fosdem.org/2026/schedule/event/7ZJJWW-fluorite-game-engine-flutter/)
engine gets natively through Flutter's external texture registry — a facility the
web platform does not have. Fluorite is Vulkan/SDL3/embedded-focused and its web
support is unconfirmed, so it is not an alternative for a web-only project today.

## Performance findings (secondary, not part of the bug report)

Procedural tree: instanced billboard canopy + recursive cylinder trunk.

```
frame = 16.7 ms floor
      + ~3.0 ms for having a canopy batch at all
      + ~1.45 ms per 1,000 leaves
```

| Device | Config | FPS |
|---|---|---|
| Desktop M-series | 20,000 leaves + bloom + wind + trunk | 60 |
| iPhone 11 | 500–1,000 leaves | 46–49 |
| iPhone 11 | 8,000 leaves | 30 |
| iPhone 11 | 20,000 leaves | 20 |

- Bloom, per-frame wind animation, and the alpha leaf texture are all **free**
  (identical FPS with each on or off).
- The procedural trunk is **free** (~300 instanced cylinders; 60 fps on its own).
- 60 fps is **unreachable on iPhone 11 with any canopy** — the batch costs ~3 ms.
- CPU cost of animating 4,000 instances per frame: **0.26 ms**.

### Leaf size dominates leaf count

At a fixed 20,000 leaves on iPhone 11:

| Leaf size | FPS | Cost above 16.7 ms floor |
|---|---|---|
| 1.0 | 20 | 33.3 ms |
| 0.5 | **30** | 16.6 ms |
| 0.25 | 40 | 8.3 ms |

Cost halves when size halves — it scales with leaf *width*, roughly
`cost ≈ 33.4 × size` at 20k, intercept ≈ 0.

But coverage scales with `count × size²` while cost scales with `count × size`.
So **for constant visual density, smaller leaves are worse**: halving size needs
4× the leaves to hold coverage, which doubles the cost. Smaller only wins while
the canopy is *over*-covered.

### Framing dominates all of it

The measurements above hold the camera fixed. Change how much of the SCREEN the
tree covers and everything moves:

| Framing (same scene, same leaves) | FPS |
|---|---|
| tree small in a portrait frame | 57 |
| tree filling a landscape frame | 27 |

So fill rate is the real cost model, and any budget stated as a leaf count is
meaningless without saying how large the tree is on screen. Fitting the camera to
a portrait viewport took 32 fps to 57 *and* stopped the crown being cropped —
composition and performance are the same decision here.

**Real iPhone 11, production HTTPS, portrait full-screen: 35 fps**, JavaScript
build, `crossOriginIsolated: true`. That supersedes every LAN and emulated figure
above.

### Current configuration

**8,000 leaves at size 0.8** — same coverage as 20,000 @ 0.5 for about a third
less work (60 fps against 37 in landscape). Tunable at runtime via
`?leaves=&size=`.

Treat it as provisional: the canopy is going to be rebuilt around the branch
structure (see `reference/README.md`), and the right numbers will be different.

## Open questions before filing

- Does `Scene.dispose()` need the same release? (Almost certainly yes.)
- Would the maintainer prefer reusing one ImageBitmap over disposing per frame?
  That would remove the churn as well as the leak, but is a larger change.
- Do `RenderTexture` and `render_texture_view.dart` (which also call `asImage()`)
  have the same problem?

## Prior art referenced

- [iOS Safari WebGL memory limits](https://bugnet.io/blog/how-to-fix-unity-webgl-build-crashing-on-safari-ios)
- [Unity WebGL memory growth on iOS](https://discussions.unity.com/t/webgl-memory-increment-issue-and-crash-on-ios/894771)
- [Apple: resizing a WebGL canvas leaks on iOS Safari](https://developer.apple.com/forums/thread/668999)
- [bdero/flutter_scene issues](https://github.com/bdero/flutter_scene/issues) — nothing matching, as of 2026-08-04
