import '../domain/ride_request.dart';

class RideRequestException implements Exception {
  RideRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Envoie une demande de trajet. Deux implémentations :
/// FakeRideRequestRepository (démo) et ApiRideRequestRepository (vraie API).
abstract class RideRequestRepository {
  Future<RideRequestResult> create(RideRequest request);
}

/// Simule le serveur : utile tant que l'endpoint n'existe pas.
class FakeRideRequestRepository implements RideRequestRepository {
  @override
  Future<RideRequestResult> create(RideRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return RideRequestResult(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      status: 'searching',
    );
  }
}
