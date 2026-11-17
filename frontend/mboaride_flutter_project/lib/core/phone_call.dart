import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ouvre le composeur du téléphone sur [phone] ; affiche le numéro si l'appel est impossible.
Future<void> callPhone(BuildContext context, String phone) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text('Appelez le $phone')));
  }
}

/// Bouton rond « Appeler ».
class CallButton extends StatelessWidget {
  const CallButton({super.key, required this.phone, this.name});

  final String phone;
  final String? name;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: name == null ? 'Appeler $phone' : 'Appeler $name',
    onPressed: () => callPhone(context, phone),
    icon: const Icon(Icons.call),
  );
}
