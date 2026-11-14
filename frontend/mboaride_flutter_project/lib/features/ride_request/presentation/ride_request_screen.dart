import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_config.dart';
import '../../../core/mboa_theme.dart';
import '../data/api_ride_request_repository.dart';
import '../data/nominatim_place_search.dart';
import '../data/place_search_service.dart';
import '../data/ride_request_repository.dart';
import '../domain/ride_request.dart';
import 'place_search_sheet.dart';
import 'ride_request_controller.dart';

/// US04 : le passager demande un trajet avec une fenêtre d'arrivée.
class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({
    super.key,
    this.repository,
    this.placeSearch,
    this.onSubmitted,
  });

  /// Pour les tests ou pour brancher une autre source. Par défaut : selon AppConfig.useFakeApi.
  final RideRequestRepository? repository;
  final PlaceSearchService? placeSearch;

  /// Appelé quand la demande est acceptée (ex. pour ouvrir l'écran des propositions, US05).
  /// Si absent, une boîte de dialogue de confirmation s'affiche.
  final void Function(RideRequestResult result)? onSubmitted;

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  late final RideRequestController _controller;
  late final PlaceSearchService _placeSearch;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _placeSearch = widget.placeSearch ?? NominatimPlaceSearch();
    _controller = RideRequestController(
      repository:
          widget.repository ??
          (AppConfig.useFakeApi
              ? FakeRideRequestRepository()
              : ApiRideRequestRepository()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _pickPlace({required bool isPickup}) async {
    final place = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PlaceSearchSheet(
        service: _placeSearch,
        title: isPickup ? 'Point de départ' : 'Destination',
      ),
    );
    if (place == null) return;
    if (isPickup) {
      _controller.setPickup(place);
    } else {
      _controller.setDropoff(place);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
  }

  void _fitMap() {
    final a = _controller.pickup;
    final b = _controller.dropoff;
    try {
      if (a != null && b != null) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)),
            padding: const EdgeInsets.all(48),
            maxZoom: 16,
          ),
        );
      } else if (a != null || b != null) {
        final p = (a ?? b)!;
        _mapController.move(LatLng(p.lat, p.lng), 14);
      }
    } catch (_) {
      // La carte n'est pas encore prête : on ignore.
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _controller.fromMinutes : _controller.toMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: isStart ? 'Arrivée au plus tôt' : 'Arrivée au plus tard',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    if (isStart) {
      _controller.setFromMinutes(minutes);
    } else {
      _controller.setToMinutes(minutes);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final ok = await _controller.submit();
    if (!mounted || !ok) return;
    final result = _controller.result!;
    final callback = widget.onSubmitted;
    if (callback != null) {
      callback(result);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demande envoyée'),
        content: Text(
          "Nous recherchons un équipage pour vous.\nRéférence : ${result.id}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Où allez-vous ?')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final c = _controller;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (c.errorMessage != null)
                  _ErrorBanner(message: c.errorMessage!),
                _PlaceField(
                  label: 'Départ',
                  icon: Icons.trip_origin,
                  place: c.pickup,
                  error: c.errors['pickup'],
                  onTap: () => _pickPlace(isPickup: true),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: c.swapPlaces,
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Inverser'),
                  ),
                ),
                _PlaceField(
                  label: 'Arrivée',
                  icon: Icons.flag_outlined,
                  place: c.dropoff,
                  error: c.errors['dropoff'],
                  onTap: () => _pickPlace(isPickup: false),
                ),
                const SizedBox(height: 20),
                const _SectionLabel("Fenêtre d'arrivée"),
                SegmentedButton<RideDay>(
                  segments: const [
                    ButtonSegment(
                      value: RideDay.today,
                      label: Text("Aujourd'hui"),
                    ),
                    ButtonSegment(
                      value: RideDay.tomorrow,
                      label: Text('Demain'),
                    ),
                  ],
                  selected: {c.day},
                  onSelectionChanged: (selection) => c.setDay(selection.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: 'Entre',
                        minutes: c.fromMinutes,
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeField(
                        label: 'et',
                        minutes: c.toMinutes,
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                if (c.errors['window'] != null)
                  _FieldError(c.errors['window']!),
                const SizedBox(height: 20),
                TextField(
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Prix maximal',
                    hintText: '500',
                    suffixText: 'FCFA',
                    errorText: c.errors['price'],
                  ),
                  onChanged: c.setPriceText,
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Confort'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final comfort in Comfort.values)
                      FilterChip(
                        label: Text(comfort.label),
                        selected: c.comforts.contains(comfort),
                        onSelected: (_) => c.toggleComfort(comfort),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 220,
                    child: _RouteMap(
                      controller: _mapController,
                      pickup: c.pickup,
                      dropoff: c.dropoff,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: c.isSubmitting ? null : _submit,
                  child: c.isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Trouver un équipage'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: MboaColors.mutedText),
    ),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MboaColors.sun,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: MboaColors.night,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.label,
    required this.icon,
    required this.place,
    required this.onTap,
    this.error,
  });

  final String label;
  final IconData icon;
  final Place? place;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = place;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: current == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.search),
          errorText: error,
        ),
        child: current == null
            ? const SizedBox.shrink()
            : Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onTap,
  });

  final String label;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.access_time),
      ),
      child: Text(formatMinutes(minutes)),
    ),
  );
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.controller,
    required this.pickup,
    required this.dropoff,
  });

  final MapController controller;
  final Place? pickup;
  final Place? dropoff;

  Marker _marker(Place place, Color color) => Marker(
    point: LatLng(place.lat, place.lng),
    width: 40,
    height: 40,
    alignment: Alignment.topCenter,
    child: Icon(Icons.location_on, color: color, size: 40),
  );

  @override
  Widget build(BuildContext context) {
    final a = pickup;
    final b = dropoff;
    return FlutterMap(
      mapController: controller,
      options: const MapOptions(
        initialCenter: LatLng(AppConfig.centerLat, AppConfig.centerLng),
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // À remplacer par l'identifiant réel de l'application (applicationId Android).
          userAgentPackageName: 'com.example.mboaride',
        ),
        MarkerLayer(
          markers: [
            if (a != null) _marker(a, MboaColors.green),
            if (b != null) _marker(b, MboaColors.red),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© contributeurs OpenStreetMap'),
          ],
        ),
      ],
    );
  }
}
