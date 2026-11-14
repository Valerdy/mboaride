import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/app_config.dart';

typedef CrewMember = Map<String, dynamic>;

class CrewMapScreen extends StatefulWidget {
  final String requestId;
  final String token;
  final LatLng initialPickup;
  final LatLng initialDropoff;
  final String pickupName;
  final String dropoffName;

  const CrewMapScreen({
    super.key,
    required this.requestId,
    required this.token,
    required this.initialPickup,
    required this.initialDropoff,
    required this.pickupName,
    required this.dropoffName,
  });

  @override
  State<CrewMapScreen> createState() => _CrewMapScreenState();
}

class _CrewMapScreenState extends State<CrewMapScreen> {
  final MapController _mapController = MapController();

  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color darkGreen = Color(0xFF074731);
  static const Color softGreen = Color(0xFFE6F2ED);
  static const Color bgBeige = Color(0xFFF6F5F0);

  String _crewStatus = 'searching';
  String? _crewId;
  String? _driverId;
  List<CrewMember> _members = [];
  List<LatLng> _routePoints = [];
  String _routeMetrics = '';
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadCrewAndRoute();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
          (_) => _loadCrewAndRoute(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadCrewAndRoute({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/routes/ride-requests/${widget.requestId}'),
        headers: {
          'Content-Type': 'application/json',
          if (widget.token.isNotEmpty) 'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final reqData = data['request'] as CrewMember?;
        final crewData = data['crew'] as CrewMember?;

        final List<CrewMember> members =
        crewData != null && crewData['members'] != null
            ? List<CrewMember>.from(crewData['members'] as List)
            : [
          {
            'id': widget.requestId,
            'pickup_name': widget.pickupName,
            'pickup_lat': widget.initialPickup.latitude,
            'pickup_lng': widget.initialPickup.longitude,
            'dropoff_name': widget.dropoffName,
            'dropoff_lat': widget.initialDropoff.latitude,
            'dropoff_lng': widget.initialDropoff.longitude,
            'max_price_fcfa': 500,
          }
        ];

        if (mounted) {
          setState(() {
            _crewId = crewData?['id']?.toString();
            _driverId = crewData?['driver_id']?.toString();
            _crewStatus = crewData?['status']?.toString() ??
                reqData?['status']?.toString() ??
                'searching';
            _members = members;
          });
        }

        await _computeMultiStopRoute(members);
      } else {
        await _computeMultiStopRoute([]);
      }
    } catch (_) {
      await _computeMultiStopRoute([]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _computeMultiStopRoute(List<CrewMember> members) async {
    final List<LatLng> waypoints = [];

    if (members.isEmpty) {
      waypoints.add(widget.initialPickup);
      waypoints.add(widget.initialDropoff);
    } else {
      for (final m in members) {
        waypoints.add(
          LatLng(
            (m['pickup_lat'] as num).toDouble(),
            (m['pickup_lng'] as num).toDouble(),
          ),
        );
      }
      for (final m in members) {
        final dest = LatLng(
          (m['dropoff_lat'] as num).toDouble(),
          (m['dropoff_lng'] as num).toDouble(),
        );
        if (waypoints.isEmpty ||
            (waypoints.last.latitude - dest.latitude).abs() > 0.001 ||
            (waypoints.last.longitude - dest.longitude).abs() > 0.001) {
          waypoints.add(dest);
        }
      }
    }

    final coordsParam = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordsParam?overview=full&geometries=geojson',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final List coords = route['geometry']['coordinates'];
          final double km = (route['distance'] ?? 0) / 1000.0;
          final int min = ((route['duration'] ?? 0) / 60).round();

          final points =
          coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();

          if (mounted) {
            setState(() {
              _routePoints = points;
              _routeMetrics = '${km.toStringAsFixed(1)} km • ~$min min';
            });
            _fitCamera(waypoints, points);
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _routePoints = waypoints;
        _routeMetrics = 'Trajet Douala';
      });
      _fitCamera(waypoints, waypoints);
    }
  }

  void _fitCamera(List<LatLng> waypoints, List<LatLng> polyline) {
    final all = <LatLng>[...waypoints, ...polyline];
    if (all.length < 2) return;
    try {
      final bounds = LatLngBounds.fromPoints(all);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 90, 40, 260),
        ),
      );
    } catch (_) {}
  }

  String _statusLabel() {
    if (_driverId != null && _driverId!.isNotEmpty) {
      return 'Conducteur assigné • En route';
    }
    if (_crewStatus == 'matched' || _members.length >= 2) {
      return 'Équipage formé (${_members.length} covoitureurs)';
    }
    return 'Recherche de covoitureurs à Douala...';
  }

  Color _statusColor() {
    if (_driverId != null && _driverId!.isNotEmpty) return darkGreen;
    if (_crewStatus == 'matched' || _members.length >= 2) return primaryGreen;
    return Colors.orange.shade800;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgBeige,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialPickup,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mboaride',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.5,
                      color: primaryGreen,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.initialPickup,
                    width: 46,
                    height: 46,
                    child: _buildBadgeMarker(
                      Icons.person_pin_circle,
                      primaryGreen,
                      'Moi',
                    ),
                  ),
                  ..._members
                      .asMap()
                      .entries
                      .where((e) => e.value['id'] != widget.requestId)
                      .map((entry) {
                    final m = entry.value;
                    final pt = LatLng(
                      (m['pickup_lat'] as num).toDouble(),
                      (m['pickup_lng'] as num).toDouble(),
                    );
                    return Marker(
                      point: pt,
                      width: 46,
                      height: 46,
                      child: _buildBadgeMarker(
                        Icons.group,
                        Colors.blue.shade700,
                        'P${entry.key + 1}',
                      ),
                    );
                  }),
                  Marker(
                    point: widget.initialDropoff,
                    width: 46,
                    height: 46,
                    child: _buildBadgeMarker(
                      Icons.flag_rounded,
                      Colors.redAccent,
                      'Arrivée',
                    ),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: primaryGreen),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: _statusColor()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusLabel(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _statusColor(),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _crewId != null
                                ? 'Équipage #${_crewId!.substring(0, 6).toUpperCase()}'
                                : 'Votre trajet',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkGreen,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.pickupName} → ${widget.dropoffName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      if (_routeMetrics.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: softGreen,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _routeMetrics,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Membres de l’équipage',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoading && _members.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(color: primaryGreen),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 130),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _members.isEmpty ? 1 : _members.length,
                        separatorBuilder: (_, __) => const Divider(height: 10),
                        itemBuilder: (context, index) {
                          if (_members.isEmpty) {
                            return _buildMemberRow(
                              name: 'Vous (Passager 1)',
                              route: '${widget.pickupName} → ${widget.dropoffName}',
                              isCurrentUser: true,
                            );
                          }
                          final m = _members[index];
                          final isMe = m['id'] == widget.requestId;
                          return _buildMemberRow(
                            name: isMe
                                ? 'Vous (Passager ${index + 1})'
                                : 'Covoitureur ${index + 1}',
                            route: '${m['pickup_name']} → ${m['dropoff_name']}',
                            isCurrentUser: isMe,
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'Modifier ou annuler la demande',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeMarker(IconData icon, Color color, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberRow({
    required String name,
    required String route,
    required bool isCurrentUser,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isCurrentUser ? primaryGreen : softGreen,
          child: Icon(
            Icons.person,
            size: 16,
            color: isCurrentUser ? Colors.white : primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                route,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_circle,
          size: 18,
          color: isCurrentUser ? primaryGreen : Colors.grey.shade400,
        ),
      ],
    );
  }
}