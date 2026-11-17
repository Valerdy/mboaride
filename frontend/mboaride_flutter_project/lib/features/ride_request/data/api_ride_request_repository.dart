import '../../../core/api_client.dart';
import '../domain/ride_request.dart';
import 'ride_request_repository.dart';

/// Enregistre la demande sur l'API Python (`POST /api/demandes`). Les offres se lisent
/// ensuite sur `/api/moi/demandes/{id}/offres`, calculées par le moteur d'agents.
class ApiRideRequestRepository implements RideRequestRepository {
  ApiRideRequestRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Corps attendu par l'API Python : heures locales « HH:MM » et date du trajet.
  static Map<String, dynamic> body(RideRequest request) {
    final start = request.windowStart.toLocal();
    final end = request.windowEnd.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    Map<String, dynamic> place(Place p) => {'libelle': p.name, 'lat': p.lat, 'lon': p.lng};
    return {
      'depart': place(request.pickup),
      'arrivee': place(request.dropoff),
      'arrivee_au_plus_tot': '${two(start.hour)}:${two(start.minute)}',
      'arrivee_au_plus_tard': '${two(end.hour)}:${two(end.minute)}',
      'date_trajet': '${start.year}-${two(start.month)}-${two(start.day)}',
      'prix_max_fcfa': request.maxPriceFcfa,
      'clim_obligatoire': request.comforts.contains(Comfort.airConditioning),
      if (request.circleCode != null) 'cercle_max': request.circleCode,
    };
  }

  @override
  Future<RideRequestResult> create(RideRequest request) async {
    try {
      final json = await _client.post('/api/demandes', body(request));
      return RideRequestResult.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw RideRequestException(error.message);
    }
  }
}
