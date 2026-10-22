import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/desktop_shell.dart';
import 'theme.dart';

/// The desktop window's own title bar: drag to move, double-click to
/// maximize, and minimize/close buttons in the app's style.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  static const height = 38.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          _WindowButton(
            icon: Icons.remove_rounded,
            tooltip: 'Свернуть',
            onTap: DesktopShell.instance.minimize,
          ),
          _WindowButton(
            icon: Icons.crop_square_rounded,
            tooltip: 'Развернуть',
            onTap: DesktopShell.instance.toggleMaximize,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрыть',
            hover: Color(0xFFE5484D),
            onTap: DesktopShell.instance.close,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.hover,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? hover;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: TitleBar.height,
          color: _hover ? (widget.hover ?? GX.glassStrong) : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 17,
            color: _hover ? GX.text : GX.muted,
          ),
        ),
      ),
    );
  }
}
