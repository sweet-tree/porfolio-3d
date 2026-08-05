/// Showcase — a procedural 3D tree, generated at runtime, nothing downloaded.
///
/// This file is the app shell and nothing else. The scene lives in
/// `lib/src/scene/`, and the tree's form lives in `lib/src/tree/` as plain
/// Dart with no rendering types in it, so the shape can be reasoned about and
/// tested on its own.
///
/// Current stage: the authored trunk curve. See `lib/src/tree/trunk_path.dart`
/// for what is being decided and `lib/src/scene/trunk_scene.dart` for what is
/// deliberately not built yet.
library;

import 'package:flutter/material.dart';
import 'package:showcase/src/scene/trunk_scene.dart';
import 'package:showcase/src/stats_overlay.dart';

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Showcase',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      // Near-black, as in the reference. Not pure black: a little lift keeps
      // the dark side of the trunk from clipping into the background.
      backgroundColor: const Color(0xFF06060C),
      body: Stack(
        children: [
          const TrunkScene(),
          // Opt-in via ?stats=1 — the numbers that matter come from a real
          // device hitting the real deployment.
          if (statsRequested) const StatsOverlay(),
        ],
      ),
    ),
  );
}
