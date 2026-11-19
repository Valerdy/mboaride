import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/organisations_repository.dart';
import '../domain/organisation.dart';

/// Mes organisations : mon entreprise, l'école de mes enfants, un campus. Elles forment mon cercle de
/// confiance : leurs membres me voient en priorité dans les offres de trajet.
class OrganisationsScreen extends StatefulWidget {
  const OrganisationsScreen({super.key, required this.repository});

  final OrganisationsRepository repository;

  @override
  State<OrganisationsScreen> createState() => _OrganisationsScreenState();
}

class _OrganisationsScreenState extends State<OrganisationsScreen> {
  List<Organisation> _organisations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.mine();
      if (!mounted) return;
      setState(() {
        _organisations = list;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _say(String message, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: error ? MboaColors.red : MboaColors.night),
  );

  Future<void> _join() async {
    final joined = await showModalBottomSheet<Organisation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _JoinSheet(repository: widget.repository),
    );
    if (joined == null || !mounted) return;
    _say('Vous avez rejoint ${joined.name}.');
    _load();
  }

  Future<void> _leave(Organisation organisation) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Quitter ${organisation.name} ?'),
        content: const Text('Vous ne ferez plus partie de son cercle de confiance. Vous pourrez la rejoindre de nouveau avec son code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rester')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MboaColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.leave(organisation.id);
      if (mounted) _say('Vous avez quitté ${organisation.name}.');
    } on ApiException catch (error) {
      if (mounted) _say(error.message, error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mes organisations')),
    floatingActionButton: FloatingActionButton.extended(
      key: const ValueKey('rejoindre-organisation'),
      onPressed: _join,
      icon: const Icon(Icons.group_add_outlined),
      label: const Text('Rejoindre avec un code'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
              children: [
                const Text(
                  'Votre entreprise, l\'école de vos enfants, un campus : ce sont vos cercles de confiance. '
                  'Une école ou un campus se rejoint avec son code. Une entreprise vous invite par e-mail : '
                  'suivez le lien reçu.',
                  style: TextStyle(fontSize: 13, color: MboaColors.mutedText, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (_error != null) Text(_error!, style: const TextStyle(color: MboaColors.red)),
                if (_error == null && _organisations.isEmpty)
                  const Text('Vous ne faites partie d\'aucune organisation pour le moment.', style: TextStyle(color: MboaColors.mutedText)),
                for (final o in _organisations) _OrganisationCard(organisation: o, onLeave: () => _leave(o)),
              ],
            ),
    ),
  );
}

class _OrganisationCard extends StatelessWidget {
  const _OrganisationCard({required this.organisation, required this.onLeave});

  final Organisation organisation;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: MboaDecor.card(),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MboaColors.greenSoft, borderRadius: BorderRadius.circular(12)),
          child: Icon(
            switch (organisation.type) {
              'etablissement_scolaire' || 'campus' => Icons.school_outlined,
              'evenement' => Icons.event_outlined,
              _ => Icons.business_outlined,
            },
            color: MboaColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(organisation.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: MboaColors.night)),
              const SizedBox(height: 2),
              Text(
                '${organisation.typeLabel} · ${organisation.isAdmin ? 'administrateur' : 'membre'}',
                style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
              ),
            ],
          ),
        ),
        if (!organisation.isAdmin)
          TextButton(onPressed: onLeave, child: const Text('Quitter')),
      ],
    ),
  );
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.repository});

  final OrganisationsRepository repository;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _code = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().length < 3) {
      setState(() => _error = 'Saisissez le code de l\'organisation.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final organisation = await widget.repository.join(_code.text);
      if (mounted) Navigator.of(context).pop(organisation);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rejoindre une organisation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MboaColors.night)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('code-organisation'),
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Code de l\'organisation', helperText: 'Par exemple COLB-2026, donné par l\'école'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(fontSize: 13, color: MboaColors.red)),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving ? null : _join,
          child: _saving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Rejoindre'),
        ),
      ],
    ),
  );
}
