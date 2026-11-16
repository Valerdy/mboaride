import 'dart:async';

import 'package:flutter/material.dart';

import '../data/place_search_service.dart';
import '../domain/ride_request.dart';

/// Fenêtre de recherche d'un lieu. Retourne le [Place] choisi via Navigator.pop.
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.service,
    required this.title,
  });

  final PlaceSearchService service;
  final String title;

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final TextEditingController _textController = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  List<Place> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    // On attend que l'utilisateur arrête de taper (limite les appels au service).
    _debounce = Timer(const Duration(milliseconds: 700), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_requestId;
    if (text.trim().length < 3) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.service.search(text);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } on PlaceSearchException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = 'Recherche impossible. Vérifiez votre connexion.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Quartier, rue, lieu connu…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onChanged,
                onSubmitted: _search,
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_searched && _results.isEmpty && !_loading && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aucun lieu trouvé à Douala. Essayez un autre nom.',
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final place = _results[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(place.name),
                      onTap: () => Navigator.of(context).pop(place),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
