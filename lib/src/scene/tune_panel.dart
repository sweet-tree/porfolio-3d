/// The live tuning panel, shown only with `?tune=1`.
///
/// It exists because the alternative is me changing one number, rebuilding,
/// looking at a screenshot, and guessing again — which is the slowest possible
/// way to make a visual decision. Sliders put the judgement where it belongs.
///
/// The **Copy Dart** button is the part that matters most: it emits the current
/// values as source that pastes straight into `TrunkForm`, so a decision made
/// by eye becomes code without anyone reading numbers off a screen.
///
/// Modelled on the gallery's `example_panel.dart` / `lighting_panel.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:showcase/src/tree/trunk_form.dart';

class TunePanel extends StatelessWidget {
  const TunePanel({
    required this.form,
    required this.onChanged,
    required this.lockCamera,
    required this.onLockCameraChanged,
    super.key,
  });

  final TrunkForm form;
  final ValueChanged<TrunkForm> onChanged;

  /// When true the camera holds still, so height and diameter visibly change
  /// the trunk's size. The auto-fitting camera the real site uses hides that
  /// completely: make the trunk taller and the camera simply backs away.
  final bool lockCamera;
  final ValueChanged<bool> onLockCameraChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 300,
            child: _PanelCard(
              title: 'Trunk',
              subtitle: '${form.slenderness.toStringAsFixed(2)} : 1',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Lock camera',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Switch(value: lockCamera, onChanged: onLockCameraChanged),
                    ],
                  ),
                  _Slider(
                    label: 'Height',
                    value: form.height,
                    min: 0.5,
                    max: 6,
                    onChanged: (v) => onChanged(form.copyWith(height: v)),
                  ),
                  _Slider(
                    label: 'Base diameter',
                    value: form.baseDiameter,
                    min: 0.1,
                    max: 3,
                    onChanged: (v) => onChanged(form.copyWith(baseDiameter: v)),
                  ),
                  _Slider(
                    label: 'Top diameter',
                    value: form.topDiameter,
                    min: 0.05,
                    max: 3,
                    onChanged: (v) => onChanged(form.copyWith(topDiameter: v)),
                  ),
                  const _Heading('Bend'),
                  _Slider(
                    label: 'Lean',
                    value: form.lean,
                    min: 0,
                    max: 1.5,
                    onChanged: (v) => onChanged(form.copyWith(lean: v)),
                  ),
                  _Slider(
                    label: 'Lean height',
                    value: form.leanHeight,
                    min: 0.1,
                    max: 0.9,
                    onChanged: (v) => onChanged(form.copyWith(leanHeight: v)),
                  ),
                  _Slider(
                    label: 'Counter-lean',
                    value: form.counterLean,
                    min: 0,
                    max: 1.5,
                    onChanged: (v) => onChanged(form.copyWith(counterLean: v)),
                  ),
                  _Slider(
                    label: 'Depth turn',
                    value: form.depthTurn,
                    min: -1,
                    max: 1,
                    onChanged: (v) => onChanged(form.copyWith(depthTurn: v)),
                  ),
                  _Slider(
                    label: 'Squash on bends',
                    value: form.squash,
                    min: 0,
                    max: 1,
                    onChanged: (v) => onChanged(form.copyWith(squash: v)),
                  ),
                  const _Heading('Root flare'),
                  _Slider(
                    label: 'Flare width',
                    value: form.flareWidth,
                    min: 0,
                    max: 3,
                    onChanged: (v) => onChanged(form.copyWith(flareWidth: v)),
                  ),
                  _Slider(
                    label: 'Flare height',
                    value: form.flareHeight,
                    min: 0.02,
                    max: 1.5,
                    onChanged: (v) => onChanged(form.copyWith(flareHeight: v)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Dart'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: form.toDartSource()),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text('Copied — paste it to me'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => onChanged(const TrunkForm()),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelCard extends StatefulWidget {
  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  State<_PanelCard> createState() => _PanelCardState();
}

class _PanelCardState extends State<_PanelCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Height against thickness, live. Absolute size means nothing
                  // on its own once the camera reframes; this ratio is the
                  // thing that actually decides whether it reads as massive.
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF7FD4FF),
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: Colors.white24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: widget.child,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
