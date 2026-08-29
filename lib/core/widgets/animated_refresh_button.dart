import 'package:flutter/material.dart';

/// A refresh icon that spins for the duration of [onRefresh] instead of
/// sitting static while the underlying data reloads. Drop-in replacement for
/// a plain `Icon(Icons.refresh)` wrapped in a tap handler — pass an optional
/// [decoration]/[padding] to keep whatever chip/box styling the call site
/// already had.
class AnimatedRefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color color;
  final double size;
  final String tooltip;
  final EdgeInsetsGeometry padding;
  final BoxDecoration? decoration;

  const AnimatedRefreshButton({
    super.key,
    required this.onRefresh,
    this.color = Colors.blue,
    this.size = 24,
    this.tooltip = 'Refresh',
    this.padding = EdgeInsets.zero,
    this.decoration,
  });

  @override
  State<AnimatedRefreshButton> createState() => _AnimatedRefreshButtonState();
}

class _AnimatedRefreshButtonState extends State<AnimatedRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    _controller.repeat();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        // Finish the current revolution rather than snapping to a stop
        // mid-spin, then reset cleanly for the next tap.
        final remaining = 1.0 - (_controller.value % 1.0);
        await _controller.animateTo(
          _controller.value + remaining,
          duration: Duration(milliseconds: (remaining * 700).round()),
          curve: Curves.easeOut,
        );
        _controller.value = 0;
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = RotationTransition(
      turns: _controller,
      child: Icon(Icons.refresh, color: widget.color, size: widget.size),
    );

    return Tooltip(
      message: widget.tooltip,
      child: InkResponse(
        onTap: _busy ? null : _handleTap,
        radius: widget.size,
        child: Container(
          padding: widget.padding,
          decoration: widget.decoration,
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );
  }
}
