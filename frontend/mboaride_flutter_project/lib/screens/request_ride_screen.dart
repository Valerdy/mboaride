import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RequestRideScreen extends StatefulWidget {
  final String token;

  const RequestRideScreen({super.key, required this.token});

  @override
  State<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends State<RequestRideScreen> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController(text: '500');
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();
  final MapController _mapController = MapController();

  TimeOfDay _windowStart = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _windowEnd = const TimeOfDay(hour: 8, minute: 0);

  bool _climatisation = true;
  bool _silence = false;
  bool _isLoading = false;
  bool _isRouteLoading = false;
  bool _selectingOriginOnMap = true;

  LatLng? _originCoords;
  LatLng? _destCoords;
  List<LatLng> _routePoints = [];
  String _routeSummary = '';

  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color darkGreen = Color(0xFF074731);
  static const Color softGreen = Color(0xFFE6F2ED);
  static const Color bgBeige = Color(0xFFF6F5F0);

  final Map<String, LatLng> _doualaNeighborhoods = {
    'Logpom': const LatLng(4.0846, 9.7562),
    'Bonanjo': const LatLng(4.0435, 9.6908),
    'Akwa': const LatLng(4.0511, 9.7011),
    'Bonapriso': const LatLng(4.0267, 9.7019),
    'Makepe': const LatLng(4.0753, 9.7423),
    'Ndokoti': const LatLng(4.0489, 9.7431),
    'Deido': const LatLng(4.0619, 9.7128),
    'Bonamoussadi': const LatLng(4.0892, 9.7385),
    'Yassa': const LatLng(4.0086, 9.8114),
    'Bonabéri': const LatLng(4.0764, 9.6644),
  };

  @override
  void initState() {
    super.initState();
    _originFocus.addListener(() {
      if (_originFocus.hasFocus) {
        setState(() => _selectingOriginOnMap = true);
      }
    });
    _destFocus.addListener(() {
      if (_destFocus.hasFocus) {
        setState(() => _selectingOriginOnMap = false);
      }
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _priceController.dispose();
    _originFocus.dispose();
    _destFocus.dispose();
    super.dispose();
  }

  Future<void> _searchLocation(String query, {required bool isOrigin}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        if (isOrigin) {
          _originCoords = null;
        } else {
          _destCoords = null;
        }
        _routePoints = [];
        _routeSummary = '';
      });
      return;
    }

    for (final entry in _doualaNeighborhoods.entries) {
      if (entry.key.toLowerCase() == trimmed.toLowerCase()) {
        _updatePoint(entry.value, entry.key, isOrigin: isOrigin);
        return;
      }
    }

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent('$trimmed, Douala, Cameroon')}&format=json&limit=1',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List results = jsonDecode(response.body);
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat']);
          final lon = double.parse(results[0]['lon']);
          _updatePoint(LatLng(lat, lon), trimmed, isOrigin: isOrigin);
          return;
        }
      }

      if (mounted) {
        _showSnack('Lieu "$trimmed" introuvable à Douala', isError: true);
      }
    } catch (e) {
      debugPrint('Erreur géocodage Nominatim: $e');
    }
  }

  void _updatePoint(LatLng coords, String label, {required bool isOrigin}) {
    setState(() {
      if (isOrigin) {
        _originCoords = coords;
        _originController.text = label;
        if (_destCoords == null) _selectingOriginOnMap = false;
      } else {
        _destCoords = coords;
        _destinationController.text = label;
      }
    });

    if (_originCoords != null && _destCoords != null) {
      _fetchOsrmRoute();
    } else {
      _mapController.move(coords, 14.0);
    }
  }

  void _swapLocations() {
    setState(() {
      final tempText = _originController.text;
      _originController.text = _destinationController.text;
      _destinationController.text = tempText;

      final tempCoords = _originCoords;
      _originCoords = _destCoords;
      _destCoords = tempCoords;
    });

    if (_originCoords != null && _destCoords != null) {
      _fetchOsrmRoute();
    }
  }

  Future<void> _fetchOsrmRoute() async {
    if (_originCoords == null || _destCoords == null) return;
    setState(() => _isRouteLoading = true);

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/routes/route'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'from': {'lat': _originCoords!.latitude, 'lng': _originCoords!.longitude},
          'to': {'lat': _destCoords!.latitude, 'lng': _destCoords!.longitude},
          'include_geometry': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final geometry = data['geometry'];
        final double distanceKm = (data['distance_m'] ?? 0) / 1000.0;
        final int durationMin = ((data['duration_s'] ?? 0) / 60).round();

        if (geometry != null && geometry['coordinates'] != null) {
          final List coords = geometry['coordinates'];
          final points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();

          setState(() {
            _routePoints = points;
            _routeSummary = '${distanceKm.toStringAsFixed(1)} km • ~$durationMin min';
          });
          _fitMapBounds();
          return;
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement itinéraire OSRM: $e');
    } finally {
      if (mounted) setState(() => _isRouteLoading = false);
    }

    setState(() {
      _routePoints = [_originCoords!, _destCoords!];
      _routeSummary = 'Itinéraire direct';
    });
    _fitMapBounds();
  }

  void _fitMapBounds() {
    if (_originCoords == null || _destCoords == null) return;
    try {
      final bounds = LatLngBounds.fromPoints([_originCoords!, _destCoords!, ..._routePoints]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(45)),
      );
    } catch (_) {}
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _windowStart : _windowEnd,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _windowStart = picked;
        } else {
          _windowEnd = picked;
        }
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _submitRideRequest() async {
    if (_originCoords == null || _destCoords == null) {
      _showSnack('Veuillez sélectionner un point de départ et une destination', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startDt = DateTime(now.year, now.month, now.day, _windowStart.hour, _windowStart.minute);
      final endDt = DateTime(now.year, now.month, now.day, _windowEnd.hour, _windowEnd.minute);

      final response = await http.post(
        Uri.parse('http://localhost:8000/routes/ride-requests'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'origin': {'lat': _originCoords!.latitude, 'lng': _originCoords!.longitude},
          'destination': {'lat': _destCoords!.latitude, 'lng': _destCoords!.longitude},
          'windowStart': startDt.toUtc().toIso8601String(),
          'windowEnd': endDt.toUtc().toIso8601String(),
          'maxPrice': int.tryParse(_priceController.text) ?? 500,
          'currency': 'XAF',
          'preferences': {
            'airConditioning': _climatisation,
            'silence': _silence,
          },
        }),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnack('Demande envoyée ! Recherche d\'équipage en cours...');
      } else {
        _showSnack(data['detail'] ?? data['message'] ?? 'Données invalides', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Impossible de joindre le serveur', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _originCoords != null && _destCoords != null;

    return Scaffold(
      backgroundColor: bgBeige,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 52, bottom: 26, left: 22, right: 22),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryGreen, darkGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Où allez-vous ?',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
                const SizedBox(height: 4),
                Text(
                  'Planifiez votre trajet partagé à Douala',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Column(
                          children: [
                            const Icon(Icons.radio_button_checked, color: primaryGreen, size: 18),
                            Container(width: 2, height: 34, color: Colors.grey.shade300),
                            const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            children: [
                              _buildCleanInput(
                                controller: _originController,
                                focusNode: _originFocus,
                                hint: 'Point de départ (ex: Logpom)',
                                onSubmitted: (val) => _searchLocation(val, isOrigin: true),
                                onClear: () => _searchLocation('', isOrigin: true),
                              ),
                              Divider(height: 16, color: Colors.grey.shade200),
                              _buildCleanInput(
                                controller: _destinationController,
                                focusNode: _destFocus,
                                hint: 'Destination (ex: Bonanjo)',
                                onSubmitted: (val) => _searchLocation(val, isOrigin: false),
                                onClear: () => _searchLocation('', isOrigin: false),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _swapLocations,
                          tooltip: 'Inverser départ et arrivée',
                          style: IconButton.styleFrom(
                            backgroundColor: softGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.swap_vert, color: primaryGreen),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _doualaNeighborhoods.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final entry = _doualaNeighborhoods.entries.elementAt(index);
                        return ActionChip(
                          label: Text(entry.key, style: const TextStyle(fontSize: 12, color: primaryGreen, fontWeight: FontWeight.w500)),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: primaryGreen.withValues(alpha: 0.25)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          onPressed: () {
                            _updatePoint(entry.value, entry.key, isOrigin: _selectingOriginOnMap);
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildCardBlock(
                          title: 'Fenêtre d\'arrivée',
                          icon: Icons.access_time_rounded,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildTimePill(_formatTime(_windowStart), () => _selectTime(true)),
                              const Text('→', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black45)),
                              _buildTimePill(_formatTime(_windowEnd), () => _selectTime(false)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: _buildCardBlock(
                          title: 'Prix max',
                          icon: Icons.payments_outlined,
                          child: TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryGreen),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                              suffixText: 'FCFA',
                              suffixStyle: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      _buildPreferencePill(
                        label: 'Climatisation',
                        icon: Icons.ac_unit_rounded,
                        selected: _climatisation,
                        onTap: () => setState(() => _climatisation = !_climatisation),
                      ),
                      const SizedBox(width: 10),
                      _buildPreferencePill(
                        label: 'Silence',
                        icon: Icons.volume_off_rounded,
                        selected: _silence,
                        onTap: () => setState(() => _silence = !_silence),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Container(
                    height: 245,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: const LatLng(4.0550, 9.7250),
                              initialZoom: 12.0,
                              onTap: (tapPosition, latLng) {
                                final label = '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
                                _updatePoint(latLng, label, isOrigin: _selectingOriginOnMap);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                              ),
                              if (_routePoints.isNotEmpty)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _routePoints,
                                      strokeWidth: 5.0,
                                      color: primaryGreen,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (_originCoords != null)
                                    Marker(
                                      point: _originCoords!,
                                      width: 42,
                                      height: 42,
                                      child: const Icon(Icons.radio_button_checked, color: primaryGreen, size: 30),
                                    ),
                                  if (_destCoords != null)
                                    Marker(
                                      point: _destCoords!,
                                      width: 44,
                                      height: 44,
                                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 36),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                  ),
                                  child: Row(
                                    children: [
                                      _buildMapModeBtn('Départ', _selectingOriginOnMap, () => setState(() => _selectingOriginOnMap = true)),
                                      _buildMapModeBtn('Arrivée', !_selectingOriginOnMap, () => setState(() => _selectingOriginOnMap = false)),
                                    ],
                                  ),
                                ),
                                if (_routeSummary.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: primaryGreen,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                    ),
                                    child: Text(
                                      _routeSummary,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_isRouteLoading)
                            const Center(
                              child: CircleAvatar(
                                backgroundColor: Colors.white,
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: primaryGreen),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isReady
                          ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))]
                          : [],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isReady ? primaryGreen : Colors.grey.shade400,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : _submitRideRequest,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isLoading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                            : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_filled_rounded, color: Colors.white),
                            SizedBox(width: 10),
                            Text(
                              'Trouver un équipage',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
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

  Widget _buildCleanInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required Function(String) onSubmitted,
    required VoidCallback onClear,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onClear();
                },
                child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => onSubmitted(controller.text),
              child: const Icon(Icons.search, size: 20, color: primaryGreen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBlock({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.black54),
              const SizedBox(width: 5),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildTimePill(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGreen)),
      ),
    );
  }

  Widget _buildPreferencePill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? primaryGreen : Colors.grey.shade300),
          boxShadow: selected
              ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : primaryGreen),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapModeBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}