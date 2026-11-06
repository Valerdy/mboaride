import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialCompany != null) {
      _companyController.text = widget.initialCompany!;
    }
    _loadProfile();
  }

  // Sélection de l'image depuis la galerie ou l'appareil photo
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
    if (profile != null) {
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
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Profil enregistré avec succès !' : 'Erreur lors de la sauvegarde')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
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
                      decoration: BoxDecoration(
                        color: primaryColor,
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

            // Champ Entreprise (ÉDITABLE PAR L'UTILISATEUR)
            TextField(
              controller: _companyController,
              readOnly: false, // Modification autorisée
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
                    selectedColor: primaryColor,
                    labelStyle: TextStyle(color: _selectedRole == UserRole.passager ? Colors.white : Colors.black),
                    onSelected: (selected) => setState(() => _selectedRole = UserRole.passager),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Conducteur'),
                    selected: _selectedRole == UserRole.conducteur,
                    selectedColor: primaryColor,
                    labelStyle: TextStyle(color: _selectedRole == UserRole.conducteur ? Colors.white : Colors.black),
                    onSelected: (selected) => setState(() => _selectedRole = UserRole.conducteur),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Les deux'),
                    selected: _selectedRole == UserRole.lesDeux,
                    selectedColor: primaryColor,
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
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enregistrer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}