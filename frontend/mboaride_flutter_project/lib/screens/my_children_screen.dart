import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/children/child_ui.dart';
import '../features/children/children_api.dart';
import 'add_child_wizard_screen.dart';

class MyChildrenScreen extends StatefulWidget {
  final String token;
  const MyChildrenScreen({super.key, required this.token});

  @override
  State<MyChildrenScreen> createState() => _MyChildrenScreenState();
}

class _MyChildrenScreenState extends State<MyChildrenScreen> {
  late final ChildrenApi _api = ChildrenApi(widget.token);

  // L'écran s'affiche tout de suite : dernière liste connue, sinon squelette.
  late List<ChildProfile> _children = List.of(ChildrenApi.cache ?? const <ChildProfile>[]);
  late bool _loading = ChildrenApi.cache == null;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _api.list();
      if (!mounted) return;
      setState(() {
        _children = list;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is ChildrenApiException ? e.message : 'Une erreur est survenue.';
      setState(() {
        _loading = false;
        _error = _children.isEmpty ? msg : null;
      });
      if (_children.isNotEmpty) ChildUi.toast(context, msg);
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  void _setChildren(List<ChildProfile> list) {
    if (!mounted) return;
    setState(() => _children = list);
    ChildrenApi.cache = list;
  }

  Future<void> _openWizard() async {
    final created = await Navigator.of(context).push<ChildProfile>(
      PageRouteBuilder<ChildProfile>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => AddChildWizardScreen(token: widget.token),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                  .animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (created != null && mounted) {
      _setChildren([..._children, created]);
      HapticFeedback.mediumImpact();
      ChildUi.toast(context, 'Le profil de ${created.firstName} est créé.', ok: true);
    }
  }

  void _openSheet(ChildProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChildSheet(
        child: profile,
        api: _api,
        onChanged: (updated) => _setChildren(
          _children.map((c) => c.id == updated.id ? updated : c).toList(),
        ),
        onDeleted: (id) => _setChildren(_children.where((c) => c.id != id).toList()),
      ),
    );
  }

  String get _subtitle {
    if (_loading && _children.isEmpty) return 'Chargement de vos profils…';
    if (_children.isEmpty) return 'Des trajets sûrs, de la maison à l’école';
    final today = ChildRoute.dayCodes[DateTime.now().weekday - 1];
    final trips = _children
        .where((c) => !c.paused && c.route != null && c.route!.days.contains(today))
        .length;
    final kids = _children.length == 1 ? '1 enfant' : '${_children.length} enfants';
    final t = trips == 0
        ? 'aucun trajet aujourd’hui'
        : trips == 1
        ? '1 trajet aujourd’hui'
        : '$trips trajets aujourd’hui';
    return '$kids, $t';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChildUi.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openWizard,
        backgroundColor: ChildUi.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un enfant', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: ChildUi.green,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            _buildHeader(),
            ..._buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 168,
      backgroundColor: ChildUi.green,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 16),
        title: const Text(
          'Mes enfants',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B6647), Color(0xFF064A33)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 66),
          alignment: Alignment.bottomLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _subtitle,
              key: ValueKey(_subtitle),
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_loading && _children.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (_, __) => const _SkeletonCard(),
              childCount: 3,
            ),
          ),
        ),
      ];
    }
    if (_error != null && _children.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MessageState(
            icon: Icons.cloud_off_rounded,
            title: 'Impossible de charger vos enfants',
            message: _error!,
            actionLabel: 'Réessayer',
            onAction: _retry,
          ),
        ),
      ];
    }
    if (_children.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MessageState(
            icon: Icons.family_restroom_rounded,
            title: 'Ajoutez votre premier enfant',
            message:
            'Créez son profil en trois étapes : qui il est, son trajet, la personne à prévenir.',
            actionLabel: 'Ajouter un enfant',
            onAction: _openWizard,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
                (_, i) => _ChildCard(
              key: ValueKey(_children[i].id),
              profile: _children[i],
              onTap: () => _openSheet(_children[i]),
            ),
            childCount: _children.length,
          ),
        ),
      ),
    ];
  }
}

// ------------------------------------------------------------------ Carte enfant

({String label, Color color}) _statusOf(ChildProfile c) {
  if (!c.authorized) return (label: 'Suspendu', color: ChildUi.muted);
  if (c.paused) return (label: 'En pause', color: const Color(0xFFB98300));
  if (c.route == null) return (label: 'Sans trajet', color: ChildUi.muted);
  return (label: 'Actif', color: ChildUi.green);
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({super.key, required this.profile, required this.onTap});

  final ChildProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(profile);
    final route = profile.route;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: ChildUi.softShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChildAvatar(name: profile.firstName, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.firstName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: ChildUi.ink,
                              ),
                            ),
                            Text(
                              '${profile.age} ans',
                              style: const TextStyle(fontSize: 13, color: ChildUi.muted),
                            ),
                          ],
                        ),
                      ),
                      _StatusPill(label: status.label, color: status.color),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (route == null)
                    const Text(
                      'Aucun trajet défini pour le moment.',
                      style: TextStyle(fontSize: 13.5, color: ChildUi.muted),
                    )
                  else ...[
                    _RouteRibbon(route: route, dimmed: profile.paused),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.paused ? 'Trajets en pause' : 'Prochain départ',
                                style: const TextStyle(fontSize: 12.5, color: ChildUi.muted),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                profile.paused ? 'Reprise à votre demande' : route.nextLabel(),
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: profile.paused ? const Color(0xFFB98300) : ChildUi.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          route.daysLabel,
                          style: const TextStyle(fontSize: 12.5, color: ChildUi.muted),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: ChildUi.muted),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le trait entre la maison et l'école : l'élément visuel central de la carte.
class _RouteRibbon extends StatelessWidget {
  const _RouteRibbon({required this.route, required this.dimmed});

  final ChildRoute route;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? ChildUi.line : ChildUi.green;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: color.withAlpha(110),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                route.pickupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChildUi.ink),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                route.dropoffName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChildUi.ink),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ------------------------------------------------------------------ États vides / erreur / chargement

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ChildUi.softShadow,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseBox(height: 54, width: 54, radius: 27),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PulseBox(height: 16, width: 120),
                    SizedBox(height: 8),
                    PulseBox(height: 12, width: 60),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          PulseBox(height: 12),
          SizedBox(height: 18),
          PulseBox(height: 18, width: 160),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: ChildUi.green.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: ChildUi.green),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ChildUi.ink),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4, color: ChildUi.muted),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: ChildUi.green,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Fiche détaillée

class _ChildSheet extends StatefulWidget {
  const _ChildSheet({
    required this.child,
    required this.api,
    required this.onChanged,
    required this.onDeleted,
  });

  final ChildProfile child;
  final ChildrenApi api;
  final ValueChanged<ChildProfile> onChanged;
  final ValueChanged<String> onDeleted;

  @override
  State<_ChildSheet> createState() => _ChildSheetState();
}

class _ChildSheetState extends State<_ChildSheet> {
  late ChildProfile _c = widget.child;

  Future<void> _apply(Map<String, dynamic> patch, ChildProfile optimistic) async {
    final previous = _c;
    setState(() => _c = optimistic);
    widget.onChanged(optimistic);
    HapticFeedback.selectionClick();
    try {
      final saved = await widget.api.update(_c.id, patch);
      if (mounted) setState(() => _c = saved);
      widget.onChanged(saved);
    } catch (e) {
      if (mounted) setState(() => _c = previous);
      widget.onChanged(previous);
      if (mounted) {
        ChildUi.toast(context, e is ChildrenApiException ? e.message : 'Modification impossible.');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Supprimer le profil de ${_c.firstName} ?'),
        content: const Text('Son trajet et sa personne de confiance seront aussi supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete(_c.id);
      widget.onDeleted(_c.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ChildUi.toast(context, e is ChildrenApiException ? e.message : 'Suppression impossible.');
      }
    }
  }

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ChildUi.muted),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _alertTile(String label, String key) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      value: _c.alertPrefs[key] ?? true,
      onChanged: (v) {
        final prefs = Map<String, bool>.from(_c.alertPrefs)..[key] = v;
        _apply({'alertPrefs': prefs}, _c.copyWith(alertPrefs: prefs));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(_c);
    final route = _c.route;
    final scheme = Theme.of(context).colorScheme.copyWith(primary: ChildUi.green);

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: scheme),
      child: Container(
        decoration: const BoxDecoration(
          color: ChildUi.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChildUi.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  ChildAvatar(name: _c.firstName, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _c.firstName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: ChildUi.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('${_c.age} ans', style: const TextStyle(color: ChildUi.muted)),
                      ],
                    ),
                  ),
                  _StatusPill(label: status.label, color: status.color),
                ],
              ),
              _section(
                'Trajet scolaire',
                route == null
                    ? const Text('Aucun trajet défini.')
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RouteRibbon(route: route, dimmed: _c.paused),
                    const SizedBox(height: 12),
                    Text(
                      '${route.daysLabel}, départ à ${route.departTime}',
                      style: const TextStyle(fontSize: 14, color: ChildUi.ink),
                    ),
                  ],
                ),
              ),
              _section(
                'Personne de confiance',
                Text(
                  _c.contactName == null
                      ? 'Non renseignée'
                      : '${_c.contactName}  ${_c.contactPhone ?? ''}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
              _section(
                'Contrôle des trajets',
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Mettre les trajets en pause',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Vous pourrez les reprendre à tout moment.'),
                  value: _c.paused,
                  onChanged: (v) => _apply({'paused': v}, _c.copyWith(paused: v)),
                ),
              ),
              _section(
                'Me prévenir',
                Column(
                  children: [
                    _alertTile('Au départ', 'onDeparture'),
                    _alertTile('À l’arrivée', 'onArrival'),
                    _alertTile('En cas de retard', 'onDelay'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  label: const Text(
                    'Supprimer ce profil',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}