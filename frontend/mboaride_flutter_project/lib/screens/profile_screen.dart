import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_services.dart';
import '../features/children/presentation/children_screen.dart';
import '../features/driver/presentation/driver_shell.dart';
import '../features/driver/presentation/vehicle_screen.dart';
import '../features/intercity/presentation/intercity_screen.dart';
import '../features/payment/presentation/my_trips_screen.dart';
import '../features/notifications/notifications.dart';
import '../features/preferences/presentation/preferences_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../services/auth_service.dart';
import '../services/session.dart';

/// Mon profil : identité et cercle (profil métier de l'API Python, créé à l'inscription),
/// puis les services. Le véhicule et l'agrément se gèrent dans l'espace conducteur.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  XFile? _pickedImage;

  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color darkGreen = Color(0xFF074731);
  static const Color softGreen = Color(0xFFE6F2ED);
  static const Color bgBeige = Color(0xFFF6F5F0);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) setState(() => _pickedImage = image);
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// Déconnexion immédiate (la révocation du jeton part en arrière-plan).
  void _signOut() => Session.confirmSignOut(context);

  String get _driverStatus => switch (_profile?['statut_agrement']) {
    'actif' => 'Agrément validé',
    'en_verification' => 'Agrément en vérification',
    'suspendu' => 'Agrément suspendu',
    _ => 'Pas encore conducteur',
  };

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final organisations = (p?['organisations'] as List<dynamic>? ?? const [])
        .map((o) => (o as Map<String, dynamic>)['nom'] as String)
        .toList();
    return Scaffold(
      backgroundColor: bgBeige,
      appBar: AppBar(
        title: const Text('Mon profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: _pickedImage == null
                          ? null
                          : (kIsWeb
                                ? NetworkImage(_pickedImage!.path)
                                : FileImage(File(_pickedImage!.path)) as ImageProvider),
                      child: _pickedImage == null
                          ? const Icon(Icons.camera_alt, color: Colors.grey, size: 28)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    p == null ? 'Profil indisponible' : '${p['prenom']} ${p['nom']}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkGreen),
                  ),
                  const SizedBox(height: 16),
                  if (p != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _info(Icons.mail_outline, p['email'] as String? ?? '—'),
                          _info(Icons.phone_outlined, p['telephone'] as String? ?? '—'),
                          _info(
                            Icons.groups_outlined,
                            organisations.isEmpty
                                ? 'Aucune organisation : réseau public'
                                : 'Cercle de confiance : ${organisations.join(', ')}',
                          ),
                          _info(Icons.verified_user_outlined, _driverStatus),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Services & activités MboaRide',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkGreen),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildServiceTile(
                    icon: Icons.event_seat_rounded,
                    title: 'Mes trajets',
                    subtitle: 'Trajets à confirmer (paiement) et trajets confirmés',
                    onTap: () => _open(MyTripsScreen(repository: AppServices.payments)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Mon portefeuille',
                    subtitle: 'Solde, recharge Mobile Money, gains de conducteur',
                    onTap: () => _open(WalletScreen(repository: AppServices.payments)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                    subtitle: 'Retards, annulations, fin de course, paiements',
                    onTap: () => _open(NotificationsScreen(repository: AppServices.notifications)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.drive_eta_rounded,
                    title: 'Espace conducteur',
                    subtitle: 'Agrément, véhicule, trajets publiés et équipage du jour',
                    onTap: () => _open(DriverShell(
                      repository: AppServices.driver,
                      walletRepository: AppServices.payments,
                      notifications: AppServices.notifications,
                    )),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.directions_car_filled_rounded,
                    title: 'Mon véhicule',
                    subtitle: 'Places, consommation et confort',
                    onTap: () => _open(VehicleScreen(repository: AppServices.driver)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.tune_rounded,
                    title: 'Mes exigences de confort',
                    subtitle: 'Climatisation, prix maximal, cercle accepté',
                    onTap: () => _open(PreferencesScreen(repository: AppServices.preferences)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.school_rounded,
                    title: 'Mes enfants (trajets scolaires)',
                    subtitle: 'Élèves autorisés et alertes départ et arrivée',
                    onTap: () => _open(ChildrenScreen(repository: AppServices.children)),
                  ),
                  const SizedBox(height: 10),
                  _buildServiceTile(
                    icon: Icons.route_rounded,
                    title: 'Voyage interurbain (Douala → Yaoundé)',
                    subtitle: 'Réserver une place à l\'avance',
                    onTap: () => _open(IntercityScreen(repository: AppServices.intercity)),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: primaryGreen),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );

  Widget _buildServiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: primaryGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: primaryGreen),
          ],
        ),
      ),
    );
  }
}
