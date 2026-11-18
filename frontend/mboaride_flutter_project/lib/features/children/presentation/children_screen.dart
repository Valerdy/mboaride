import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/children_repository.dart';
import '../domain/child.dart';
import 'child_journal_screen.dart';

/// US17 · Créer un compte élève pour mes enfants de 12 ans et plus et
/// autoriser leurs trajets, pour garder le contrôle de qui les transporte.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key, required this.repository, this.schoolId});

  final ChildrenRepository repository;

  /// Établissement rattaché par défaut aux nouveaux comptes élèves, quand il
  /// est connu (école partenaire de MboaRide).
  final int? schoolId;

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  List<Child> _children = const [];
  bool _loading = true;
  String? _error;
  int? _busyChild;

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
      final children = await widget.repository.children();
      if (!mounted) return;
      setState(() {
        _children = children;
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

  Future<void> _toggle(Child child, bool value) async {
    setState(() => _busyChild = child.id);
    try {
      final updated = await widget.repository.setAuthorization(child.id, value);
      if (!mounted) return;
      setState(() {
        _children = _children
            .map((c) => c.id == updated.id ? updated : c)
            .toList(growable: false);
        _busyChild = null;
      });
      if (!value) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Autorisation retirée : ${child.firstName} ne peut plus réserver.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busyChild = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<Child>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddChildSheet(
        repository: widget.repository,
        schoolId: widget.schoolId,
      ),
    );
    if (created != null && mounted) {
      setState(() => _children = [..._children, created]);
    }
  }

  void _openJournal(Child child) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildJournalScreen(
          repository: widget.repository,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mes enfants')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Ajouter un élève'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
              children: [
                const Text(
                  'Un compte élève permet de réserver un trajet scolaire. '
                  'Vous gardez la main : sans votre autorisation, aucune place '
                  'ne peut être réservée pour votre enfant.',
                  style: TextStyle(fontSize: 13, color: MboaColors.mutedText),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: MboaColors.red)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Réessayer'),
                  ),
                ],
                if (_error == null && _children.isEmpty)
                  const Text(
                    'Aucun compte élève pour le moment.',
                    style: TextStyle(color: MboaColors.mutedText),
                  ),
                ..._children.map(
                  (child) => _ChildCard(
                    child: child,
                    busy: _busyChild == child.id,
                    onToggle: (value) => _toggle(child, value),
                    onOpenJournal: () => _openJournal(child),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.busy,
    required this.onToggle,
    required this.onOpenJournal,
  });

  final Child child;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenJournal;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: child.authorized ? MboaColors.green : MboaColors.border,
        width: child.authorized ? 1.5 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.firstName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MboaColors.night,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${child.age} ans · ${child.schoolLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: MboaColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(value: child.authorized, onChanged: onToggle),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          child.authorized
              ? 'Trajets autorisés. Vous recevez une notification au départ et '
                    'à l\'arrivée.'
              : 'Trajets suspendus. Aucune réservation possible pour cet élève.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: child.authorized ? MboaColors.green : MboaColors.red,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onOpenJournal,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Voir le journal des trajets'),
          ),
        ),
      ],
    ),
  );
}

class _AddChildSheet extends StatefulWidget {
  const _AddChildSheet({required this.repository, this.schoolId});

  final ChildrenRepository repository;

  /// Établissement rattaché au compte, quand le parent en a choisi un.
  final int? schoolId;

  @override
  State<_AddChildSheet> createState() => _AddChildSheetState();
}

class _AddChildSheetState extends State<_AddChildSheet> {
  final _firstName = TextEditingController();
  final _age = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = Child.validate(
      firstName: _firstName.text,
      ageText: _age.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final child = await widget.repository.addChild(
        firstName: _firstName.text.trim(),
        age: int.parse(_age.text.trim()),
        schoolId: widget.schoolId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(child);
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
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      18 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nouveau compte élève',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _firstName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Prénom de l\'élève',
            helperText: 'MboaRide n\'enregistre que le prénom et l\'âge déclaré',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _age,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Âge',
            helperText: 'De 12 à 17 ans',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: MboaColors.red),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Créer le compte'),
        ),
      ],
    ),
  );
}
