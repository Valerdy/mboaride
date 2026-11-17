import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/children/child_ui.dart';
import '../features/children/children_api.dart';

/// Assistant en 3 étapes. Se ferme avec le [ChildProfile] créé (ou null si abandonné).
class AddChildWizardScreen extends StatefulWidget {
  const AddChildWizardScreen({super.key, required this.token});

  final String token;

  @override
  State<AddChildWizardScreen> createState() => _AddChildWizardScreenState();
}

class _AddChildWizardScreenState extends State<AddChildWizardScreen> {
  static const _titles = ['Qui voyage ?', 'Quel trajet ?', 'Qui prévenir ?'];

  late final ChildrenApi _api = ChildrenApi(widget.token);
  final PageController _pages = PageController();
  int _step = 0;
  bool _saving = false;

  // Étape 1
  final _nameCtrl = TextEditingController();
  int _age = 13;

  // Étape 2
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final Set<String> _days = {'mon', 'tue', 'wed', 'thu', 'fri'};
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);

  // Étape 3
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  bool _consent = false;

  String? _nameError;
  String? _pickupError;
  String? _dropoffError;
  String? _daysError;
  String? _contactNameError;
  String? _contactPhoneError;
  String? _consentError;

  @override
  void dispose() {
    _pages.dispose();
    _nameCtrl.dispose();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  String get _timeLabel =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------ Navigation

  bool _validate(int step) {
    var ok = true;
    setState(() {
      if (step == 0) {
        _nameError = _nameCtrl.text.trim().length < 2 ? 'Indiquez le prénom de votre enfant' : null;
        ok = _nameError == null;
      } else if (step == 1) {
        _pickupError = _pickupCtrl.text.trim().length < 2 ? 'Indiquez le point de départ' : null;
        _dropoffError = _dropoffCtrl.text.trim().length < 2 ? 'Indiquez l’école' : null;
        _daysError = _days.isEmpty ? 'Choisissez au moins un jour' : null;
        ok = _pickupError == null && _dropoffError == null && _daysError == null;
      } else {
        _contactNameError =
        _contactNameCtrl.text.trim().length < 2 ? 'Indiquez le nom de cette personne' : null;
        _contactPhoneError = RegExp(r'^\+?[0-9 ]{8,15}$').hasMatch(_contactPhoneCtrl.text.trim())
            ? null
            : 'Numéro invalide (ex. 6 99 00 11 22)';
        _consentError = _consent ? null : 'Votre accord est nécessaire pour continuer';
        ok = _contactNameError == null && _contactPhoneError == null && _consentError == null;
      }
    });
    return ok;
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(
      step,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_saving) return;
    if (!_validate(_step)) {
      HapticFeedback.lightImpact();
      return;
    }
    if (_step < 2) {
      _goTo(_step + 1);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_saving || _step == 0) return;
    _goTo(_step - 1);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final created = await _api.create(
        firstName: _nameCtrl.text.trim(),
        age: _age,
        route: ChildRoute(
          pickupName: _pickupCtrl.text.trim(),
          dropoffName: _dropoffCtrl.text.trim(),
          days: ChildRoute.dayCodes.where(_days.contains).toList(),
          departTime: _timeLabel,
        ),
        contactName: _contactNameCtrl.text.trim(),
        contactPhone: _contactPhoneCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ChildUi.toast(context, e is ChildrenApiException ? e.message : 'Création impossible.');
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: ChildUi.green),
          ),
          child: child!,
        ),
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  // ------------------------------------------------------------ Build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: ChildUi.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTop(),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_stepIdentity(), _stepRoute(), _stepSafety()],
                ),
              ),
              _buildBottom(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: ChildUi.ink),
                tooltip: 'Fermer',
              ),
              Text(
                'Étape ${_step + 1} sur 3',
                style: const TextStyle(fontSize: 13.5, color: ChildUi.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: (_step + 1) / 3),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: ChildUi.line,
                      valueColor: const AlwaysStoppedAnimation(ChildUi.green),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _titles[_step],
                    key: ValueKey(_step),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: ChildUi.ink,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom() {
    final last = _step == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          if (_step > 0) ...[
            TextButton(
              onPressed: _saving ? null : _back,
              style: TextButton.styleFrom(
                foregroundColor: ChildUi.green,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              ),
              child: const Text('Retour', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _next,
                style: FilledButton.styleFrom(
                  backgroundColor: ChildUi.green,
                  disabledBackgroundColor: ChildUi.green.withAlpha(120),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _saving
                      ? const SizedBox(
                    key: ValueKey('saving'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                      : Text(
                    last ? 'Créer le profil' : 'Continuer',
                    key: ValueKey(last),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Étapes

  Widget _stepScroll(List<Widget> children) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _stepIdentity() {
    return _stepScroll([
      Center(child: ChildAvatar(name: _nameCtrl.text, size: 96)),
      const SizedBox(height: 26),
      _field(
        controller: _nameCtrl,
        label: 'Prénom',
        icon: Icons.person_rounded,
        error: _nameError,
        capitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _nameError = null),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.cake_rounded, color: ChildUi.green),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Âge', style: TextStyle(fontSize: 16, color: ChildUi.muted)),
            ),
            IconButton(
              onPressed: _age > 12
                  ? () {
                HapticFeedback.selectionClick();
                setState(() => _age--);
              }
                  : null,
              icon: const Icon(Icons.remove_circle_rounded),
              color: ChildUi.green,
            ),
            SizedBox(
              width: 70,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Text(
                  '$_age ans',
                  key: ValueKey(_age),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ChildUi.ink),
                ),
              ),
            ),
            IconButton(
              onPressed: _age < 25
                  ? () {
                HapticFeedback.selectionClick();
                setState(() => _age++);
              }
                  : null,
              icon: const Icon(Icons.add_circle_rounded),
              color: ChildUi.green,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _note('Le service est réservé aux élèves de 12 ans et plus, voyageant sans accompagnateur avec un conducteur agréé.'),
    ]);
  }

  Widget _stepRoute() {
    return _stepScroll([
      _field(
        controller: _pickupCtrl,
        label: 'Départ (maison)',
        icon: Icons.home_rounded,
        error: _pickupError,
        capitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() => _pickupError = null),
      ),
      const SizedBox(height: 12),
      _field(
        controller: _dropoffCtrl,
        label: 'Arrivée (école)',
        icon: Icons.school_rounded,
        error: _dropoffError,
        capitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() => _dropoffError = null),
      ),
      const SizedBox(height: 24),
      const Text(
        'Jours de trajet',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ChildUi.ink),
      ),
      const SizedBox(height: 10),
      Row(
        children: ChildRoute.dayCodes
            .map((c) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _dayPill(c),
          ),
        ))
            .toList(),
      ),
      if (_daysError != null) ...[
        const SizedBox(height: 8),
        Text(_daysError!, style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
      ],
      const SizedBox(height: 24),
      InkWell(
        onTap: _pickTime,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: ChildUi.green),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Heure de départ', style: TextStyle(fontSize: 16, color: ChildUi.muted)),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: Text(
                  _timeLabel,
                  key: ValueKey(_timeLabel),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ChildUi.ink),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded, size: 18, color: ChildUi.muted),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _stepSafety() {
    final name = _nameCtrl.text.trim();
    final pickup = _pickupCtrl.text.trim();
    final dropoff = _dropoffCtrl.text.trim();
    final daysText = ChildRoute(
      pickupName: pickup,
      dropoffName: dropoff,
      days: ChildRoute.dayCodes.where(_days.contains).toList(),
      departTime: _timeLabel,
    ).daysLabel;

    return _stepScroll([
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ChildUi.green.withAlpha(22),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ChildAvatar(name: name, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name, $_age ans',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ChildUi.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$pickup vers $dropoff\n$daysText, départ à $_timeLabel',
                    style: const TextStyle(fontSize: 13, height: 1.35, color: ChildUi.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        'Personne de confiance',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ChildUi.ink),
      ),
      const SizedBox(height: 4),
      const Text(
        'Nous la contactons si vous ne répondez pas à une alerte.',
        style: TextStyle(fontSize: 13.5, color: ChildUi.muted),
      ),
      const SizedBox(height: 12),
      _field(
        controller: _contactNameCtrl,
        label: 'Nom',
        icon: Icons.person_outline_rounded,
        error: _contactNameError,
        capitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _contactNameError = null),
      ),
      const SizedBox(height: 12),
      _field(
        controller: _contactPhoneCtrl,
        label: 'Téléphone',
        icon: Icons.call_rounded,
        error: _contactPhoneError,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() => _contactPhoneError = null),
      ),
      const SizedBox(height: 20),
      _consentTile(),
    ]);
  }

  // ------------------------------------------------------------ Éléments

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? error,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    OutlineInputBorder border(Color color, [double width = 0]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ChildUi.ink),
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        prefixIcon: Icon(icon, color: ChildUi.green),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(ChildUi.green, 1.6),
        errorBorder: border(Colors.red.shade300, 1.4),
        focusedErrorBorder: border(Colors.red.shade400, 1.6),
      ),
    );
  }

  Widget _dayPill(String code) {
    final on = _days.contains(code);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (on) {
            _days.remove(code);
          } else {
            _days.add(code);
          }
          _daysError = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? ChildUi.green : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? ChildUi.green : ChildUi.line),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : ChildUi.ink,
          ),
          child: Text(ChildRoute.dayShort[code]!),
        ),
      ),
    );
  }

  Widget _consentTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _consent = !_consent;
          _consentError = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _consentError != null
                ? Colors.red.shade300
                : _consent
                ? ChildUi.green
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _consent ? ChildUi.green : Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: _consent ? ChildUi.green : ChildUi.line, width: 2),
                  ),
                  child: _consent
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'J’exerce l’autorité parentale sur cet enfant et j’autorise ses trajets sans accompagnateur avec un conducteur agréé.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: ChildUi.ink),
                  ),
                ),
              ],
            ),
            if (_consentError != null) ...[
              const SizedBox(height: 8),
              Text(_consentError!, style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _note(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChildUi.amber.withAlpha(46),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: ChildUi.ink),
      ),
    );
  }
}