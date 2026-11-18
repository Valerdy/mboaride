import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_services.dart';
import '../features/driver/presentation/driver_shell.dart';
import '../services/auth_service.dart';
import 'request_ride_screen.dart';

/// Écran ouvert après la connexion : la demande de trajet (passager), ou directement
/// l'espace conducteur avec `--dart-define=START=driver` (téléphone du conducteur).
const String _afterLogin = String.fromEnvironment('START', defaultValue: 'ride');

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _authService = AuthService();

  // Contrôleurs Inscription
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // 6 contrôleurs et focus nodes pour les 6 cases du code OTP (comme sur la maquette)
  final List<TextEditingController> _otpCtrls =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  // Contrôleurs Connexion ("Déjà inscrit ? Se connecter")
  final _loginIdCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();

  bool _isLoginMode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptLocationSharing = false;
  String? _recognizedCompany;
  String _normalizedPhoneForVerify = '';

  // Couleurs exactes de votre maquette
  static const Color headerGreen = Color(0xFF0E6B4B);
  static const Color bgCream = Color(0xFFF3F2ED);
  static const Color borderGrey = Color(0xFFD5D4CE);
  static const Color textDark = Color(0xFF2B2D2C);
  static const Color textMuted = Color(0xFF6B6E6C);

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_detectCompanyFromEmail);
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_detectCompanyFromEmail);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _loginIdCtrl.dispose();
    _loginPassCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // Détection automatique du cercle d'entreprise à partir du domaine email
  void _detectCompanyFromEmail() {
    final email = _emailCtrl.text.trim();
    if (email.contains('@') && email.split('@').last.contains('.')) {
      final domain = email.split('@').last.split('.').first;
      const publicDomains = {'gmail', 'yahoo', 'hotmail', 'outlook', 'icloud'};
      if (domain.isNotEmpty && !publicDomains.contains(domain.toLowerCase())) {
        final formatted = domain[0].toUpperCase() + domain.substring(1);
        if (_recognizedCompany != formatted) {
          setState(() => _recognizedCompany = formatted);
        }
        return;
      }
    }
    if (_recognizedCompany != null) {
      setState(() => _recognizedCompany = null);
    }
  }

  String get _fullOtpCode => _otpCtrls.map((c) => c.text.trim()).join();

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : headerGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _navigateToRideRequest(String token) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _afterLogin == 'driver'
            ? DriverShell(
                repository: AppServices.driver,
                walletRepository: AppServices.payments,
                notifications: AppServices.notifications,
              )
            : RequestRideScreen(token: token),
      ),
    );
  }

  // Étape 1 : Bouton "Recevoir le code" -> crée le compte et envoie le SMS OTP
  Future<void> _handleReceiveCode() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.length < 8) {
      _showSnack(
        'Renseignez votre nom, email, téléphone et un mot de passe (8 caractères min.)',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.registerWithDetails(
        fullName: _nameCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        password: _passwordCtrl.text,
      );

      _normalizedPhoneForVerify =
          (result['phone'] as String?) ?? _phoneCtrl.text.trim();

      // Le serveur dit où le code est parti : « Code envoyé par e-mail à ka***@gmail.com ».
      final sentTo = (result['message'] as String?) ?? 'Code de vérification envoyé';
      final devCode = result['devOtp']?.toString();
      if (devCode != null && devCode.length == 6) {
        // Démonstration locale sans envoi configuré : le code est affiché ici.
        _showSnack('$sentTo (code de démonstration : $devCode)');
      } else {
        _showSnack(sentTo);
      }

      if (mounted) {
        _otpFocusNodes[0].requestFocus();
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Étape 2 : Bouton "Vérifier" -> valide l'OTP SMS + consentement GPS et ouvre la demande de trajet
  Future<void> _handleVerifyOtp() async {
    final code = _fullOtpCode;
    if (code.length != 6) {
      _showSnack('Veuillez saisir les 6 chiffres du code reçu par e-mail', isError: true);
      return;
    }
    if (!_acceptLocationSharing) {
      _showSnack('Veuillez accepter le partage de position pendant un trajet', isError: true);
      return;
    }

    final phoneToUse = _normalizedPhoneForVerify.isNotEmpty
        ? _normalizedPhoneForVerify
        : _phoneCtrl.text.trim();

    setState(() => _isLoading = true);
    try {
      final token = await _authService.verifySmsOtp(
        phone: phoneToUse,
        code: code,
      );
      if (!mounted) return;
      _navigateToRideRequest(token);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Connexion directe ("Déjà inscrit ? Se connecter")
  Future<void> _handleLogin() async {
    if (_loginIdCtrl.text.trim().isEmpty || _loginPassCtrl.text.isEmpty) {
      _showSnack('Veuillez saisir votre email/téléphone et votre mot de passe', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _authService.loginWithCredentials(
        identifier: _loginIdCtrl.text,
        password: _loginPassCtrl.text,
      );

      if (res['requiresOtp'] == true) {
        setState(() {
          _isLoginMode = false;
          _normalizedPhoneForVerify = res['phone'] as String;
          _phoneCtrl.text = _normalizedPhoneForVerify;
        });
        _showSnack('Compte non vérifié : un nouveau code vous a été envoyé par e-mail.');
        return;
      }

      final token = res['token'] as String;
      if (!mounted) return;
      _navigateToRideRequest(token);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: Column(
        children: [
          // En-tête vert fidèle à la maquette
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 52, bottom: 24, left: 22, right: 22),
            decoration: const BoxDecoration(
              color: headerGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Text(
              _isLoginMode ? 'Se connecter' : 'Créer mon compte',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: _isLoginMode ? _buildLoginBody() : _buildRegisterBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informations personnelles & professionnelles',
          style: TextStyle(fontSize: 12.5, color: textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),

        // 1. Champ ajouté : Nom complet
        _buildWhiteField(
          controller: _nameCtrl,
          hintText: 'Nom complet (ex: Jean Dupont)',
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 10),

        // 2. Champ maquette : Email professionnel
        _buildWhiteField(
          controller: _emailCtrl,
          hintText: 'prenom.nom@entreprise.cm',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 10),

        // 3. Champ maquette : Numéro de téléphone (+237)
        _buildWhiteField(
          controller: _phoneCtrl,
          hintText: '+237 6 •• •• •• ••',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 10),

        // 4. Champ ajouté : Mot de passe
        _buildWhiteField(
          controller: _passwordCtrl,
          hintText: 'Mot de passe (8 caractères min.)',
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 14),

        // Bouton "Recevoir le code" (fidèle à la maquette)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleReceiveCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: headerGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Text(
              'Recevoir le code',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Libellé OTP maquette
        const Text(
          'Code à 6 chiffres reçu par SMS ou email',
          style: TextStyle(fontSize: 12.5, color: textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),

        // Les 6 cases OTP carrées arrondies de la maquette
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) => _buildOtpDigitBox(index)),
        ),

        const SizedBox(height: 14),

        // Encadré "Domaine reconnu" de la maquette
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGrey),
          ),
          child: Text(
            _recognizedCompany != null
                ? 'Domaine reconnu : vous rejoignez automatiquement le cercle de $_recognizedCompany'
                : 'Domaine reconnu : vous rejoignez automatiquement le cercle de [Entreprise]',
            style: const TextStyle(fontSize: 12.5, color: textDark, height: 1.35),
          ),
        ),

        const SizedBox(height: 12),

        // Case à cocher "J'accepte le partage de ma position pendant un trajet"
        InkWell(
          onTap: () => setState(() => _acceptLocationSharing = !_acceptLocationSharing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _acceptLocationSharing,
                  activeColor: headerGreen,
                  side: const BorderSide(color: textMuted, width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) => setState(() => _acceptLocationSharing = val ?? false),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "J'accepte le partage de ma position pendant un trajet",
                  style: TextStyle(fontSize: 12, color: textDark),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Bouton "Vérifier" (fidèle à la maquette)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleVerifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: headerGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Vérifier',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Lien "Déjà inscrit ? Se connecter" en bas à gauche comme sur la maquette
        GestureDetector(
          onTap: () => setState(() => _isLoginMode = true),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Déjà inscrit ? Se connecter',
              style: TextStyle(
                fontSize: 12.5,
                color: textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email professionnel ou numéro de téléphone',
          style: TextStyle(fontSize: 12.5, color: textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        _buildWhiteField(
          controller: _loginIdCtrl,
          hintText: 'prenom.nom@entreprise.cm ou +237 6...',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildWhiteField(
          controller: _loginPassCtrl,
          hintText: 'Votre mot de passe',
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: textMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: headerGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Text(
              'Se connecter',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _isLoginMode = false),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Pas encore de compte ? Créer mon compte',
              style: TextStyle(
                fontSize: 12.5,
                color: textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhiteField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(fontSize: 14, color: textDark),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: textMuted, fontSize: 13.5),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: headerGreen, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildOtpDigitBox(int index) {
    return SizedBox(
      width: 46,
      height: 50,
      child: TextField(
        controller: _otpCtrls[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: '•',
          hintStyle: const TextStyle(color: textDark, fontSize: 18),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderGrey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: headerGreen, width: 1.5),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }
}