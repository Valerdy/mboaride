import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'cancel_trip_screen.dart';
import 'delay_screen.dart';
import 'driver_widgets.dart';

/// Équipage du jour (wireframe 8), sur le modèle de l'écran carte de Cindy : carte en haut,
/// panneau arrondi en bas avec l'ordre de prise en charge, le retard et l'annulation.
class CrewScreen extends StatelessWidget {
  const CrewScreen({
    super.key,
    required this.repository,
    required this.crew,
    this.showMapTiles = true,
  });

  final DriverRepository repository;
  final Crew crew;

  /// Fond de carte OpenStreetMap ; désactivé dans les tests (pas de réseau).
  final bool showMapTiles;

  List<LatLng> get _route => [
        if (crew.fromLat != null) LatLng(crew.fromLat!, crew.fromLng!),
        for (final s in crew.stops)
          if (s.lat != null) LatLng(s.lat!, s.lng!),
        if (crew.toLat != null) LatLng(crew.toLat!, crew.toLng!),
      ];

  Future<void> _open(BuildContext context, Widget screen) async {
    final cancelled = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (cancelled == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Scaffold(
      // Tous les enfants sont positionnés : la pile occupe tout l'écran, et le panneau du bas
      // s'étend de la carte jusqu'en bas (sinon la pile prendrait la seule hauteur de la carte).
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: route.length >= 2
                ? _map(route)
                : Container(color: DriverColors.softGreen),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (Navigator.of(context).canPop())
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Retour',
                          icon: const Icon(Icons.arrow_back,
                              color: MboaColors.green),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 10,
                              color: crew.passengers > 0
                                  ? MboaColors.green
                                  : MboaColors.sun),
                          const SizedBox(width: 8),
                          Text(
                            crew.passengers > 0
                                ? 'Équipage confirmé'
                                : 'En attente de passagers',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 292,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _sheet(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(List<LatLng> route) => FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(
              coordinates: route,
              padding: const EdgeInsets.fromLTRB(40, 80, 40, 50)),
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
        ),
        children: [
          if (showMapTiles)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mboaride',
            ),
          PolylineLayer(polylines: [
            Polyline(points: route, strokeWidth: 5, color: MboaColors.green)
          ]),
          MarkerLayer(
            markers: [
              for (var i = 0; i < route.length; i++)
                Marker(
                  point: route[i],
                  width: 28,
                  height: 28,
                  child: _marker(i, route.length),
                ),
            ],
          ),
        ],
      );

  Widget _marker(int index, int count) {
    final isStart = index == 0;
    final isEnd = index == count - 1;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isStart
            ? MboaColors.green
            : (isEnd ? MboaColors.red : MboaColors.sun),
        border: Border.all(color: Colors.white, width: 3),
      ),
      alignment: Alignment.center,
      child: isStart || isEnd
          ? null
          : Text('$index',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MboaColors.night)),
    );
  }

  Widget _sheet(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFCBD6CF),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${crew.dayLabel} · départ ${frenchTime(crew.departure)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '${crew.from} → ${crew.to} · ${crew.passengers} place${crew.passengers > 1 ? 's' : ''} sur ${crew.seatsTotal}',
            style: const TextStyle(fontSize: 14, color: MboaColors.mutedText),
          ),
          const SizedBox(height: 14),
          if (crew.stops.isEmpty)
            const InfoBanner(
                'L\'ordre de prise en charge s\'affichera ici dès que l\'API fournira le détail de l\'équipage.')
          else ...[
            const Overline('Ordre de prise en charge'),
            const SizedBox(height: 10),
            for (var i = 0; i < crew.stops.length; i++)
              _stopRow(i + 1, crew.stops[i]),
            _arrivalRow(),
            const SizedBox(height: 10),
            Text(
              '${fcfa(crew.totalFcfa)} partagés · paiement Mobile Money après le trajet · '
              'les échanges passent par l\'application.',
              style: const TextStyle(
                  fontSize: 13, color: MboaColors.mutedText, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: crew.passengers == 0
                ? null
                : () => showDriverMessage(context,
                    'Bon trajet ! Vos passagers sont prévenus de votre départ.'),
            child: const Text('Démarrer le trajet'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: MboaColors.green, width: 1.5),
                  ),
                  onPressed: crew.stops.isEmpty
                      ? null
                      : () => _open(context,
                          DelayScreen(repository: repository, crew: crew)),
                  child: const Text('Signaler un retard'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: MboaColors.red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: MboaColors.red, width: 1.5),
                  ),
                  onPressed: () => _open(context,
                      CancelTripScreen(repository: repository, crew: crew)),
                  child: const Text('Annuler le trajet'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _stopRow(int order, CrewStop stop) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: MboaColors.sun,
              child: Text('$order',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MboaColors.night)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${stop.passenger} · ${stop.place}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('Prise à ${frenchTime(stop.pickupTime)}',
                      style: const TextStyle(
                          fontSize: 14, color: MboaColors.mutedText)),
                ],
              ),
            ),
            Text(fcfa(stop.priceFcfa),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _arrivalRow() => Row(
        children: [
          const CircleAvatar(
              radius: 15,
              backgroundColor: MboaColors.red,
              child: Icon(Icons.place, size: 16, color: Colors.white)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(crew.to,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Arrivée vers ${frenchTime(crew.arrival)}',
                  style: const TextStyle(
                      fontSize: 14, color: MboaColors.mutedText)),
            ],
          ),
        ],
      );
}
