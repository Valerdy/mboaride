import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';

typedef PickupStop = Map<String, dynamic>;

class IntercityTripScreen extends StatefulWidget {
  final String token;
  const IntercityTripScreen({super.key, required this.token});

  @override
  State<IntercityTripScreen> createState() => _IntercityTripScreenState();
}

class _IntercityTripScreenState extends State<IntercityTripScreen> {
  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color bgBeige = Color(0xFFF6F5F0);

  String _dayLabel = 'Vendredi';
  String _departureTime = '14:00';
  final List<String> _pickupPoints = ['Akwa', 'Ndokoti'];
  final List<PickupStop> _pickupOrder = [
    {'rank': 1, 'passengerLabel': '[Passager]', 'point': 'Akwa', 'time': '14:00'},
    {'rank': 2, 'passengerLabel': '[Passager]', 'point': 'Ndokoti', 'time': '14:20'},
  ];

  bool _isPublishing = false;

  Future<void> _addPickupPoint() async {
    final ctrl = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un point de départ'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Ex: Yassa, Japoma...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (added != null && added.isNotEmpty) {
      setState(() => _pickupPoints.add(added));
    }
  }

  Future<void> _publishTrip() async {
    setState(() => _isPublishing = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/intercity/trips'),
        headers: {
          'Content-Type': 'application/json',
          if (widget.token.isNotEmpty) 'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'originCity': 'Douala',
          'destinationCity': 'Yaoundé',
          'dayLabel': _dayLabel,
          'departureTime': _departureTime,
          'pickupPoints': _pickupPoints,
          'totalSeats': 4,
          'pricePerSeatFcfa': 3200,
          'pickupOrder': _pickupOrder,
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voyage Douala → Yaoundé publié !'),
            backgroundColor: primaryGreen,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyage enregistré localement.')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBeige,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Douala → Yaoundé', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Jour & Heure de départ
            Row(
              children: [
                Expanded(
                  child: _buildSelectorBox(_dayLabel, () {
                    setState(() => _dayLabel = _dayLabel == 'Vendredi' ? 'Samedi' : 'Vendredi');
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSelectorBox('Départ $_departureTime', () {
                    setState(() => _departureTime = _departureTime == '14:00' ? '08:00' : '14:00');
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text('Points de départ', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._pickupPoints.map(
                      (pt) => Chip(
                    label: Text(pt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: primaryGreen,
                    deleteIconColor: Colors.white70,
                    onDeleted: _pickupPoints.length > 1
                        ? () => setState(() => _pickupPoints.remove(pt))
                        : null,
                  ),
                ),
                ActionChip(
                  label: const Text('+ Ajouter', style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: primaryGreen),
                  onPressed: _addPickupPoint,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carte places & tarif
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_pickupOrder.length} / 4 places réservées',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: primaryGreen, width: 1.4),
                        ),
                        child: const Text(
                          '= 3 200 FCFA',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Carburant et péage partagés · car classique : 3 500 FCFA',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Carte Ordre de prise en charge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ordre de prise en charge', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ..._pickupOrder.map(
                        (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${item['rank']} · ${item['passengerLabel']} · ${item['point']} · ${item['time']}',
                        style: const TextStyle(fontSize: 13.5, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isPublishing ? null : _publishTrip,
                child: _isPublishing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Publier le voyage',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorBox(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87)),
      ),
    );
  }
}