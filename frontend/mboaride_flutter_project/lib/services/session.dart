import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/auth_session.dart';
import '../core/mboa_theme.dart';
import '../core/session_store.dart';
import 'auth_service.dart';

/// Session de l'application, accessible de n'importe quel écran.
///
///  - Déconnexion rapide : un appui, la session locale est fermée et l'écran de connexion
///    s'affiche aussitôt ; la révocation du jeton chez l'API Node part en arrière-plan
///    (avant, l'écran attendait la réponse du serveur, jusqu'à 10 s hors connexion).
///  - Session gardée entre deux lancements (stockage chiffré), renouvelée par le jeton de
///    rafraîchissement quand le jeton d'accès a expiré.
///  - Session expirée en cours d'usage (réponse 401) : renouvellement, sinon retour à la
///    connexion avec un message, au lieu d'écrans en erreur.
class Session {
  Session._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Écrans de connexion et d'accueil, fournis par main.dart.
  static Widget Function()? loginScreen;
  static Widget Function()? homeScreen;

  static AuthService authService = AuthService();
  static bool _renewing = false;

  /// Au lancement : reprend la session enregistrée. true si l'utilisateur est connecté.
  static Future<bool> restore() async {
    if (!await SessionStore.load()) return false;
    try {
      if (AuthSession.accessToken != null) {
        AuthSession.profile = await authService.ensureProfile();
        return true;
      }
    } on Object {
      // jeton d'accès expiré : on tente le renouvellement
    }
    if (await authService.refreshSession()) return true;
    AuthSession.clear();
    await SessionStore.clear();
    return false;
  }

  /// Déconnexion immédiate, depuis n'importe quel écran.
  static void signOut({String? message}) {
    final refresh = AuthSession.refreshToken;
    AuthSession.clear();
    unawaited(SessionStore.clear());
    if (refresh != null) unawaited(authService.revoke(refresh));
    final nav = navigatorKey.currentState;
    final login = loginScreen;
    if (nav != null && login != null) {
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => login()), (_) => false);
    }
    if (message != null) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Appelé par [ApiClient] sur une réponse 401.
  static Future<void> onUnauthorized() async {
    if (_renewing || AuthSession.accessToken == null) return;
    _renewing = true;
    try {
      if (await authService.refreshSession()) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Session renouvelée : réessayez.')),
        );
      } else {
        signOut(message: 'Votre session a expiré, reconnectez-vous.');
      }
    } finally {
      _renewing = false;
    }
  }

  /// Demande confirmation, puis déconnecte.
  static Future<void> confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous devrez saisir à nouveau votre e-mail ou téléphone et votre mot de passe.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MboaColors.red, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) signOut();
  }
}

/// Bouton « Se déconnecter » à poser dans une barre d'application.
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Se déconnecter',
    icon: Icon(Icons.logout, color: color),
    onPressed: () => Session.confirmSignOut(context),
  );
}

/// Premier écran : reprend la session enregistrée, sinon ouvre la connexion.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  bool? _connected;

  @override
  void initState() {
    super.initState();
    Session.restore().then((ok) {
      if (mounted) setState(() => _connected = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    if (connected == null) {
      return const Scaffold(
        backgroundColor: MboaColors.green,
        body: Center(
          child: Text(
            'MboaRide',
            style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    final screen = connected ? Session.homeScreen : Session.loginScreen;
    return screen?.call() ?? const SizedBox.shrink();
  }
}

/// Branchement du client HTTP sur la session (appelé une fois dans main.dart).
void connectApiClientToSession() {
  ApiClient.onUnauthorized = Session.onUnauthorized;
}
