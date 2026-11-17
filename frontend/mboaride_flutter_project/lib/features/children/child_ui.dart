import 'package:flutter/material.dart';

/// Identité visuelle partagée par les écrans « enfants ».
class ChildUi {
  static const green = Color(0xFF0B6647);
  static const greenLight = Color(0xFF2FA37A);
  static const bg = Color(0xFFF6F5F0);
  static const amber = Color(0xFFF5B400);
  static const ink = Color(0xFF1B2B24);
  static const muted = Color(0xFF6B7A72);
  static const line = Color(0xFFDAD8CF);

  static const softShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const _palettes = [
    [Color(0xFF0B6647), Color(0xFF2FA37A)],
    [Color(0xFF1E6FD9), Color(0xFF5AA6FF)],
    [Color(0xFFE07A1F), Color(0xFFF5B400)],
    [Color(0xFF8A4FD6), Color(0xFFB98BFF)],
    [Color(0xFFD64F7A), Color(0xFFFF8BA9)],
  ];

  static List<Color> paletteFor(String name) {
    final h = name.runes.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return _palettes[h % _palettes.length];
  }

  static void toast(BuildContext context, String message, {bool ok = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? green : ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }
}

/// Pastille avec l'initiale ; sa couleur change en douceur pendant la saisie du prénom.
class ChildAvatar extends StatelessWidget {
  const ChildAvatar({super.key, required this.name, this.size = 52});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final colors = ChildUi.paletteFor(trimmed.isEmpty ? '?' : trimmed);
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Bloc gris qui « respire » : squelette affiché pendant le chargement.
class PulseBox extends StatefulWidget {
  const PulseBox({super.key, required this.height, this.width, this.radius = 12});

  final double height;
  final double? width;
  final double radius;

  @override
  State<PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<PulseBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: const Color(0xFFE4E2DA),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}