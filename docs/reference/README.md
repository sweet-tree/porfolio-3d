# Design reference

The image itself is **not in this repository** — it is licensed Adobe Stock and
`.gitignore` excludes `docs/reference/*.{jpeg,jpg,png}`. Only this description
is committed.

- File: `tree-reference.jpeg` (AdobeStock_559104745, 3072×2048)
- Source on the owner's machine: `~/Documents/Assets/AdobeStock_559104745.jpeg`
- Copy it back into this folder to view it: it will be ignored, not committed.

## What we are taking from it

Not a copy target. Read at full resolution — the small version misleads.

**1. The branch network IS the subject.** A braided, S-curving trunk fans into
limbs that spread across the whole crown and stay visible right out to the
silhouette edge. Foliage clusters at the branch TIPS. This is a branch structure
with leaves on it, not a canopy with a trunk underneath.
→ Ours is a sphere of leaves that happens to sit above a thin trunk. Different
structure, not a polish gap.

**2. The roots are architecture.** Roughly a quarter of the image: a spreading
braided root mass with dark cave-like hollows, on a small mound with grass and
glowing embers. They give the tree its weight and anchor the composition.
→ We have none.

**3. The glow is light BETWEEN the branches.** Teal pours from behind the trunk
near the base; hot orange sits in pockets in the gaps between limbs. It reads as
light sources inside the tree shining out through the foliage.
→ Our bloom just makes leaves brighter, which is a different effect.

**4. Colour zones are large and distinct** — magenta left, blue centre-top,
olive-green right-top, teal right, orange in the interior. Regions with edges,
not a smooth gradient.

**5. Real darkness.** Near-black background, dark canopy interior. The dark
interior is what makes the eye read volume rather than a silhouette.

**6. Silhouette:** the overall dome is fairly regular; the irregularity is fine
twiggy fringe at the edge. Petals drift slowly, few at a time.

Proportions: canopy ~⅔ of the height, trunk and roots ~⅓.

## Where ours already goes further

The reference is a still. Ours moves, and is generated procedurally at runtime —
no model, no textures, nothing downloaded. See `../../lib/main.dart` and
`../flutter-scene-web-leak.md`.

## Licensing

Adobe Stock, design reference only. Never shipped in the app; nothing in `web/`
or `lib/` loads it. Deliberately gitignored: a standard Stock licence covers
using an image *within* a work, not redistributing the source file — and a
public repository is redistribution.
