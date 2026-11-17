import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Position de l'appareil pendant une course, pour faire avancer la carte.
///
/// Deux sources :
///  - [GpsPositionSource] : la vraie position du téléphone. Sur l'émulateur Android, elle
///    suit aussi un trajet rejoué (Extended controls > Location > Routes, ou le script
///    scripts/simuler_gps_emulateur.ps1) : on « se déplace » sans bouger du bureau ;
///  - [SimulatedRide] : un déplacement simulé dans l'application, le long du tracé routier,
///    accéléré. C'est aussi ce qu'utilisent les tests automatiques.
abstract class PositionSource {
  /// Nom affiché à l'écran (« Position GPS », « Simulation ×20 »).
  String get label;

  Stream<LatLng> positions();
}

class PositionUnavailable implements Exception {
  const PositionUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class GpsPositionSource implements PositionSource {
  const GpsPositionSource();

  @override
  String get label => 'Position GPS';

  @override
  Stream<LatLng> positions() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PositionUnavailable('Activez la localisation du téléphone, ou passez en simulation.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const PositionUnavailable("MboaRide n'a pas accès à votre position : passez en simulation.");
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }
}

/// Déplacement simulé le long de [path] (tracé routier), à [speedKmh] multipliés par
/// [acceleration] : une position toutes les [tick]. Le flux se termine sur le dernier point.
class SimulatedRide implements PositionSource {
  SimulatedRide(
    this.path, {
    this.speedKmh = 25,
    this.acceleration = 20,
    this.tick = const Duration(milliseconds: 500),
  }) : assert(path.length >= 2);

  final List<LatLng> path;
  final double speedKmh;
  final double acceleration;
  final Duration tick;

  static const Distance _distance = Distance();

  @override
  String get label => 'Simulation ×${acceleration.round()}';

  /// Longueur du tracé, en mètres.
  double get lengthMeters => _cumulative().last;

  List<double> _cumulative() {
    final out = <double>[0];
    for (var i = 1; i < path.length; i++) {
      out.add(out.last + _distance.as(LengthUnit.Meter, path[i - 1], path[i]));
    }
    return out;
  }

  /// Point du tracé situé à [meters] du départ.
  LatLng pointAt(double meters, [List<double>? cumulative]) {
    final c = cumulative ?? _cumulative();
    if (meters <= 0) return path.first;
    if (meters >= c.last) return path.last;
    var i = 1;
    while (c[i] < meters) {
      i++;
    }
    final segment = c[i] - c[i - 1];
    final t = segment == 0 ? 0.0 : (meters - c[i - 1]) / segment;
    final a = path[i - 1], b = path[i];
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  @override
  Stream<LatLng> positions() {
    final cumulative = _cumulative();
    final stepMeters = speedKmh / 3.6 * acceleration * tick.inMilliseconds / 1000;
    Timer? timer;
    late final StreamController<LatLng> controller;
    controller = StreamController<LatLng>(
      onListen: () {
        var travelled = 0.0;
        controller.add(path.first);
        timer = Timer.periodic(tick, (_) {
          travelled += stepMeters;
          if (travelled >= cumulative.last) {
            controller.add(path.last);
            timer?.cancel();
            controller.close();
          } else {
            controller.add(pointAt(travelled, cumulative));
          }
        });
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}

/// Distance en mètres entre deux points (formule de Vincenty de latlong2).
double metersBetween(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b);

/// Arrivé à destination : à moins de [radiusMeters] du point d'arrivée.
bool hasArrived(LatLng position, LatLng destination, {double radiusMeters = 80}) =>
    metersBetween(position, destination) <= radiusMeters;
