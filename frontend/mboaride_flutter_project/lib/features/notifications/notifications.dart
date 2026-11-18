import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/mboa_theme.dart';
import '../../core/system_notifications.dart';

/// Notifications dans l'application : retard du conducteur, trajet annulé, course démarrée,
/// fin de course à valider, paiement reçu, gains versés au portefeuille...
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.read,
    this.createdAt,
  });

  final int id;
  final String type;
  final String message;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: (json['id_notification'] as num).toInt(),
    type: json['type'] as String? ?? '',
    message: json['message'] as String? ?? '',
    read: json['lue'] == true,
    createdAt: DateTime.tryParse(json['cree_le'] as String? ?? '')?.toLocal(),
  );

  IconData get icon => switch (type) {
    'retard' => Icons.schedule,
    'annulation' => Icons.event_busy,
    'reaffectation' || 'offres' => Icons.swap_horiz,
    'paiement' || 'remboursement' => Icons.payments_outlined,
    'versement' || 'portefeuille' => Icons.account_balance_wallet_outlined,
    'course' => Icons.directions_car,
    'fin_course' => Icons.flag_outlined,
    _ => Icons.notifications_none,
  };

  /// Une alerte qui demande d'agir vite (retard, annulation) : bandeau orange ou rouge.
  bool get urgent => type == 'retard' || type == 'annulation';

  /// Titre de la notification du téléphone.
  String get title => switch (type) {
    'retard' => 'Retard du conducteur',
    'annulation' => 'Trajet annulé',
    'reaffectation' => 'Nouveau conducteur',
    'offres' => 'Offres de trajet',
    'paiement' => 'Paiement',
    'remboursement' => 'Remboursement',
    'versement' || 'portefeuille' => 'Portefeuille',
    'course' => 'Course en cours',
    'fin_course' => 'Fin de course',
    _ => 'MboaRide',
  };
}

/// Durée d'affichage du bandeau dans l'application.
const Duration notificationBannerDuration = Duration(seconds: 5);

class NotificationSummary {
  const NotificationSummary({required this.unread, this.latest});

  final int unread;
  final AppNotification? latest;
}

abstract class NotificationsRepository {
  Future<NotificationSummary> summary();

  /// Les plus récentes ; les ouvrir les marque comme lues.
  Future<List<AppNotification>> list();
}

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<NotificationSummary> summary() async {
    final body = await _client.get('/api/moi/notifications/resume') as Map<String, dynamic>;
    final latest = body['derniere'] as Map<String, dynamic>?;
    return NotificationSummary(
      unread: (body['non_lues'] as num?)?.toInt() ?? 0,
      latest: latest == null ? null : AppNotification.fromJson(latest),
    );
  }

  @override
  Future<List<AppNotification>> list() async => [
    for (final n in (await _client.get('/api/moi/notifications?limite=50') as List<dynamic>))
      AppNotification.fromJson(n as Map<String, dynamic>),
  ];
}

class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository([List<AppNotification>? items])
    : items = items ??
          [
            AppNotification(
              id: 2,
              type: 'retard',
              message: 'Armand a 10 min de retard : prise en charge vers 07:08 à Kotto.',
              read: false,
              createdAt: DateTime(2026, 11, 17, 6, 50),
            ),
            AppNotification(
              id: 1,
              type: 'paiement',
              message: 'Paiement de 350 FCFA reçu : votre trajet du 17/11 avec Armand est confirmé.',
              read: true,
              createdAt: DateTime(2026, 11, 16, 20, 5),
            ),
          ];

  final List<AppNotification> items;

  @override
  Future<NotificationSummary> summary() async => NotificationSummary(
    unread: items.where((n) => !n.read).length,
    latest: items.firstOrNull,
  );

  @override
  Future<List<AppNotification>> list() async {
    final copy = List<AppNotification>.of(items);
    for (var i = 0; i < items.length; i++) {
      final n = items[i];
      items[i] = AppNotification(id: n.id, type: n.type, message: n.message, read: true, createdAt: n.createdAt);
    }
    return copy;
  }
}

/// Cloche avec le nombre de notifications non lues. Elle interroge l'API toutes les
/// [interval] et affiche un bandeau quand une nouvelle notification arrive (retard du
/// conducteur, trajet annulé, fin de course à valider...).
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.repository,
    this.interval = const Duration(seconds: 20),
    this.color,
  });

  final NotificationsRepository repository;
  final Duration interval;

  /// Couleur de l'icône ; par défaut celle de la barre de titre.
  final Color? color;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  Timer? _timer;
  int _unread = 0;
  int? _lastSeenId;
  bool _initialized = false;

  /// Notifications déjà annoncées : deux cloches ouvertes (accueil passager et espace
  /// conducteur) n'annoncent pas deux fois la même.
  static final Set<int> _announced = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.repository.summary();
      if (!mounted) return;
      final latest = s.latest;
      // Au premier relevé, on ne fait que noter la plus récente : seules les suivantes
      // sont annoncées.
      final isNew = _initialized && latest != null && !latest.read && latest.id != _lastSeenId;
      setState(() {
        _unread = s.unread;
        if (latest != null) _lastSeenId = latest.id;
        _initialized = true;
      });
      if (isNew && _announced.add(latest.id)) _announce(latest);
    } on ApiException {
      // hors ligne ou session expirée : la cloche reste telle quelle
    }
  }

  void _announce(AppNotification n) {
    // Notification du téléphone : visible aussi quand l'application est en arrière-plan.
    unawaited(SystemNotifications.show(id: n.id, title: n.title, body: n.message));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // Le bandeau se ferme seul après 5 s, même avec son bouton « Voir » (sans `persist`,
        // Flutter garde affiché un bandeau qui a une action).
        duration: notificationBannerDuration,
        persist: false,
        backgroundColor: n.urgent ? const Color(0xFFB8580B) : MboaColors.green,
        content: Row(
          children: [
            Icon(n.icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(n.message)),
          ],
        ),
        action: SnackBarAction(label: 'Voir', textColor: Colors.white, onPressed: _open),
      ),
    );
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationsScreen(repository: widget.repository)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _unread == 0 ? 'Notifications' : '$_unread notification(s) non lue(s)',
    onPressed: _open,
    icon: Badge(
      isLabelVisible: _unread > 0,
      label: Text('$_unread'),
      child: Icon(Icons.notifications_outlined, color: widget.color),
    ),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.repository});

  final NotificationsRepository repository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _items = widget.repository.list();

  static String _when(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} à ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: RefreshIndicator(
      onRefresh: () async {
        final next = widget.repository.list();
        setState(() => _items = next);
        await next;
      },
      child: FutureBuilder<List<AppNotification>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}'))]);
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Aucune notification. Vous serez prévenu ici d\'un retard, d\'une annulation '
                    'ou de la fin d\'une course.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MboaColors.mutedText),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: n.urgent ? const Color(0xFFFDE7D3) : MboaColors.greenSoft,
                  child: Icon(n.icon, color: n.urgent ? const Color(0xFFB8580B) : MboaColors.green),
                ),
                title: Text(
                  n.message,
                  style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(_when(n.createdAt)),
              );
            },
          );
        },
      ),
    ),
  );
}
