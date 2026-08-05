/// Sweeping the trunk's surface along its centre line.
///
/// `TubeGeometry` would be the obvious tool and it cannot do this job: it drags
/// a **rigid circle** along the curve, so wherever the curve bends tighter than
/// the circle's own radius the inner wall passes through the axis and out the
/// far side. The surface self-intersects and renders as a folded shell. The
/// fatter the trunk, the straighter it is forced to be — which is the opposite
/// of what a massive tree looks like.
///
/// Real trunks bend hard all the time. They manage it because they are not
/// rigid: the wood compresses on the inside of a bend and stretches on the
/// outside, so the cross-section flattens as it goes round. This sweep does the
/// same thing, and the limit disappears.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:showcase/src/tree/trunk_form.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Builds the trunk's surface for [form].
///
/// [stations] cross-sections along the length, [radialSegments] points around
/// each. Texture coordinates run `0..1` around the trunk and by arc-length
/// distance along it, so bark will not stretch where the trunk bends.
MeshGeometry buildTrunkMesh(
  TrunkForm form, {
  int stations = 96,
  int radialSegments = 28,
}) {
  final path = form.toPath();
  final total = path.length;

  final frames = <ScenePathFrame>[
    for (var i = 0; i < stations; i++)
      path.frameAtDistance(total * i / (stations - 1)),
  ];

  // Which way each station bends, and how hard. The curvature vector points at
  // the centre of the turn, which is the INSIDE of the bend — the side that has
  // to give way.
  final bendDir = List<vm.Vector3>.filled(stations, vm.Vector3.zero());
  final bendAmount = List<double>.filled(stations, 0);
  for (var i = 1; i < stations - 1; i++) {
    final span = (frames[i + 1].position - frames[i - 1].position).length / 2;
    if (span < 1e-6) continue;
    final turn = frames[i + 1].tangent - frames[i - 1].tangent;
    final curvature = turn.length / (2 * span);
    if (curvature < 1e-6) continue;
    bendDir[i] = turn.normalized();
    bendAmount[i] = curvature;
  }
  bendDir[0] = bendDir[1];
  bendAmount[0] = bendAmount[1];
  bendDir[stations - 1] = bendDir[stations - 2];
  bendAmount[stations - 1] = bendAmount[stations - 2];

  final ringCount = radialSegments + 1; // duplicate seam vertex for clean UVs
  final vertexCount = stations * ringCount;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  for (var i = 0; i < stations; i++) {
    final t = i / (stations - 1);
    final frame = frames[i];
    final radius = form.radiusAt(t);
    final v = total * t;

    // No fold-avoidance needed here: `TrunkForm.toPath` has already relaxed the
    // curve so no bend is tighter than the trunk is wide. An earlier version
    // tried to fix it at this level by shifting each cross-section sideways,
    // and it produced garbage — each station compensated on its own, so the
    // centreline lurched about and the base came out as a torn skirt. A
    // constraint belongs on the curve, once, not on every slice after the fact.
    //
    // What is left here is cosmetic: bent wood compresses on the inside of the
    // bend, and that flattening is most of what makes a bend read as a bend.
    final pressure = (bendAmount[i] * radius).clamp(0.0, 1.0);
    final give = form.squash.clamp(0.0, 1.0) * pressure * 0.35;
    // The bend direction in the cross-section's own plane.
    final insideN = bendDir[i].dot(frame.normal);
    final insideB = bendDir[i].dot(frame.binormal);

    for (var k = 0; k <= radialSegments; k++) {
      final angle = 2 * math.pi * k / radialSegments;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      // +1 on the inside of the bend, -1 on the outside.
      final facing = cos * insideN + sin * insideB;
      final scale = 1 - give * math.max(0.0, facing);

      final radial = frame.normal * cos + frame.binormal * sin;
      final position = frame.position + radial * (radius * scale);

      final vi = (i * ringCount + k) * 3;
      positions[vi] = position.x;
      positions[vi + 1] = position.y;
      positions[vi + 2] = position.z;

      final ti = (i * ringCount + k) * 2;
      texCoords[ti] = k / radialSegments;
      texCoords[ti + 1] = v;
    }
  }

  // Normals from the surface itself rather than from the radial direction: the
  // squash and the taper both tilt the surface away from radial, and shading it
  // as a plain cylinder would flatten exactly the compression this sweep exists
  // to produce.
  final indices = <int>[];
  for (var i = 0; i < stations - 1; i++) {
    for (var k = 0; k < radialSegments; k++) {
      final a = i * ringCount + k;
      final b = a + 1;
      final c = (i + 1) * ringCount + k;
      final d = c + 1;
      // Counter-clockwise seen from OUTSIDE, which is the winding the engine
      // treats as front-facing (the glTF convention). Getting this backwards
      // does not look like a lighting bug — the outer surface is culled and you
      // see the far inner wall instead, which reads as a shape folded through
      // itself. That cost most of a session: check the winding before
      // suspecting the geometry.
      indices
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(b)
        ..add(d)
        ..add(c);
    }
  }
  _accumulateNormals(positions, indices, normals);
  _weldSeamNormals(normals, stations, ringCount, radialSegments);

  return MeshGeometry.fromArrays(
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    indices: indices,
  );
}

// Area-weighted face normals summed onto their vertices, then normalized.
void _accumulateNormals(
  Float32List positions,
  List<int> indices,
  Float32List normals,
) {
  final ab = vm.Vector3.zero();
  final ac = vm.Vector3.zero();
  final face = vm.Vector3.zero();
  for (var i = 0; i < indices.length; i += 3) {
    final a = indices[i] * 3;
    final b = indices[i + 1] * 3;
    final c = indices[i + 2] * 3;
    ab.setValues(
      positions[b] - positions[a],
      positions[b + 1] - positions[a + 1],
      positions[b + 2] - positions[a + 2],
    );
    ac.setValues(
      positions[c] - positions[a],
      positions[c + 1] - positions[a + 1],
      positions[c + 2] - positions[a + 2],
    );
    ab.crossInto(ac, face);
    for (final v in <int>[a, b, c]) {
      normals[v] += face.x;
      normals[v + 1] += face.y;
      normals[v + 2] += face.z;
    }
  }
  for (var v = 0; v < normals.length; v += 3) {
    final x = normals[v];
    final y = normals[v + 1];
    final z = normals[v + 2];
    final length = math.sqrt(x * x + y * y + z * z);
    if (length < 1e-9) {
      normals[v + 1] = 1;
      continue;
    }
    normals[v] = x / length;
    normals[v + 1] = y / length;
    normals[v + 2] = z / length;
  }
}

// The first and last vertex of each ring share a position but are separate
// vertices, so each collects only the faces on its own side and the seam shows
// as a visible line. Averaging the pair closes it.
void _weldSeamNormals(
  Float32List normals,
  int stations,
  int ringCount,
  int radialSegments,
) {
  for (var i = 0; i < stations; i++) {
    final first = (i * ringCount) * 3;
    final last = (i * ringCount + radialSegments) * 3;
    for (var c = 0; c < 3; c++) {
      final averaged = (normals[first + c] + normals[last + c]) / 2;
      normals[first + c] = averaged;
      normals[last + c] = averaged;
    }
  }
}
