import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';
import '../services/auth_service.dart';
import 'request_ride_screen.dart';
import '../core/auth_session.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  String _phoneNumber = '';
  bool _isPhoneSelected = false;
  bool _positionAccepted = false;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _detectedCompany;
  String? _savedToken; // Stocke le token si renvoyé dès l'étape register

  void _checkEmailDomain(String email) {
    if (email.contains('@')) {
      final domain = email.split('@').last;
      if (domain == 'entreprise.cm') {
        setState(() {
          _detectedCompany = 'Entreprise';
        });
        return;
      }
    }
    setState(() {
      _detectedCompany = null;
    });
  }

  String get _currentIdentifier =>
      _isPhoneSelected ? _phoneNumber : _emailController.text.trim();

  Future<void> _handleSendCode() async {
    if (_currentIdentifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un email ou numéro valide')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final res = await _authService.register(
      identifier: _currentIdentifier,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : "Motdepasse123",
      fullName: "Utilisateur",
    );
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (res['statusCode'] == 201 || res['statusCode'] == 200 || res['statusCode'] == 409) {
      // Sauvegarde du token s'il est déjà présent dans la réponse de register
      final body = res['body'];
      if (body is Map) {
        _savedToken = body['token'] ?? body['access_token'];
      }

      setState(() => _otpSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code OTP envoyé !')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['body']['error'] ?? res['body']['detail'] ?? 'Erreur lors de l’envoi')),
      );
    }
  }

  Future<void> _handleVerify() async {
    if (_otpController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer le code à 6 chiffres')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final res = await _authService.verifyOtp(
      identifier: _currentIdentifier,
      code: _otpController.text.trim(),
    );
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (res['statusCode'] == 200 || res['statusCode'] == 201) {
      // Récupération du token JWT depuis la réponse verifyOtp (ou fallback sur _savedToken)
      final body = res['body'];
      final String token = (body is Map ? (body['token'] ?? body['access_token']) : null) ?? _savedToken ?? '';

      AuthSession.accessToken = token.isEmpty ? null : token;

      // Redirection directe vers la page RequestRideScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RequestRideScreen(token: token),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['body']['error'] ?? res['body']['detail'] ?? 'Code OTP invalide')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer mon compte', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            // Champ Email professionnel
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: (val) {
                _checkEmailDomain(val);
                if (val.isNotEmpty) setState(() => _isPhoneSelected = false);
              },
              decoration: InputDecoration(
                labelText: 'Email professionnel ou téléphone',
                hintText: 'prenom.nom@entreprise.cm',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            // Champ Téléphone +237
            IntlPhoneField(
              initialCountryCode: 'CM',
              decoration: InputDecoration(
                labelText: 'Numéro de téléphone',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (phone) {
                _phoneNumber = phone.completeNumber;
                if (_phoneNumber.isNotEmpty) setState(() => _isPhoneSelected = true);
              },
            ),
            const SizedBox(height: 12),

            // Bouton Recevoir le code
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSendCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Recevoir le code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),

            const Text('Code à 6 chiffres reçu par SMS ou email', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),

            // Cases pour Code à 6 chiffres
            Pinput(
              length: 6,
              controller: _otpController,
              defaultPinTheme: PinTheme(
                width: 45,
                height: 50,
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Encadré Domaine reconnu
            if (_detectedCompany != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Domaine reconnu : vous rejoignez automatiquement le cercle de [$_detectedCompany]',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            const SizedBox(height: 16),

            // Checkbox position
            Row(
              children: [
                Checkbox(
                  value: _positionAccepted,
                  activeColor: primaryColor,
                  onChanged: (val) => setState(() => _positionAccepted = val ?? false),
                ),
                const Expanded(
                  child: Text(
                    "J'accepte le partage de ma position pendant un trajet",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Bouton Vérifier
            ElevatedButton(
              onPressed: _isLoading ? null : _handleVerify,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              child: const Text('Vérifier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),

            // Lien connexion
            Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('Déjà inscrit ? Se connecter', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}