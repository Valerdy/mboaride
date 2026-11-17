import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Circle;
import '../app_services.dart';
import '../core/api_client.dart';
import '../core/auth_session.dart';
import '../core/road_routing.dart';
import '../features/children/presentation/children_screen.dart';
import '../features/driver/presentation/driver_shell.dart';
import '../features/intercity/presentation/intercity_screen.dart';
import '../features/offers/presentation/my_requests_screen.dart';
import '../features/offers/presentation/offers_screen.dart';
import '../features/payment/presentation/my_trips_screen.dart';
import '../features/preferences/domain/preferences.dart';
import '../features/preferences/presentation/preferences_screen.dart';
import '../features/ride_request/data/ride_request_repository.dart';
import '../features/ride_request/domain/ride_request.dart';
import 'profile_screen.dart';

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
  final RoadRouting _roadRouting = RoadRouting();

  TimeOfDay _windowStart = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _windowEnd = const TimeOfDay(hour: 8, minute: 0);

  // Climatisation non exigée par défaut : exigée, elle écarte tous les véhicules sans clim.
  bool _climatisation = false;

  /// Avec qui voyager : tout MboaRide par défaut, pour voir tous les conducteurs agréés.
  Circle _circle = Circle.public;
  bool _silence = false;
  bool _isLoading = false;
  bool _isRouteLoading = false;
  bool _selectingOriginOnMap = true;
  RideDay _day = RideDay.today;

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
    final n = DateTime.now();
    _day = n.hour * 60 + n.minute >= 7 * 60 + 30 ? RideDay.tomorrow : RideDay.today;
    if (widget.token.isNotEmpty) AuthSession.accessToken = widget.token;
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
    _mapController.dispose();
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

  /// Tracé sur les routes de Douala (OpenStreetMap, OSRM), jamais à vol d'oiseau : sans
  /// itinéraire routier disponible, la carte montre seulement le départ et l'arrivée.
  Future<void> _fetchOsrmRoute() async {
    if (_originCoords == null || _destCoords == null) return;
    final from = _originCoords!, to = _destCoords!;
    setState(() {
      _isRouteLoading = true;
      _routePoints = [];
      _routeSummary = "Calcul de l'itinéraire par la route…";
    });
    final route = await _roadRouting.route([from, to]);
    if (!mounted || from != _originCoords || to != _destCoords) return; // points changés entre-temps
    setState(() {
      _isRouteLoading = false;
      if (route == null) {
        _routePoints = [];
        _routeSummary = 'Itinéraire routier indisponible pour le moment';
      } else {
        _routePoints = route.points;
        _routeSummary = '${route.distanceKm.toStringAsFixed(1)} km • ~${route.durationMin} min par la route';
      }
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
    final now = DateTime.now();
    final base = _day == RideDay.today ? now : now.add(const Duration(days: 1));
    final start = DateTime(base.year, base.month, base.day, _windowStart.hour, _windowStart.minute);
    final end = DateTime(base.year, base.month, base.day, _windowEnd.hour, _windowEnd.minute);
    final price = int.tryParse(_priceController.text.trim());

    final pickup = _originCoords == null
        ? null
        : Place(
      name: _originController.text.trim().isEmpty ? 'Départ' : _originController.text.trim(),
      lat: _originCoords!.latitude,
      lng: _originCoords!.longitude,
    );
    final dropoff = _destCoords == null
        ? null
        : Place(
      name: _destinationController.text.trim().isEmpty ? 'Arrivée' : _destinationController.text.trim(),
      lat: _destCoords!.latitude,
      lng: _destCoords!.longitude,
    );

    final validation = validateRideRequest(
      pickup: pickup,
      dropoff: dropoff,
      windowStart: start,
      windowEnd: end,
      maxPriceFcfa: price,
      now: now,
    );
    if (!validation.isValid) {
      _showSnack(validation.errors.values.first, isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await AppServices.rideRequests.create(
        RideRequest(
          pickup: pickup!,
          dropoff: dropoff!,
          windowStart: start,
          windowEnd: end,
          maxPriceFcfa: price!,
          comforts: <Comfort>{
            if (_climatisation) Comfort.airConditioning,
            if (_silence) Comfort.quiet,
          },
          circleCode: _circle.code,
        ),
      );
      if (!mounted) return;
      await _openOffers(result.id);
    } on RideRequestException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Une erreur inattendue est survenue', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Offres calculées par le moteur d'agents pour la demande qui vient d'être créée.
  Future<void> _openOffers(String requestId) async {
    final offers = AppServices.offers;
    try {
      final requests = await offers.openRequests();
      final created = requests.where((r) => '${r.id}' == requestId).firstOrNull;
      if (!mounted) return;
      if (created == null) {
        _showSnack('Demande enregistrée. Retrouvez-la dans « Mes demandes ».');
        _push(_myRequests());
        return;
      }
      _showSnack('Demande enregistrée : voici les offres de nos conducteurs.');
      final booked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => OffersScreen(repository: offers, request: created)),
      );
      if (booked == true && mounted) _push(MyTripsScreen(repository: AppServices.payments));
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    }
  }

  Widget _myRequests() => MyRequestsScreen(
    offers: AppServices.offers,
    preferences: AppServices.preferences,
    childrenRepository: AppServices.children,
    intercityRepository: AppServices.intercity,
  );

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  void _openProfile() => _push(const ProfileScreen());

  Widget _drawerItem(IconData icon, String title, Widget screen) => ListTile(
    leading: Icon(icon, color: primaryGreen),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    onTap: () {
      Navigator.pop(context);
      _push(screen);
    },
  );

  @override
  Widget build(BuildContext context) {
    final bool isReady = _originCoords != null && _destCoords != null;

    return Scaffold(
      backgroundColor: bgBeige,
      drawer: Drawer(
        backgroundColor: bgBeige,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryGreen, darkGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MboaRide',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Covoiturage urbain & interurbain',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.local_taxi_rounded, color: primaryGreen),
                title: const Text('Trajet urbain (Douala)', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context),
              ),
              _drawerItem(Icons.event_seat_rounded, 'Mes trajets (à confirmer, confirmés)',
                  MyTripsScreen(repository: AppServices.payments)),
              _drawerItem(Icons.receipt_long_rounded, 'Mes demandes et offres', _myRequests()),
              _drawerItem(Icons.tune_rounded, 'Mes exigences de confort',
                  PreferencesScreen(repository: AppServices.preferences)),
              _drawerItem(Icons.directions_car_rounded, 'Voyage Douala → Yaoundé',
                  IntercityScreen(repository: AppServices.intercity)),
              _drawerItem(Icons.school_rounded, 'Mes enfants (scolaire)',
                  ChildrenScreen(repository: AppServices.children)),
              _drawerItem(Icons.drive_eta_rounded, 'Espace conducteur',
                  DriverShell(repository: AppServices.driver)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_rounded, color: darkGreen),
                title: const Text('Mon profil & Services', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _openProfile();
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 46, bottom: 24, left: 16, right: 16),
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
            child: Row(
              children: [
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
                    tooltip: 'Menu des services',
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Où allez-vous ?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Planifiez votre trajet partagé à Douala',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openProfile,
                  tooltip: 'Mon profil',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                  ),
                  icon: const Icon(Icons.person_rounded, color: Colors.white),
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

                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RideDay>(
                      segments: const [
                        ButtonSegment(value: RideDay.today, label: Text("Aujourd'hui")),
                        ButtonSegment(value: RideDay.tomorrow, label: Text('Demain')),
                      ],
                      selected: {_day},
                      onSelectionChanged: (s) => setState(() => _day = s.first),
                    ),
                  ),

                  const SizedBox(height: 12),

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

                  const SizedBox(height: 14),

                  const Text(
                    'Avec qui voyager ?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkGreen),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final circle in Circle.values)
                        ChoiceChip(
                          label: Text(circle == Circle.public ? 'Tout MboaRide' : circle.label),
                          selected: _circle == circle,
                          selectedColor: softGreen,
                          onSelected: (_) => setState(() => _circle = circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _circle.description,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                              initialCenter: const LatLng(4.0511, 9.7011),
                              initialZoom: 12.2,
                              onTap: (_, latLng) {
                                final label = '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
                                _updatePoint(latLng, label, isOrigin: _selectingOriginOnMap);
                              },
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
                                      strokeWidth: 4.5,
                                      color: primaryGreen,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (_originCoords != null)
                                    Marker(
                                      point: _originCoords!,
                                      width: 38,
                                      height: 38,
                                      child: const Icon(Icons.radio_button_checked, color: primaryGreen, size: 30),
                                    ),
                                  if (_destCoords != null)
                                    Marker(
                                      point: _destCoords!,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 36),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildMapModeBtn('Départ', _selectingOriginOnMap, () => setState(() => _selectingOriginOnMap = true)),
                                  _buildMapModeBtn('Arrivée', !_selectingOriginOnMap, () => setState(() => _selectingOriginOnMap = false)),
                                ],
                              ),
                            ),
                          ),
                          if (_routeSummary.isNotEmpty || _isRouteLoading)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: primaryGreen,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: _isRouteLoading
                                    ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                                    : Text(
                                  _routeSummary,
                                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isLoading || !isReady) ? null : _submitRideRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                        'Trouver un équipage',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildMapModeBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildCleanInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required ValueChanged<String> onSubmitted,
    required VoidCallback onClear,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13.5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.close, size: 16, color: Colors.black45),
          onPressed: () {
            controller.clear();
            onClear();
          },
        )
            : null,
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: primaryGreen),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildTimePill(String time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          time,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: primaryGreen),
        ),
      ),
    );
  }

  Widget _buildPreferencePill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? primaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? primaryGreen : Colors.black12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : primaryGreen),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}