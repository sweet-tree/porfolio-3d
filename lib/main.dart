// Showcase — 3D hero probe.
//
// Replaces the Flutter counter boilerplate with a live flutter_scene render, to
// see real GPU 3D running in the browser on the STABLE channel.
//
// On web, flutter_scene uses its own WebGL2 backend (Impeller and Flutter GPU
// are not available in the browser). No master channel, no flags.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Showcase',
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Color(0xFF0B0B10), body: HeroScene()),
  );
}

class HeroScene extends StatefulWidget {
  const HeroScene({super.key});

  @override
  State<HeroScene> createState() => _HeroSceneState();
}

class _HeroSceneState extends State<HeroScene> {
  final Scene scene = Scene();
  bool ready = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      // Shader bundle and BRDF lookup table load asynchronously; nothing can be
      // rendered before this completes.
      await Scene.initializeStaticResources();

      // A ring of cubes around the origin, plus a torus through them. Built
      // from primitive geometry so there is no glTF asset to ship.
      const count = 8;
      for (var i = 0; i < count; i++) {
        final angle = i / count * math.pi * 2;
        scene.add(
          Node(
            name: 'cube$i',
            localTransform: vm.Matrix4.translationValues(
              math.cos(angle) * 2.2,
              0,
              math.sin(angle) * 2.2,
            )..rotateY(angle),
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(0.7, 0.7, 0.7), debugColors: true),
              UnlitMaterial(),
            ),
          ),
        );
      }
      scene.add(
        Node(
          name: 'torus',
          mesh: Mesh(
            TorusGeometry(radius: 2.2, tubeRadius: 0.08),
            UnlitMaterial(),
          ),
        ),
      );

      if (mounted) setState(() => ready = true);
    } on Object catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scene failed to initialise:\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 15),
          ),
        ),
      );
    }
    if (!ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        SceneView(
          scene,
          // Camera orbits the origin; `elapsed` drives it directly, so there
          // is no AnimationController to manage.
          cameraBuilder: (elapsed) {
            final t = elapsed.inMilliseconds / 1000.0;
            return PerspectiveCamera(
              position: vm.Vector3(
                math.cos(t * 0.35) * 6.5,
                2.4 + math.sin(t * 0.5) * 1.2,
                math.sin(t * 0.35) * 6.5,
              ),
              target: vm.Vector3.zero(),
            );
          },
        ),
        const Positioned(
          left: 28,
          bottom: 28,
          child: Text(
            'flutter_scene 0.20.0  ·  WebGL2  ·  stable channel',
            style: TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 13,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}
