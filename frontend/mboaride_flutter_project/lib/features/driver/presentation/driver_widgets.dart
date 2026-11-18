import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';

/// Couleurs secondaires des wireframes conducteur, dérivées de la charte de Cindy.
class DriverColors {
  static const Color softGreen = Color(0xFFE6F2ED);
  static const Color line = Color(0xFFDCE3DE);
  static const Color softSun = Color(0xFFFDF3D0);
  static const Color sunText = Color(0xFF6B4E00);
  static const Color softRed = Color(0xFFF9E3E0);
  static const Color redText = Color(0xFF9E2A1F);
  static const Color softGrey = Color(0xFFEDEFEE);
}

enum PillTone { success, warning, danger, neutral }

/// Pastille d'état arrondie (« Validée », « En vérification », « À déposer »...).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.success});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      PillTone.success => (DriverColors.softGreen, MboaColors.green),
      PillTone.warning => (DriverColors.softSun, DriverColors.sunText),
      PillTone.danger => (DriverColors.softRed, DriverColors.redText),
      PillTone.neutral => (DriverColors.softGrey, MboaColors.mutedText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Carte blanche à bord fin, comme sur les écrans de Cindy.
class DriverCard extends StatelessWidget {
  const DriverCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Surface Material (et non un simple fond) : les interrupteurs et listes posés dessus
  /// gardent leur effet visuel au toucher.
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: DriverColors.line),
    ),
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Encadré d'information vert (ou jaune pour un calcul de prix).
class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.icon = Icons.info_outline, this.warm = false, this.title});

  final String text;
  final String? title;
  final IconData icon;
  final bool warm;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: warm ? DriverColors.softSun : DriverColors.softGreen,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!warm) ...[
          Icon(icon, size: 20, color: MboaColors.green),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: MboaColors.night)),
            ],
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
  );
}

/// Petit libellé en capitales (« PROCHAIN TRAJET »).
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 13,
      color: MboaColors.mutedText,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
    ),
  );
}

/// Chargement, erreur avec « Réessayer », puis contenu : le schéma des écrans du dépôt.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return ErrorView(message: snapshot.error.toString(), onRetry: onRetry);
      }
      return builder(context, snapshot.data as T);
    },
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: MboaColors.mutedText),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

void showDriverMessage(BuildContext context, String message, {bool isError = false}) {
  // Le nouveau message remplace le précédent au lieu d'attendre derrière lui.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? MboaColors.red : MboaColors.green,
    ),
  );
}

/// « 1008 » -> « 1 008 ».
String fcfa(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$buffer FCFA';
}

/// « 2.0 » -> « 2 » ; « 0.8 » -> « 0,8 ».
String km(double value) {
  final text = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} km';
}
