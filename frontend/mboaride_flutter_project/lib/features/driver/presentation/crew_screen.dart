import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../../../core/phone_call.dart';
import '../../../core/road_routing.dart';
import '../../payment/data/payment_repository.dart';
import '../../ride/live_ride_map.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'cancel_trip_screen.dart';
import 'delay_screen.dart';
import 'driver_ride_screen.dart';
import 'driver_widgets.dart';

/// Équipage du jour (wireframe 8), sur le modèle de l'écran carte de Cindy : carte en haut,
/// panneau arrondi en bas avec l'ordre de prise en charge, le retard et l'annulation.
class CrewScreen extends StatelessWidget {
  const CrewScreen({
    super.key,
    required this.repository,
    required this.crew,
    this.showMapTiles = true,
    this.walletRepository,
    this.routeLoader = roadRouteLoader,
    this.trackingMode = TrackingMode.gps,
  });

  final DriverRepository repository;
  final Crew crew;

  /// Portefeuille, pour voir le versement à la fin de la course.
  final PaymentRepository? walletRepository;
  final RouteLoader routeLoader;
  final TrackingMode trackingMode;

  /// Fond de carte OpenStreetMap et tracé routier ; désactivés dans les tests (pas de réseau).
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
          if (showMapTiles) _RoadLine(stops: route),
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
          const SizedBox(height: 12),
          _MeetingPointCard(repository: repository, crew: crew),
          const SizedBox(height: 14),
          if (crew.stops.isEmpty)
            const InfoBanner(
                'Aucun passager payé pour l\'instant : ils apparaîtront ici, avec leur nom et leur téléphone, '
                'dès qu\'ils auront payé leur place.')
          else ...[
            const Overline('Ordre de prise en charge'),
            const SizedBox(height: 10),
            for (var i = 0; i < crew.stops.length; i++)
              _stopRow(i + 1, crew.stops[i]),
            _arrivalRow(),
            const SizedBox(height: 10),
            Text(
              '${fcfa(crew.totalFcfa)} payés par vos passagers. MboaRide vous les verse dans votre portefeuille, '
              'moins 10 % de commission, quand chacun a validé la fin de la course.',
              style: const TextStyle(
                  fontSize: 13, color: MboaColors.mutedText, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: crew.passengers == 0
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => DriverRideScreen(
                        repository: repository,
                        crew: crew,
                        walletRepository: walletRepository,
                        showMapTiles: showMapTiles,
                        routeLoader: routeLoader,
                        initialMode: trackingMode,
                      ),
                    )),
            icon: const Icon(Icons.navigation),
            label: Text(crew.courseStatus == CourseStatus.notStarted ? 'Démarrer la course' : 'Reprendre la course'),
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text('${stop.fullName}${stop.seats > 1 ? ' (${stop.seats} places)' : ''} · ${stop.place}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                      'Prise à ${frenchTime(stop.pickupTime)}'
                      '${stop.destination == null ? '' : ' · descend à ${stop.destination}'}',
                      style: const TextStyle(
                          fontSize: 14, color: MboaColors.mutedText)),
                  if (stop.phone != null)
                    Text(stop.phone!,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  Text(
                    [
                      stop.rating == null
                          ? 'Nouveau passager'
                          : '★ ${stop.rating!.toStringAsFixed(1).replaceAll('.', ',')} (${stop.ratingCount} avis)',
                      if (stop.student) 'élève (autorisation parentale)',
                      fcfa(stop.priceFcfa),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: MboaColors.mutedText),
                  ),
                ],
              ),
            ),
            if (stop.phone != null) CallButton(phone: stop.phone!, name: stop.passenger),
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

/// Point de ramassage du trajet : affiché, et modifiable (les passagers sont prévenus).
class _MeetingPointCard extends StatefulWidget {
  const _MeetingPointCard({required this.repository, required this.crew});

  final DriverRepository repository;
  final Crew crew;

  @override
  State<_MeetingPointCard> createState() => _MeetingPointCardState();
}

class _MeetingPointCardState extends State<_MeetingPointCard> {
  late String? _point = widget.crew.meetingPoint;
  late String? _instructions = widget.crew.meetingInstructions;
  late final int _wait = widget.crew.waitMinutes;

  Future<void> _edit() async {
    final point = TextEditingController(text: _point ?? '');
    final instructions = TextEditingController(text: _instructions ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Point de ramassage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: point,
              decoration: const InputDecoration(
                labelText: 'Lieu exact',
                hintText: 'Station Total de Logpom, côté boulangerie',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: instructions,
              decoration: const InputDecoration(
                labelText: 'Consignes (facultatif)',
                hintText: 'Berline grise, je klaxonne deux fois',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.repository.setMeetingPoint(
        widget.crew.tripId,
        point: point.text,
        instructions: instructions.text,
        waitMinutes: _wait,
      );
      if (!mounted) return;
      setState(() {
        _point = point.text.trim();
        _instructions = instructions.text.trim().isEmpty ? null : instructions.text.trim();
      });
      showDriverMessage(context, 'Point de ramassage enregistré : vos passagers sont prévenus.');
    } on ApiException catch (e) {
      if (mounted) showDriverMessage(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => InfoBanner(
    _point == null
        ? 'Pas encore précisé : indiquez où vos passagers vous retrouvent (lieu exact, repère).'
        : '$_point${_instructions == null ? '' : ' · $_instructions'} · attente $_wait min au plus',
    title: 'Point de ramassage',
    icon: Icons.place_outlined,
  ).withAction(TextButton(onPressed: _edit, child: Text(_point == null ? 'Préciser' : 'Modifier')));
}

extension on Widget {
  Widget withAction(Widget action) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [this, Align(alignment: Alignment.centerRight, child: action)],
  );
}

/// Tracé de l'équipage sur les routes (départ, chaque prise en charge, arrivée), calculé
/// par OSRM sur OpenStreetMap. Rien n'est dessiné tant qu'il n'est pas arrivé, ni s'il est
/// indisponible : jamais de ligne droite à vol d'oiseau.
class _RoadLine extends StatefulWidget {
  const _RoadLine({required this.stops});

  final List<LatLng> stops;

  @override
  State<_RoadLine> createState() => _RoadLineState();
}

class _RoadLineState extends State<_RoadLine> {
  late final Future<RoadRoute?> _route = RoadRouting().route(widget.stops);

  @override
  Widget build(BuildContext context) => FutureBuilder<RoadRoute?>(
        future: _route,
        builder: (context, snapshot) {
          final route = snapshot.data;
          if (route == null) return const SizedBox.shrink();
          return PolylineLayer(polylines: [
            Polyline(points: route.points, strokeWidth: 5, color: MboaColors.green),
          ]);
        },
      );
}
