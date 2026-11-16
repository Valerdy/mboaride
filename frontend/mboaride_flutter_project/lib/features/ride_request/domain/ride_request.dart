import 'dart:math' as math;

import '../../../core/app_config.dart';

/// Un lieu choisi par l'utilisateur : nom affiché et coordonnées.
class Place {
  const Place({required this.name, required this.lat, required this.lng});

  final String name;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};
}

/// Exigences de confort (voir US02). Le code est celui envoyé à l'API.
enum Comfort {
  airConditioning('air_conditioning', 'Climatisation'),
  nonSmoking('non_smoking', 'Non-fumeur'),
  quiet('quiet', 'Silence');

  const Comfort(this.code, this.label);

  final String code;
  final String label;
}

enum RideDay { today, tomorrow }

/// Règles de validation de la demande.
class RideRequestRules {
  static const int minPriceFcfa = 100;
  static const int maxPriceFcfa = 20000;
  static const int minWindowMinutes = 10;
  static const int maxWindowMinutes = 180;
  static const double minDistanceMeters = 100;
}

/// Distance à vol d'oiseau entre deux lieux, en mètres.
double distanceMeters(Place a, Place b) {
  const earthRadius = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(h));
}

/// Date du jour [base] à l'heure donnée en minutes depuis minuit.
DateTime dateAtMinutes(DateTime base, int minutes) =>
    DateTime(base.year, base.month, base.day, minutes ~/ 60, minutes % 60);

/// 450 -> "07:30"
String formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

class ValidationResult {
  const ValidationResult(this.errors);

  /// Clés possibles : pickup, dropoff, window, price.
  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
}

bool _inServiceArea(Place p) =>
    p.lat >= AppConfig.minLat &&
    p.lat <= AppConfig.maxLat &&
    p.lng >= AppConfig.minLng &&
    p.lng <= AppConfig.maxLng;

ValidationResult validateRideRequest({
  required Place? pickup,
  required Place? dropoff,
  required DateTime? windowStart,
  required DateTime? windowEnd,
  required int? maxPriceFcfa,
  required DateTime now,
}) {
  final errors = <String, String>{};

  if (pickup == null) {
    errors['pickup'] = 'Choisissez un point de départ';
  } else if (!_inServiceArea(pickup)) {
    errors['pickup'] = 'Ce point est hors de la zone de service (Douala)';
  }

  if (dropoff == null) {
    errors['dropoff'] = 'Choisissez une destination';
  } else if (!_inServiceArea(dropoff)) {
    errors['dropoff'] = 'Ce point est hors de la zone de service (Douala)';
  }

  if (pickup != null &&
      dropoff != null &&
      !errors.containsKey('pickup') &&
      !errors.containsKey('dropoff') &&
      distanceMeters(pickup, dropoff) < RideRequestRules.minDistanceMeters) {
    errors['dropoff'] = "Le départ et l'arrivée sont trop proches";
  }

  if (windowStart == null || windowEnd == null) {
    errors['window'] = "Choisissez la fenêtre d'arrivée";
  } else {
    final minutes = windowEnd.difference(windowStart).inMinutes;
    if (minutes <= 0) {
      errors['window'] = 'La fin de la fenêtre doit être après le début';
    } else if (minutes < RideRequestRules.minWindowMinutes) {
      errors['window'] =
          'La fenêtre doit durer au moins ${RideRequestRules.minWindowMinutes} minutes';
    } else if (minutes > RideRequestRules.maxWindowMinutes) {
      errors['window'] = 'La fenêtre ne peut pas dépasser 3 heures';
    } else if (!windowEnd.isAfter(now)) {
      errors['window'] = "Cette fenêtre d'arrivée est déjà passée";
    }
  }

  if (maxPriceFcfa == null) {
    errors['price'] = 'Indiquez votre prix maximal';
  } else if (maxPriceFcfa < RideRequestRules.minPriceFcfa ||
      maxPriceFcfa > RideRequestRules.maxPriceFcfa) {
    errors['price'] =
        'Le prix doit être entre ${RideRequestRules.minPriceFcfa} et ${RideRequestRules.maxPriceFcfa} FCFA';
  }

  return ValidationResult(errors);
}

/// Demande de trajet envoyée à l'API (POST /ride-requests).
class RideRequest {
  const RideRequest({
    required this.pickup,
    required this.dropoff,
    required this.windowStart,
    required this.windowEnd,
    required this.maxPriceFcfa,
    required this.comforts,
  });

  final Place pickup;
  final Place dropoff;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int maxPriceFcfa;
  final Set<Comfort> comforts;

  Map<String, dynamic> toJson() {
    final sorted = comforts.toList()..sort((a, b) => a.index - b.index);
    return {
      'pickup': pickup.toJson(),
      'dropoff': dropoff.toJson(),
      'arrival_window': {
        'from': windowStart.toUtc().toIso8601String(),
        'to': windowEnd.toUtc().toIso8601String(),
      },
      'max_price_fcfa': maxPriceFcfa,
      'comforts': sorted.map((c) => c.code).toList(),
    };
  }
}

/// Réponse de l'API après création de la demande.
class RideRequestResult {
  const RideRequestResult({required this.id, required this.status});

  final String id;
  final String status;

  factory RideRequestResult.fromJson(Map<String, dynamic> json) =>
      RideRequestResult(
        id: '${json['id']}',
        status: '${json['status'] ?? 'searching'}',
      );
}
