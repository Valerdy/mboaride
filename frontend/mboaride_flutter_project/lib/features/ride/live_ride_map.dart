import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/mboa_theme.dart';
import '../../core/position_source.dart';
import '../../core/road_routing.dart';

/// Calcule le tracé routier passant par des points (OSRM) ; remplaçable dans les tests.
typedef RouteLoader = Future<List<LatLng>?> Function(List<LatLng> stops);

Future<List<LatLng>?> roadRouteLoader(List<LatLng> stops) async => (await RoadRouting().route(stops))?.points;

/// Mode de suivi : la vraie position du téléphone, ou un déplacement simulé.
enum TrackingMode { gps, simulation }

/// Repère sur la carte (départ, prise en charge, arrivée).
class RideMarker {
  const RideMarker(this.point, {this.color = MboaColors.green, this.icon = Icons.circle, this.label});

  final LatLng point;
  final Color color;
  final IconData icon;
  final String? label;
}

/// Carte d'une course qui suit la position : tracé sur les routes, position qui avance, et
/// arrivée détectée à moins de [arrivalRadiusMeters] de [destination].
///
/// En simulation, la position parcourt le tracé routier (accéléré ×[acceleration]) : de quoi
/// vérifier sans se déplacer que la carte suit le trajet et que l'arrivée déclenche la fin de
/// course. Sur l'émulateur, le mode GPS suit aussi un trajet rejoué
/// (scripts/simuler_gps_emulateur.ps1).
class LiveRideMap extends StatefulWidget {
  const LiveRideMap({
    super.key,
    required this.stops,
    required this.destination,
    required this.onArrived,
    this.markers = const [],
    this.showMapTiles = true,
    this.routeLoader = roadRouteLoader,
    this.initialMode = TrackingMode.gps,
    this.autoStartSimulation = false,
    this.acceleration = 20,
    this.arrivalRadiusMeters = 80,
    this.height = 300,
    this.onPosition,
  });

  /// Points de passage, dans l'ordre (départ, prises en charge, arrivée).
  final List<LatLng> stops;
  final LatLng destination;
  final VoidCallback onArrived;
  final List<RideMarker> markers;
  final bool showMapTiles;
  final RouteLoader routeLoader;
  final TrackingMode initialMode;
  final bool autoStartSimulation;
  final double acceleration;
  final double arrivalRadiusMeters;
  final double height;

  /// Chaque nouvelle position, avec la distance restante jusqu'à [destination] (mètres).
  final void Function(LatLng position, double remainingMeters)? onPosition;

  @override
  State<LiveRideMap> createState() => LiveRideMapState();
}

class LiveRideMapState extends State<LiveRideMap> {
  final MapController _map = MapController();
  bool _mapReady = false;
  List<LatLng>? _route;
  bool _routeIsRoad = false;
  late TrackingMode _mode = widget.initialMode;
  StreamSubscription<LatLng>? _subscription;
  LatLng? _position;
  final List<LatLng> _travelled = [];
  double? _remaining;
  bool _arrived = false;
  bool _follow = true;
  String? _error;

  TrackingMode get mode => _mode;
  LatLng? get position => _position;
  bool get running => _subscription != null;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    final road = await widget.routeLoader(widget.stops);
    if (!mounted) return;
    setState(() {
      _routeIsRoad = road != null && road.length >= 2;
      // Sans tracé routier, la simulation suit les points de passage ; aucune ligne n'est
      // dessinée (jamais de ligne droite qui ferait croire à un itinéraire).
      _route = _routeIsRoad ? road : widget.stops;
    });
    if (widget.autoStartSimulation || widget.initialMode == TrackingMode.gps) start();
  }

  /// Lance le suivi dans le mode choisi (GPS ou simulation).
  void start() {
    final route = _route;
    if (route == null) return;
    _subscription?.cancel();
    _travelled.clear();
    _arrived = false;
    _error = null;
    final PositionSource source = _mode == TrackingMode.simulation
        ? SimulatedRide(route, acceleration: widget.acceleration)
        : const GpsPositionSource();
    _subscription = source.positions().listen(
      _onPosition,
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _subscription = null;
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _subscription = null);
      },
    );
    setState(() {});
  }

  void stop() {
    _subscription?.cancel();
    setState(() => _subscription = null);
  }

  void setMode(TrackingMode mode) {
    if (mode == _mode) return;
    _subscription?.cancel();
    setState(() {
      _mode = mode;
      _subscription = null;
      _error = null;
    });
    if (mode == TrackingMode.gps) start();
  }

  void _onPosition(LatLng p) {
    if (!mounted) return;
    final remaining = metersBetween(p, widget.destination);
    setState(() {
      _position = p;
      _travelled.add(p);
      _remaining = remaining;
    });
    if (_follow && _mapReady) {
      try {
        _map.move(p, _map.camera.zoom < 14 ? 15 : _map.camera.zoom);
      } on Object {
        // carte pas encore dimensionnée
      }
    }
    widget.onPosition?.call(p, remaining);
    if (!_arrived && hasArrived(p, widget.destination, radiusMeters: widget.arrivalRadiusMeters)) {
      _arrived = true;
      _subscription?.cancel();
      _subscription = null;
      widget.onArrived();
    }
  }

  static String _distance(double meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '${meters.round()} m';

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final position = _position;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: widget.stops,
                    padding: const EdgeInsets.all(40),
                  ),
                  onMapReady: () => _mapReady = true,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _follow) setState(() => _follow = false);
                  },
                ),
                children: [
                  if (widget.showMapTiles)
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mboaride',
                    ),
                  if (route != null && _routeIsRoad)
                    PolylineLayer(
                      polylines: [
                        Polyline(points: route, strokeWidth: 5, color: MboaColors.green),
                        if (_travelled.length >= 2)
                          Polyline(points: List.of(_travelled), strokeWidth: 5, color: const Color(0xFF9AA8A1)),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final m in widget.markers)
                        Marker(
                          point: m.point,
                          width: 30,
                          height: 30,
                          child: Icon(m.icon, color: m.color, size: 26),
                        ),
                      if (position != null)
                        Marker(
                          point: position,
                          width: 30,
                          height: 30,
                          child: Container(
                            key: const ValueKey('position-courante'),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E6FD9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: SegmentedButton<TrackingMode>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: TrackingMode.gps, label: Text('GPS'), icon: Icon(Icons.gps_fixed, size: 16)),
                        ButtonSegment(
                          value: TrackingMode.simulation,
                          label: Text('Simulation'),
                          icon: Icon(Icons.play_circle_outline, size: 16),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setMode(s.first),
                    ),
                  ),
                ),
              ),
              if (!_follow && position != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Recentrer sur ma position',
                    onPressed: () {
                      setState(() => _follow = true);
                      _map.move(position, 15);
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              Icon(
                _mode == TrackingMode.gps ? Icons.gps_fixed : Icons.route,
                size: 18,
                color: MboaColors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error ??
                      (route == null
                          ? "Calcul de l'itinéraire par la route…"
                          : _remaining == null
                          ? (_mode == TrackingMode.simulation
                                ? 'Simulation prête : lancez-la pour voir la course avancer.'
                                : 'En attente de votre position…')
                          : _arrived
                          ? 'Arrivé à destination'
                          : 'Encore ${_distance(_remaining!)} jusqu\'à l\'arrivée'),
                  key: const ValueKey('progression-course'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _error != null ? MboaColors.red : MboaColors.night,
                  ),
                ),
              ),
              if (_mode == TrackingMode.simulation && route != null && !_arrived)
                TextButton.icon(
                  onPressed: running ? stop : start,
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  label: Text(running ? 'Pause' : 'Lancer la simulation'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
