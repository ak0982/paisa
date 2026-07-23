import 'package:flutter/material.dart';

class PaisaProgressBar extends StatefulWidget {
  const PaisaProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 8,
    this.trackColor = const Color(0xFF232427),
    this.animate = true,
  });

  final double progress;
  final Color color;
  final double height;
  final Color trackColor;
  final bool animate;

  @override
  State<PaisaProgressBar> createState() => _PaisaProgressBarState();
}

class _PaisaProgressBarState extends State<PaisaProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: widget.progress.clamp(0.0, 1.0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(PaisaProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.progress.clamp(0.0, 1.0),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: widget.height,
        color: widget.trackColor,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Align(
              alignment: Alignment.centerLeft,
              widthFactor: _animation.value,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
