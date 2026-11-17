import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications du téléphone (barre d'état, écran verrouillé), en plus du bandeau dans
/// l'application : retard du conducteur, trajet annulé, course démarrée, fin de course...
///
/// Elles partent tant que l'application tourne, au premier plan ou en arrière-plan. Une
/// application complètement fermée ne reçoit rien : il faudra pour cela des notifications
/// poussées par le serveur (Firebase Cloud Messaging).
///
/// Sans support (tests, navigateur), tout devient sans effet.
class SystemNotifications {
  SystemNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'mboaride_trajets',
    'Trajets MboaRide',
    description: 'Retards, annulations, début et fin de course, paiements',
    importance: Importance.high,
  );

  /// À appeler une fois au démarrage : prépare le canal et demande l'autorisation
  /// d'afficher des notifications (Android 13 et plus).
  static Future<void> init() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();
      _ready = true;
    } on Object {
      _ready = false;
    }
  }

  static Future<void> show({required int id, required String title, required String body}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } on Object {
      // notification refusée par le système : le bandeau de l'application suffit
    }
  }
}
