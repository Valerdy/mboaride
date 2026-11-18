import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import '../../core/mboa_theme.dart';
import '../payment/data/payment_repository.dart';
import '../payment/domain/payment.dart';

/// Portefeuille MboaRide, pour le passager comme pour le conducteur.
///
/// Passager : il le recharge depuis Mobile Money et paie ses trajets avec ; l'argent d'un
/// trajet reste chez MboaRide jusqu'à la fin de la course. Conducteur : il y reçoit le prix
/// de chaque place moins la commission de 10 %, quand tout l'équipage a validé la fin de la
/// course, et le vire vers son compte Mobile Money (à la main ou automatiquement).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.repository, this.driver = false});

  final PaymentRepository repository;

  /// Vue conducteur : gains en attente, commission et virement automatique en avant.
  final bool driver;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Wallet? _wallet;
  List<MobileMoneyAccount> _accounts = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final wallet = await widget.repository.wallet();
      final accounts = await widget.repository.accounts();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _accounts = accounts;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<Wallet> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      final wallet = await action();
      if (!mounted) return;
      setState(() => _wallet = wallet);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<MobileMoneyAccount?> _ensureAccount() async {
    if (_accounts.isNotEmpty) return _accounts.first;
    final account = await showDialog<MobileMoneyAccount>(
      context: context,
      builder: (_) => _AccountDialog(repository: widget.repository),
    );
    if (account != null) await _load();
    return account;
  }

  Future<void> _topUp() async {
    final account = await _ensureAccount();
    if (account == null || !mounted) return;
    final request = await showDialog<(MobileMoneyAccount, int, String)>(
      context: context,
      builder: (_) => _TopUpDialog(accounts: _accounts.isEmpty ? [account] : _accounts),
    );
    if (request == null) return;
    final (from, amount, pin) = request;
    await _run(
      () => widget.repository.topUpWallet(accountId: from.id, amountFcfa: amount, pin: pin),
      'Portefeuille rechargé de $amount FCFA.',
    );
  }

  Future<void> _withdraw() async {
    final wallet = _wallet;
    if (wallet == null) return;
    final account = await _ensureAccount();
    if (account == null || !mounted) return;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: 'Virer vers ${account.operator.label}',
        hint: 'Vers ${account.displayPhone} · solde ${wallet.balanceFcfa} FCFA',
        initial: wallet.balanceFcfa,
        max: wallet.balanceFcfa,
        action: 'Virer',
      ),
    );
    if (amount == null) return;
    await _run(
      () => widget.repository.withdrawFromWallet(amountFcfa: amount, accountId: account.id),
      '$amount FCFA virés vers ${account.operator.label}.',
    );
  }

  Future<void> _toggleAuto(bool enabled) async {
    if (enabled && await _ensureAccount() == null) return;
    await _run(
      () => widget.repository.setAutoTransfer(enabled),
      enabled
          ? 'Vos gains partiront automatiquement vers votre compte Mobile Money.'
          : 'Vos gains restent dans votre portefeuille.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon portefeuille')),
      body: w == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _balanceCard(w),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: _busy ? null : _topUp,
                          icon: const Icon(Icons.add),
                          label: const Text('Recharger'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: _busy || w.balanceFcfa < 100 ? null : _withdraw,
                          icon: const Icon(Icons.call_made),
                          label: const Text('Virer'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (widget.driver || w.pendingEarningsFcfa > 0) _driverCard(w),
                  if (w.escrowFcfa > 0) ...[
                    const SizedBox(height: 10),
                    _info(
                      Icons.lock_clock_outlined,
                      '${w.escrowFcfa} FCFA de trajets payés sont gardés par MboaRide : ils iront à vos '
                      'conducteurs quand vous aurez validé la fin de chaque course.',
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('Relevé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (w.movements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Aucun mouvement pour l\'instant.', style: TextStyle(color: MboaColors.mutedText)),
                    )
                  else
                    for (final m in w.movements) _movement(m),
                ],
              ),
            ),
    );
  }

  Widget _balanceCard(Wallet w) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: MboaDecor.brandGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Solde disponible', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              '${w.balanceFcfa} FCFA',
              key: const ValueKey('solde-portefeuille'),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
            ),
            if (w.defaultAccount != null)
              Text(
                'Compte lié : ${w.defaultAccount!.operator.label} ${w.defaultAccount!.displayPhone}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
          ],
        ),
      );

  /// Surface Material : l'interrupteur garde son effet au toucher.
  Widget _driverCard(Wallet w) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: MboaColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _driverCardContent(w),
        ),
      );

  Widget _driverCardContent(Wallet w) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mes gains de conducteur', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            w.pendingEarningsFcfa > 0
                ? '${w.pendingEarningsFcfa} FCFA en attente (${w.pendingPassengers} passager(s) payé(s)) : '
                    'versés dès que tout l\'équipage aura validé la fin de la course.'
                : 'Aucun gain en attente.',
            style: const TextStyle(color: MboaColors.mutedText),
          ),
          if (w.commissionFcfa > 0)
            Text(
              'Commission MboaRide (10 %) prélevée sur vos courses : ${w.commissionFcfa} FCFA.',
              style: const TextStyle(color: MboaColors.mutedText, fontSize: 12.5),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: w.autoTransfer,
            onChanged: _busy ? null : _toggleAuto,
            title: const Text('Virement automatique vers Mobile Money'),
            subtitle: const Text('Chaque gain part aussitôt vers votre compte, sans rester dans l\'application.'),
          ),
        ],
      );

  Widget _info(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MboaColors.greenSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MboaColors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _movement(WalletMovement m) {
    final credit = m.amountFcfa > 0;
    final icon = switch (m.type) {
      WalletMovementType.topUp => Icons.add_circle_outline,
      WalletMovementType.payment => Icons.directions_car_outlined,
      WalletMovementType.refund => Icons.undo,
      WalletMovementType.earning => Icons.savings_outlined,
      WalletMovementType.withdrawal => Icons.call_made,
    };
    String two(int n) => n.toString().padLeft(2, '0');
    final d = m.createdAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: credit ? MboaColors.greenSoft : MboaColors.neutralSoft,
        child: Icon(icon, color: credit ? MboaColors.green : MboaColors.mutedText),
      ),
      title: Text(m.label, style: const TextStyle(fontSize: 14)),
      subtitle: Text([
        if (d != null) '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}',
        if (m.reference != null) 'réf. ${m.reference}',
        'solde ${m.balanceAfterFcfa} FCFA',
      ].join(' · ')),
      trailing: Text(
        '${credit ? '+' : ''}${m.amountFcfa} FCFA',
        style: TextStyle(fontWeight: FontWeight.w700, color: credit ? MboaColors.green : MboaColors.night),
      ),
    );
  }
}

/// Recharge : compte, montant et code secret (fictif, jamais enregistré).
class _TopUpDialog extends StatefulWidget {
  const _TopUpDialog({required this.accounts});

  final List<MobileMoneyAccount> accounts;

  @override
  State<_TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<_TopUpDialog> {
  late MobileMoneyAccount _account = widget.accounts.first;
  final _amount = TextEditingController(text: '2000');
  final _pin = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _pin.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_amount.text.trim());

  @override
  Widget build(BuildContext context) {
    final ok = (_value ?? 0) >= 100 && _pin.text.length >= 4;
    return AlertDialog(
      title: const Text('Recharger le portefeuille'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _account.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Depuis'),
              items: [
                for (final a in widget.accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.operator.label} ${a.displayPhone}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _account = widget.accounts.firstWhere((a) => a.id == id)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final v in const [500, 1000, 2000, 5000])
                  ChoiceChip(
                    label: Text('$v'),
                    selected: _value == v,
                    onSelected: (_) => setState(() => _amount.text = '$v'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 5,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Code secret ${_account.operator.label}', counterText: ''),
            ),
            const Text(
              'Recharge fictive : aucun montant n\'est débité, le code n\'est pas enregistré.',
              style: TextStyle(fontSize: 12, color: MboaColors.mutedText),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: ok ? () => Navigator.pop(context, (_account, _value!, _pin.text)) : null,
          child: const Text('Recharger'),
        ),
      ],
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog(
      {required this.title, required this.hint, required this.initial, required this.max, required this.action});

  final String title;
  final String hint;
  final int initial;
  final int max;
  final String action;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _amount = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_amount.text.trim()) ?? 0;
    final ok = value >= 100 && value <= widget.max;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.hint, style: const TextStyle(color: MboaColors.mutedText)),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: ok ? () => Navigator.pop(context, value) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Premier compte Mobile Money : opérateur, numéro, titulaire.
class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.repository});

  final PaymentRepository repository;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  MobileMoneyOperator _operator = MobileMoneyOperator.mtn;
  final _phone = TextEditingController();
  late final _holder = TextEditingController(
    text: [AuthSession.profile?['prenom'], AuthSession.profile?['nom']].whereType<String>().join(' '),
  );
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = _operator.checkNumber(_phone.text);
    if (error != null || _holder.text.trim().length < 2) {
      setState(() => _error = error ?? 'Indiquez le nom du titulaire.');
      return;
    }
    try {
      final account = await widget.repository.addAccount(operator: _operator, phone: _phone.text, holder: _holder.text);
      if (mounted) Navigator.pop(context, account);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Compte Mobile Money'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<MobileMoneyOperator>(
                segments: const [
                  ButtonSegment(value: MobileMoneyOperator.mtn, label: Text('MTN MoMo')),
                  ButtonSegment(value: MobileMoneyOperator.orange, label: Text('Orange Money')),
                ],
                selected: {_operator},
                onSelectionChanged: (s) => setState(() => _operator = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: 'Numéro ${_operator.label}', prefixText: '+237 '),
              ),
              const SizedBox(height: 10),
              TextField(controller: _holder, decoration: const InputDecoration(labelText: 'Nom du titulaire')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: MboaColors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _save,
            child: const Text('Enregistrer'),
          ),
        ],
      );
}
