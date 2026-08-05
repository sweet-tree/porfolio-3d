/// The hero scene, at its first stage: the trunk section, and nothing else.
///
/// ## Why this is declarative
///
/// The scene is described in `build()` with [SceneView.declarative],
/// [SceneNode] and [SceneMesh], and the engine identity-diffs the result the
/// way Flutter diffs widgets. Motion, when it arrives, goes in [Component]
/// subclasses that mutate engine objects in place — never in a rebuild.
/// flutter_scene's own examples put it as *"rebuild for structure, mutate for
/// motion"*, and it is the reason this file can grow to hold a whole tree,
/// falling leaves and sliding walls without turning into one imperative
/// `initState` that builds everything.
///
/// The corollary, and the one real hazard of the declarative layer: geometry
/// and materials are GPU resources. They are built once here and rebuilt only
/// when the shape actually changes, never per frame.
///
/// ## What is deliberately NOT here yet
///
/// No bark, no vines, no emissive veins, no post-processing, no wind. The
/// lighting below is three lights placed to make form legible — it is not the
/// studio rig, and it is not trying to look like the reference.
library;

import 'dart:math' as math;

// `hide Material` so the Flutter one wins here, matching the gallery examples;
// flutter_scene's Material is reached through the alias below.
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene/scene.dart' as fs show Material;
import 'package:showcase/src/query_params.dart';
import 'package:showcase/src/scene/tune_panel.dart';
import 'package:showcase/src/tree/trunk_form.dart';
import 'package:showcase/src/tree/trunk_mesh.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Vertical field of view. The horizontal one follows from this and the
/// viewport's aspect ratio at render time.
const double _fovY = 40 * math.pi / 180;

/// Padding around the subject, as a multiple of the fitted distance.
const double _framingMargin = 1.12;

/// True when the page was opened with `?tune=1`.
bool get tuningRequested => qFlag('tune');

class TrunkScene extends StatefulWidget {
  const TrunkScene({super.key});

  @override
  State<TrunkScene> createState() => _TrunkSceneState();
}

class _TrunkSceneState extends State<TrunkScene> {
  TrunkForm _form = const TrunkForm();
  bool _lockCamera = false;

  /// Camera distance held across shape changes while the camera is locked, so
  /// height and diameter visibly change the trunk's size instead of the camera
  /// quietly compensating for them.
  double? _lockedDistance;

  late Geometry _geometry = buildTrunkMesh(_form);

  /// Neutral and matte. Colour and gloss are decisions for the bark stage;
  /// here they would only get in the way of reading the shape.
  late final fs.Material _formMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.42, 0.40, 0.44, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.78;

  /// Three lights, placed to read form rather than to look like anything:
  /// a warm key high on the left, a cool rim behind each shoulder to separate
  /// the silhouette from the background, and no fill — the shadow side is
  /// meant to go dark so the trunk's depth is visible.
  late final DirectionalLight _key = DirectionalLight(
    direction: vm.Vector3(-0.55, -0.75, -0.36)..normalize(),
    color: vm.Vector3(1, 0.95, 0.88),
    intensity: 2.6,
  );
  late final PointLight _rimLeft = PointLight(
    color: vm.Vector3(0.62, 0.78, 1),
    intensity: 9,
    range: 14,
  );
  late final PointLight _rimRight = PointLight(
    color: vm.Vector3(0.78, 0.70, 1),
    intensity: 7,
    range: 14,
  );

  void _applyForm(TrunkForm form) {
    setState(() {
      _form = form;
      _geometry = buildTrunkMesh(form);
    });
  }

  /// Axis-aligned bounds of the trunk, derived from the form rather than from
  /// constants — so reshaping it can never leave the framing stale.
  ({vm.Vector3 centre, vm.Vector3 half}) get _bounds {
    final minV = vm.Vector3.all(double.infinity);
    final maxV = vm.Vector3.all(-double.infinity);
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = _form.axisAt(t);
      final r = vm.Vector3.all(_form.radiusAt(t));
      vm.Vector3.min(minV, p - r, minV);
      vm.Vector3.max(maxV, p + r, maxV);
    }
    return (
      centre: (minV + maxV).scaled(0.5),
      half: (maxV - minV).scaled(0.5),
    );
  }

  /// A static camera that frames the subject at the given viewport [aspect].
  ///
  /// Each axis is fitted **separately** and the camera takes whichever distance
  /// is larger. Fitting a bounding *sphere* instead is the obvious approach and
  /// it is wrong for anything that is not roughly cube-shaped: a trunk is tall
  /// and thin, so its sphere is nearly as wide as the trunk is tall, and
  /// squeezing that sphere into a phone's narrow horizontal field shoves the
  /// camera far enough back to leave the trunk small in the middle of an empty
  /// screen. Portrait is the case that exposes it, and portrait is the case
  /// that matters most here.
  Camera _cameraFor(double aspect, ({vm.Vector3 centre, vm.Vector3 half}) b) {
    final fovX = 2 * math.atan(math.tan(_fovY / 2) * aspect);
    final fitted =
        math.max(
              b.half.y / math.tan(_fovY / 2),
              b.half.x / math.tan(fovX / 2),
            ) *
            _framingMargin +
        // The near face of a subject with depth is closer than its centre.
        b.half.z;

    // Locked: hold the first fitted distance. Without this, making the trunk
    // taller just moves the camera back and nothing appears to change, which
    // makes the height and diameter sliders useless to judge by.
    final distance = _lockCamera ? (_lockedDistance ??= fitted) : fitted;
    if (!_lockCamera) _lockedDistance = null;

    return PerspectiveCamera(
      fovRadiansY: _fovY,
      // Straight on, very slightly above the midpoint, matching the
      // reference's eye level. The camera does not move — the vision calls for
      // a still frame in which only the tree is alive.
      position: vm.Vector3(
        b.centre.x,
        b.centre.y + b.half.y * 0.06,
        b.centre.z + distance,
      ),
      target: b.centre,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds;
    // Lights are placed off the subject's own size, so they stay in the same
    // relation to it whatever the trunk is reshaped to.
    final reach = bounds.half.y;
    final rimDepth = bounds.centre.z - reach * 0.9;

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final aspect = constraints.maxHeight <= 0
                ? 1.0
                : constraints.maxWidth / constraints.maxHeight;

            return SceneView.declarative(
              // The built-in studio environment, dimmed hard so the three
              // lights above carry the image instead of a flat ambient wash.
              environmentIntensity: 0.30,
              exposure: 1.25,
              camera: _cameraFor(aspect, bounds),
              children: [
                SceneNode(
                  name: 'key',
                  components: [DirectionalLightComponent(_key)],
                ),
                SceneNode(
                  name: 'rim-left',
                  position: vm.Vector3(
                    bounds.centre.x - reach * 0.8,
                    bounds.centre.y + reach * 0.25,
                    rimDepth,
                  ),
                  components: [PointLightComponent(_rimLeft)],
                ),
                SceneNode(
                  name: 'rim-right',
                  position: vm.Vector3(
                    bounds.centre.x + reach * 0.85,
                    bounds.centre.y - reach * 0.1,
                    rimDepth,
                  ),
                  components: [PointLightComponent(_rimRight)],
                ),
                SceneMesh(
                  name: 'trunk',
                  geometry: _geometry,
                  material: _formMaterial,
                ),
              ],
            );
          },
        ),
        if (tuningRequested)
          TunePanel(
            form: _form,
            onChanged: _applyForm,
            lockCamera: _lockCamera,
            onLockCameraChanged: (value) => setState(() => _lockCamera = value),
          ),
      ],
    );
  }
}
