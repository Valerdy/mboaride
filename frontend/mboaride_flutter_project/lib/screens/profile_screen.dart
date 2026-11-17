import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/auth_session.dart';
import '../services/auth_service.dart';
import 'driver_agreement_screen.dart';
import 'my_children_screen.dart';
import 'intercity_trip_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? initialCompany;
  final String identifier;

  const ProfileScreen({
    super.key,
    this.initialCompany,
    required this.identifier,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum UserRole { passager, conducteur, lesDeux }

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _fullNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _plateController = TextEditingController();

  UserRole _selectedRole = UserRole.conducteur;
  bool _isLoading = false;
  XFile? _pickedImage;

  static const Color primaryGreen = Color(0xFF0B6647);
  static const Color darkGreen = Color(0xFF074731);
  static const Color softGreen = Color(0xFFE6F2ED);
  static const Color bgBeige = Color(0xFFF6F5F0);

  @override
  void initState() {
    super.initState();
    if (widget.initialCompany != null) {
      _companyController.text = widget.initialCompany!;
    }
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _companyController.dispose();
    _vehicleModelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.getProfile();
    if (profile != null && mounted) {
      setState(() {
        if (profile['full_name'] != null) _fullNameController.text = profile['full_name'];
        if (profile['company'] != null && _companyController.text.isEmpty) {
          _companyController.text = profile['company'];
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    final success = await _authService.updateProfile({
      'full_name': _fullNameController.text,
      'company': _companyController.text,
      'role': _selectedRole.name,
      'vehicle_brand_model': _vehicleModelController.text,
      'vehicle_plate': _plateController.text,
    });
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Profil enregistré avec succès !' : 'Erreur lors de la sauvegarde'),
        backgroundColor: success ? primaryGreen : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentToken = AuthSession.accessToken ?? '';

    return Scaffold(
      backgroundColor: bgBeige,
      appBar: AppBar(
        title: const Text('Mon profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Photo de profil avec bouton d'ajout
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: _pickedImage != null
                        ? (kIsWeb
                        ? NetworkImage(_pickedImage!.path)
                        : FileImage(File(_pickedImage!.path)) as ImageProvider)
                        : null,
                    child: _pickedImage == null
                        ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.grey, size: 28),
                        SizedBox(height: 4),
                        Text('Ajouter photo', style: TextStyle(fontSize: 10, color: Colors.black54)),
                      ],
                    )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: primaryGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Champ Nom complet
            TextField(
              controller: _fullNameController,
              decoration: InputDecoration(
                labelText: 'Nom complet',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),

            // Champ Entreprise
            TextField(
              controller: _companyController,
              readOnly: false,
              decoration: InputDecoration(
                labelText: 'Nom de l\'entreprise',
                hintText: 'Entrez le nom de votre entreprise',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),

            // Sélection du rôle
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Je suis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Passager'),
                    selected: _selectedRole == UserRole.passager,
                    selectedColor: primaryGreen,
                    labelStyle: TextStyle(color: _selectedRole == UserRole.passager ? Colors.white : Colors.black),
                    onSelected: (selected) => setState(() => _selectedRole = UserRole.passager),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Conducteur'),
                    selected: _selectedRole == UserRole.conducteur,
                    selectedColor: primaryGreen,
                    labelStyle: TextStyle(color: _selectedRole == UserRole.conducteur ? Colors.white : Colors.black),
                    onSelected: (selected) => setState(() => _selectedRole = UserRole.conducteur),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Les deux'),
                    selected: _selectedRole == UserRole.lesDeux,
                    selectedColor: primaryGreen,
                    labelStyle: TextStyle(color: _selectedRole == UserRole.lesDeux ? Colors.white : Colors.black),
                    onSelected: (selected) => setState(() => _selectedRole = UserRole.lesDeux),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Détails du véhicule pour conducteurs
            if (_selectedRole != UserRole.passager) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Véhicule (conducteur)', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vehicleModelController,
                decoration: InputDecoration(
                  labelText: 'Marque et modèle',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _plateController,
                decoration: InputDecoration(
                  labelText: 'Plaque · Places libres : 3',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Bouton Enregistrer
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enregistrer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            // --- NOUVELLE SECTION : SERVICES & ACTIVITÉS MBOARIDE ---
            const SizedBox(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Services & Activités MboaRide',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkGreen),
              ),
            ),
            const SizedBox(height: 12),

            _buildServiceTile(
              icon: Icons.verified_user_rounded,
              title: 'Devenir conducteur',
              subtitle: 'Déposer vos documents et activer votre agrément',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverAgreementScreen(token: currentToken),
                ),
              ),
            ),
            const SizedBox(height: 10),

            _buildServiceTile(
              icon: Icons.school_rounded,
              title: 'Mes enfants (Trajets scolaires)',
              subtitle: 'Gérer les élèves autorisés et les alertes départ/arrivée',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MyChildrenScreen(token: currentToken),
                ),
              ),
            ),
            const SizedBox(height: 10),

            _buildServiceTile(
              icon: Icons.directions_car_filled_rounded,
              title: 'Voyage interurbain (Douala → Yaoundé)',
              subtitle: 'Publier ou gérer un trajet longue distance',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IntercityTripScreen(token: currentToken),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

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
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: softGreen,
                borderRadius: BorderRadius.circular(12),
              ),
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