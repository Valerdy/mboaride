import '../domain/ride_request.dart';

class PlaceSearchException implements Exception {
  PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Recherche de lieux par nom (départ, destination).
abstract class PlaceSearchService {
  Future<List<Place>> search(String query);
}
