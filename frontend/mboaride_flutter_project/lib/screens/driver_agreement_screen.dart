import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';

class DriverAgreementScreen extends StatefulWidget {
  final String token;
  const DriverAgreementScreen({super.key, required this.token});

  @override
  State<DriverAgreementScreen> createState() => _DriverAgreementScreenState();
}

class _DriverAgreementScreenState extends State<DriverAgreementScreen> {
  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color bgBeige = Color(0xFFF6F5F0);
  static const Color warningAmber = Color(0xFFF5B400);

  final Map<String, bool> _docs = {
    'idCard': false,
    'license': false,
    'criminalRecord': false,
    'insurance': false,
  };

  // pending | under_review | active | rejected
  String _status = 'pending';
  bool _isLoading = true;
  bool _isSubmitting = false;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (widget.token.isNotEmpty) 'Authorization': 'Bearer ${widget.token}',
  };

  String get _base => '${AppConfig.apiBaseUrl}/routes/driver/agreement';

  int get _receivedCount => _docs.values.where((v) => v).length;
  bool get _locked => _status == 'under_review' || _status == 'active';
  bool get _canSubmit => _receivedCount == 4 && !_locked && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------- API

  void _apply(Map<String, dynamic> data) {
    final docs = (data['documents'] as Map?) ?? {};
    for (final k in _docs.keys) {
      _docs[k] = docs[k] == 'received';
    }
    _status = data['status']?.toString() ?? 'pending';
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? primaryGreen : null),
    );
  }

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.parse(_base), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        if (mounted) setState(() => _apply(_decode(res)));
      } else if (res.statusCode == 401) {
        _toast('Session expirée, reconnectez-vous.');
      } else {
        _toast('Erreur serveur (${res.statusCode}).');
      }
    } on TimeoutException {
      _toast('Le serveur ne répond pas. Réessayez.');
    } catch (_) {
      _toast('Impossible de charger le dossier.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDoc(String key) async {
    if (_locked) return;
    final next = !(_docs[key] ?? false);
    setState(() => _docs[key] = next); // mise à jour optimiste
    try {
      final res = await http
          .put(
        Uri.parse('$_base/documents/$key'),
        headers: _headers,
        body: jsonEncode({'status': next ? 'received' : 'missing'}),
      )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception(_decode(res)['detail'] ?? 'Erreur ${res.statusCode}');
      }
    } catch (_) {
      if (mounted) setState(() => _docs[key] = !next); // annule
      _toast("Impossible d'enregistrer le document.");
    }
  }

  Future<void> _submitAgreement() async {
    setState(() => _isSubmitting = true);
    try {
      final res = await http
          .post(Uri.parse('$_base/submit'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _decode(res);
      if (res.statusCode == 200) {
        if (mounted) setState(() => _apply(data));
        _toast('Dossier envoyé pour vérification !', ok: true);
      } else {
        _toast(data['detail']?.toString() ?? 'Erreur (${res.statusCode})');
      }
    } on TimeoutException {
      _toast('Le serveur ne répond pas. Réessayez.');
    } catch (_) {
      _toast('Impossible de joindre le serveur.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------- UI

  String get _buttonLabel {
    switch (_status) {
      case 'under_review':
        return 'Dossier en cours de vérification';
      case 'active':
        return 'Agrément actif';
      default:
        return 'Envoyer pour vérification';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: bgBeige,
        body: Center(child: CircularProgressIndicator(color: primaryGreen)),
      );
    }

    return Scaffold(
      backgroundColor: bgBeige,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Devenir conducteur',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Carte récapitulative
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agrément : $_receivedCount documents sur 4',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tous les conducteurs sont vérifiés avant leur premier trajet.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Liste des 4 documents
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _buildDocRow("Pièce d'identité", 'idCard'),
                  const Divider(),
                  _buildDocRow('Permis de conduire', 'license'),
                  const Divider(),
                  _buildDocRow('Extrait de casier judiciaire', 'criminalRecord'),
                  const Divider(),
                  _buildDocRow("Attestation d'assurance", 'insurance'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bandeau d'avertissement ambre
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: warningAmber,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                "Aucun trajet publiable avant l'activation de l'agrément. Un signalement grave le suspend.",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const Spacer(),

            // Bouton principal
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryGreen.withOpacity(0.35),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _canSubmit ? _submitAgreement : null,
                child: _isSubmitting
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
                    : Text(
                  _buttonLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow(String label, String key) {
    final received = _docs[key] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          InkWell(
            onTap: () => _toggleDoc(key),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: received ? primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryGreen, width: 1.4),
              ),
              child: Text(
                received ? 'Reçu' : 'Déposer',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: received ? Colors.white : primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}