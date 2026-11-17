import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_config.dart';

class ChildrenApiException implements Exception {
  ChildrenApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Trajet scolaire récurrent d'un enfant.
class ChildRoute {
  const ChildRoute({
    required this.pickupName,
    required this.dropoffName,
    required this.days,
    required this.departTime,
  });

  final String pickupName;
  final String dropoffName;
  final List<String> days; // mon, tue, wed, thu, fri, sat, sun
  final String departTime; // HH:mm

  static const dayCodes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const dayShort = {
    'mon': 'Lun',
    'tue': 'Mar',
    'wed': 'Mer',
    'thu': 'Jeu',
    'fri': 'Ven',
    'sat': 'Sam',
    'sun': 'Dim',
  };

  factory ChildRoute.fromJson(Map<String, dynamic> j) => ChildRoute(
    pickupName: j['pickupName']?.toString() ?? '',
    dropoffName: j['dropoffName']?.toString() ?? '',
    days: ((j['days'] as List?) ?? const []).map((e) => e.toString()).toList(),
    departTime: j['departTime']?.toString() ?? '07:00',
  );

  Map<String, dynamic> toJson() => {
    'pickupName': pickupName,
    'dropoffName': dropoffName,
    'days': days,
    'departTime': departTime,
  };

  String get daysLabel {
    final set = days.toSet();
    if (set.length == 7) return 'Tous les jours';
    const weekdays = {'mon', 'tue', 'wed', 'thu', 'fri'};
    if (set.length == 5 && set.containsAll(weekdays)) return 'Lun – Ven';
    return dayCodes.where(set.contains).map((c) => dayShort[c]!).join(', ');
  }

  DateTime? nextDeparture([DateTime? from]) {
    final now = from ?? DateTime.now();
    final parts = departTime.split(':');
    final h = int.tryParse(parts.first) ?? 7;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    for (var i = 0; i < 8; i++) {
      final d = now.add(Duration(days: i));
      if (!days.contains(dayCodes[d.weekday - 1])) continue;
      final candidate = DateTime(d.year, d.month, d.day, h, m);
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }

  /// Ex. « Demain à 07:15 », « Aujourd’hui à 07:15 », « Lun à 07:15 ».
  String nextLabel([DateTime? from]) {
    final now = from ?? DateTime.now();
    final next = nextDeparture(now);
    if (next == null) return 'Aucun trajet prévu';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(next.year, next.month, next.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Aujourd’hui à $departTime';
    if (diff == 1) return 'Demain à $departTime';
    return '${dayShort[dayCodes[next.weekday - 1]]} à $departTime';
  }
}

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.firstName,
    required this.age,
    required this.authorized,
    required this.paused,
    required this.route,
    required this.contactName,
    required this.contactPhone,
    required this.alertPrefs,
  });

  final String id;
  final String firstName;
  final int age;
  final bool authorized;
  final bool paused;
  final ChildRoute? route;
  final String? contactName;
  final String? contactPhone;
  final Map<String, bool> alertPrefs;

  factory ChildProfile.fromJson(Map<String, dynamic> j) {
    final route = j['route'];
    final contact = j['trustedContact'];
    final prefs = (j['alertPrefs'] as Map?) ?? const {};
    return ChildProfile(
      id: j['id'].toString(),
      firstName: j['firstName']?.toString() ?? '',
      age: (j['age'] as num?)?.toInt() ?? 0,
      authorized: j['authorized'] != false,
      paused: j['paused'] == true,
      route: route is Map ? ChildRoute.fromJson(Map<String, dynamic>.from(route)) : null,
      contactName: contact is Map ? contact['name']?.toString() : null,
      contactPhone: contact is Map ? contact['phone']?.toString() : null,
      alertPrefs: {
        'onDeparture': prefs['onDeparture'] != false,
        'onArrival': prefs['onArrival'] != false,
        'onDelay': prefs['onDelay'] != false,
      },
    );
  }

  ChildProfile copyWith({bool? paused, Map<String, bool>? alertPrefs}) => ChildProfile(
    id: id,
    firstName: firstName,
    age: age,
    authorized: authorized,
    paused: paused ?? this.paused,
    route: route,
    contactName: contactName,
    contactPhone: contactPhone,
    alertPrefs: alertPrefs ?? this.alertPrefs,
  );
}

class ChildrenApi {
  ChildrenApi(this.token);

  final String token;

  /// Dernière liste connue : permet d'afficher l'écran instantanément à la réouverture.
  static List<ChildProfile>? cache;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _send(
      String method,
      String path, {
        Object? body,
        int timeoutSeconds = 10,
      }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/routes/students$path');
    final encoded = body == null ? null : jsonEncode(body);
    try {
      final Future<http.Response> request;
      switch (method) {
        case 'POST':
          request = http.post(uri, headers: _headers, body: encoded);
          break;
        case 'PATCH':
          request = http.patch(uri, headers: _headers, body: encoded);
          break;
        case 'DELETE':
          request = http.delete(uri, headers: _headers);
          break;
        default:
          request = http.get(uri, headers: _headers);
      }
      final res = await request.timeout(Duration(seconds: timeoutSeconds));
      final data = _decode(res);
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      if (res.statusCode == 401) {
        throw ChildrenApiException('Votre session a expiré, reconnectez-vous.');
      }
      throw ChildrenApiException(
        data['detail']?.toString() ?? 'Erreur serveur (${res.statusCode}).',
      );
    } on TimeoutException {
      throw ChildrenApiException('Le serveur ne répond pas. Réessayez.');
    } on http.ClientException {
      throw ChildrenApiException('Impossible de joindre le serveur.');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Future<List<ChildProfile>> list() async {
    final data = await _send('GET', '', timeoutSeconds: 8);
    final items = (data['students'] as List?) ?? const [];
    final result = items
        .map((e) => ChildProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    cache = result;
    return result;
  }

  Future<ChildProfile> create({
    required String firstName,
    required int age,
    required ChildRoute route,
    required String contactName,
    required String contactPhone,
  }) async {
    final data = await _send('POST', '', body: {
      'firstName': firstName,
      'age': age,
      'route': route.toJson(),
      'trustedContact': {'name': contactName, 'phone': contactPhone},
      'parentalConsent': true,
    });
    return ChildProfile.fromJson(data);
  }

  Future<ChildProfile> update(String id, Map<String, dynamic> patch) async {
    final data = await _send('PATCH', '/$id', body: patch);
    return ChildProfile.fromJson(data);
  }

  Future<void> delete(String id) async {
    await _send('DELETE', '/$id');
  }
}