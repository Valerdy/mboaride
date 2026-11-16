import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/ride_request_repository.dart';
import '../domain/ride_request.dart';

enum SubmitStatus { idle, submitting, success, error }

/// État et logique de l'écran « Où allez-vous ? » (US04).
class RideRequestController extends ChangeNotifier {
  RideRequestController({
    required RideRequestRepository repository,
    DateTime Function()? clock,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now {
    final now = _clock();
    // Si l'heure habituelle est déjà passée aujourd'hui, on propose demain.
    _day = now.hour * 60 + now.minute >= _fromMinutes
        ? RideDay.tomorrow
        : RideDay.today;
  }

  final RideRequestRepository _repository;
  final DateTime Function() _clock;

  Place? _pickup;
  Place? _dropoff;
  RideDay _day = RideDay.tomorrow;
  int _fromMinutes = 7 * 60 + 30;
  int _toMinutes = 8 * 60;
  String _priceText = '';
  final Set<Comfort> _comforts = <Comfort>{};
  final Map<String, String> _errors = <String, String>{};
  SubmitStatus _status = SubmitStatus.idle;
  String? _errorMessage;
  RideRequestResult? _result;

  Place? get pickup => _pickup;
  Place? get dropoff => _dropoff;
  RideDay get day => _day;
  int get fromMinutes => _fromMinutes;
  int get toMinutes => _toMinutes;
  Set<Comfort> get comforts => Set.unmodifiable(_comforts);
  Map<String, String> get errors => Map.unmodifiable(_errors);
  SubmitStatus get status => _status;
  bool get isSubmitting => _status == SubmitStatus.submitting;
  String? get errorMessage => _errorMessage;
  RideRequestResult? get result => _result;
  int? get maxPriceFcfa => int.tryParse(_priceText.trim());

  DateTime _baseDay(DateTime now) =>
      _day == RideDay.today ? now : now.add(const Duration(days: 1));

  void setPickup(Place? place) {
    _pickup = place;
    _errors.remove('pickup');
    _errors.remove('dropoff');
    notifyListeners();
  }

  void setDropoff(Place? place) {
    _dropoff = place;
    _errors.remove('dropoff');
    notifyListeners();
  }

  void swapPlaces() {
    final tmp = _pickup;
    _pickup = _dropoff;
    _dropoff = tmp;
    _errors.remove('pickup');
    _errors.remove('dropoff');
    notifyListeners();
  }

  void setDay(RideDay day) {
    _day = day;
    _errors.remove('window');
    notifyListeners();
  }

  void setFromMinutes(int minutes) {
    _fromMinutes = minutes;
    // Si la fin n'est plus après le début, on la décale de 30 minutes.
    if (_toMinutes <= minutes) {
      _toMinutes = math.min(minutes + 30, 23 * 60 + 59);
    }
    _errors.remove('window');
    notifyListeners();
  }

  void setToMinutes(int minutes) {
    _toMinutes = minutes;
    _errors.remove('window');
    notifyListeners();
  }

  void setPriceText(String text) {
    _priceText = text;
    _errors.remove('price');
    notifyListeners();
  }

  void toggleComfort(Comfort comfort) {
    if (!_comforts.remove(comfort)) _comforts.add(comfort);
    notifyListeners();
  }

  /// Valide puis envoie la demande. Retourne true si elle a été acceptée.
  Future<bool> submit() async {
    if (isSubmitting) return false;
    final now = _clock();
    final base = _baseDay(now);
    final windowStart = dateAtMinutes(base, _fromMinutes);
    final windowEnd = dateAtMinutes(base, _toMinutes);

    final validation = validateRideRequest(
      pickup: _pickup,
      dropoff: _dropoff,
      windowStart: windowStart,
      windowEnd: windowEnd,
      maxPriceFcfa: maxPriceFcfa,
      now: now,
    );
    _errors
      ..clear()
      ..addAll(validation.errors);
    _errorMessage = null;
    if (!validation.isValid) {
      _status = SubmitStatus.idle;
      notifyListeners();
      return false;
    }

    _status = SubmitStatus.submitting;
    notifyListeners();
    try {
      _result = await _repository.create(
        RideRequest(
          pickup: _pickup!,
          dropoff: _dropoff!,
          windowStart: windowStart,
          windowEnd: windowEnd,
          maxPriceFcfa: maxPriceFcfa!,
          comforts: Set<Comfort>.of(_comforts),
        ),
      );
      _status = SubmitStatus.success;
      notifyListeners();
      return true;
    } on RideRequestException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Une erreur inattendue est survenue. Réessayez.';
    }
    _status = SubmitStatus.error;
    notifyListeners();
    return false;
  }
}
