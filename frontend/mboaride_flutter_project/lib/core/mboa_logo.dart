import 'package:flutter/material.dart';

/// Logo MboaRide. [full] : voiture, repère et nom ; sinon la seule voiture avec son repère.
/// [chip] pose le logo sur une pastille blanche, pour qu'il reste lisible sur le vert de la marque.
class MboaLogo extends StatelessWidget {
  const MboaLogo({super.key, this.height = 40, this.full = false, this.chip = false});

  final double height;
  final bool full;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      full ? 'assets/images/logo.png' : 'assets/images/logo_icone.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'MboaRide',
      errorBuilder: (_, __, ___) => SizedBox(height: height),
    );
    if (!chip) return image;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: height * 0.34, vertical: height * 0.2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height * 0.5),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: image,
    );
  }
}
