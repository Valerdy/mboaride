import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_session.dart';
import '../../../core/mboa_theme.dart';
import '../../wallet/wallet_screen.dart';
import '../data/payment_repository.dart';
import '../domain/payment.dart';

/// Résultat de l'écran de paiement, renvoyé à l'écran précédent.
enum PaymentOutcome { paid, notPaid }

/// Payer un trajet choisi par Mobile Money (simulé) : c'est le paiement qui le confirme.
///
/// Le passager enregistre une fois son opérateur, son numéro et le nom du titulaire, puis
/// paie. La validation sur le téléphone est simulée : le code secret demandé ici n'est ni
/// envoyé ni enregistré, comme avec un vrai opérateur où il ne quitte pas le téléphone.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.repository,
    required this.paymentId,
    required this.amountFcfa,
    required this.route,
    required this.driver,
    required this.date,
  });

  final PaymentRepository repository;
  final int paymentId;
  final int amountFcfa;
  final String route;
  final String driver;
  final DateTime date;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  List<MobileMoneyAccount>? _accounts;
  int? _selected;
  bool _adding = false;
  bool _busy = false;
  String? _error;
  PaymentReceipt? _paid;
  Wallet? _wallet;

  MobileMoneyOperator _operator = MobileMoneyOperator.mtn;
  final _phone = TextEditingController();
  late final _holder = TextEditingController(
    text: [AuthSession.profile?['prenom'], AuthSession.profile?['nom']].whereType<String>().join(' '),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accounts = await widget.repository.accounts();
      Wallet? wallet;
      try {
        wallet = await widget.repository.wallet();
      } on ApiException {
        wallet = null; // portefeuille indisponible : on paie par Mobile Money
      }
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _accounts = accounts;
        _selected = accounts.where((a) => a.isDefault).firstOrNull?.id ?? accounts.firstOrNull?.id;
        _adding = accounts.isEmpty;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _saveAccount() async {
    final error = _operator.checkNumber(_phone.text);
    if (error != null || _holder.text.trim().length < 2) {
      setState(() => _error = error ?? 'Indiquez le nom du titulaire du compte.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await widget.repository.addAccount(
        operator: _operator,
        phone: _phone.text,
        holder: _holder.text,
      );
      final accounts = await widget.repository.accounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _selected = account.id;
        _adding = false;
        _phone.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    final accountId = _selected;
    if (accountId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final started = await widget.repository.startPayment(paymentId: widget.paymentId, accountId: accountId);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PhoneValidationDialog(receipt: started),
      );
      final result = await widget.repository.answerOnPhone(
        paymentId: widget.paymentId,
        approved: approved == true,
      );
      if (!mounted) return;
      setState(() {
        if (result.status == PaymentStatus.succeeded) {
          _paid = result;
        } else {
          _error = '${result.failureReason ?? 'Paiement non abouti.'} '
              'Il vous reste ${result.attemptsLeft} essai(s).';
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payWithWallet() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.payWithWallet(widget.paymentId);
      if (mounted) setState(() => _paid = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWallet() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WalletScreen(repository: widget.repository)),
    );
    if (mounted) _load();
  }

  Widget _walletChoice(Wallet w) {
    final enough = w.balanceFcfa >= widget.amountFcfa;
    return _Card(
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, color: MboaColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mon portefeuille MboaRide · ${w.balanceFcfa} FCFA',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          enough
              ? 'Paiement immédiat, sans code. L\'argent reste chez MboaRide jusqu\'à la fin de la course.'
              : 'Solde insuffisant : rechargez votre portefeuille depuis Mobile Money, ou payez directement ci-dessous.',
          style: const TextStyle(fontSize: 12.5, color: MboaColors.mutedText),
        ),
        const SizedBox(height: 10),
        enough
            ? FilledButton.icon(
                onPressed: _busy ? null : _payWithWallet,
                icon: const Icon(Icons.bolt),
                label: Text('Payer ${widget.amountFcfa} FCFA avec mon portefeuille'),
              )
            : OutlinedButton.icon(
                onPressed: _busy ? null : _openWallet,
                icon: const Icon(Icons.add),
                label: const Text('Recharger mon portefeuille'),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, result) {},
    child: Scaffold(
      appBar: AppBar(title: Text(_paid == null ? 'Payer le trajet' : 'Trajet confirmé')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          _summary(),
          const SizedBox(height: 16),
          if (_paid != null) ..._success() else ..._paymentForm(),
        ],
      ),
    ),
  );

  Widget _summary() => _Card(
    children: [
      Text(widget.route, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: MboaColors.night)),
      const SizedBox(height: 4),
      Text('Avec ${widget.driver} · ${frenchDate(widget.date)}', style: const TextStyle(color: MboaColors.mutedText)),
      const Divider(height: 22),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('À payer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text('${widget.amountFcfa} FCFA',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MboaColors.green)),
        ],
      ),
      if (_paid == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Votre place est retenue. Le trajet sera confirmé, et le conducteur prévenu, dès le paiement.',
            style: TextStyle(fontSize: 13, color: MboaColors.mutedText),
          ),
        ),
    ],
  );

  List<Widget> _paymentForm() {
    final accounts = _accounts;
    return [
      if (accounts == null && _error == null) const Center(child: CircularProgressIndicator()),
      if (_wallet != null) ...[
        _walletChoice(_wallet!),
        const SizedBox(height: 8),
      ],
      if (accounts != null && accounts.isNotEmpty) ...[
        Text(_wallet == null ? 'Payer avec' : 'Ou payer par Mobile Money',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        RadioGroup<int>(
          groupValue: _selected,
          onChanged: (id) => setState(() => _selected = id),
          child: Column(
            children: [
              for (final a in accounts)
                _Card(
                  padding: EdgeInsets.zero,
                  children: [
                    RadioListTile<int>(
                      value: a.id,
                      title: Text(a.operator.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${a.displayPhone} · ${a.holder}'),
                      secondary: IconButton(
                        tooltip: 'Supprimer ce compte',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () async {
                                await widget.repository.deleteAccount(a.id);
                                _load();
                              },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (!_adding)
          TextButton.icon(
            onPressed: () => setState(() => _adding = true),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un compte Mobile Money'),
          ),
      ],
      if (_adding) _accountForm(),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _Banner(text: _error!),
      ],
      const SizedBox(height: 18),
      if (!_adding)
        FilledButton.icon(
          onPressed: _busy || _selected == null ? null : _pay,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.phone_iphone),
          label: Text('Payer ${widget.amountFcfa} FCFA'),
        ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(PaymentOutcome.notPaid),
        child: const Text('Payer plus tard (le trajet reste à confirmer)'),
      ),
    ];
  }

  Widget _accountForm() => _Card(
    children: [
      const Text('Enregistrer mon compte Mobile Money', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text(
        'Opérateur, numéro et titulaire. Votre code secret n\'est jamais enregistré.',
        style: TextStyle(fontSize: 12.5, color: MboaColors.mutedText),
      ),
      const SizedBox(height: 12),
      SegmentedButton<MobileMoneyOperator>(
        segments: const [
          ButtonSegment(value: MobileMoneyOperator.mtn, label: Text('MTN MoMo')),
          ButtonSegment(value: MobileMoneyOperator.orange, label: Text('Orange Money')),
        ],
        selected: {_operator},
        onSelectionChanged: (s) => setState(() => _operator = s.first),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Numéro ${_operator.label}',
          hintText: _operator == MobileMoneyOperator.mtn ? '6 77 12 34 56' : '6 99 12 34 56',
          prefixText: '+237 ',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _holder,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nom du titulaire du compte'),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          if ((_accounts ?? const []).isNotEmpty)
            TextButton(onPressed: _busy ? null : () => setState(() => _adding = false), child: const Text('Annuler')),
          const Spacer(),
          FilledButton(
            // Bouton dans une ligne : largeur finie (le thème étire les boutons sur toute la largeur).
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: _busy ? null : _saveAccount,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ],
  );

  List<Widget> _success() {
    final r = _paid!;
    return [
      _Card(
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: MboaColors.green, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('Paiement reçu : votre trajet est confirmé',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Référence : ${r.reference ?? '—'}'),
          Text('Montant : ${r.amountFcfa} FCFA'),
          if (r.operatorLabel != null) Text('Payé avec : ${r.operatorLabel} ${r.phone ?? ''}'),
          const SizedBox(height: 8),
          Text(
            '${widget.driver} est prévenu. MboaRide garde le paiement jusqu\'à la fin de la course : '
            '${widget.driver} le recevra quand vous l\'aurez validée. Retrouvez ce trajet dans « Mes trajets ».',
            style: const TextStyle(color: MboaColors.mutedText),
          ),
        ],
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(PaymentOutcome.paid),
        child: const Text('Terminer'),
      ),
    ];
  }
}

/// Validation simulée sur le téléphone du payeur : code secret de l'opérateur.
class _PhoneValidationDialog extends StatefulWidget {
  const _PhoneValidationDialog({required this.receipt});

  final PaymentReceipt receipt;

  @override
  State<_PhoneValidationDialog> createState() => _PhoneValidationDialogState();
}

class _PhoneValidationDialogState extends State<_PhoneValidationDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.receipt.operatorLabel ?? 'Mobile Money'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.receipt.message ?? 'Validez le paiement avec votre code secret.'),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 5,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Code secret', counterText: ''),
        ),
        const Text(
          'Paiement fictif : aucun montant n\'est débité et le code n\'est ni envoyé ni enregistré.',
          style: TextStyle(fontSize: 12, color: MboaColors.mutedText),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Refuser')),
      FilledButton(
        onPressed: _pin.text.length >= 4 ? () => Navigator.of(context).pop(true) : null,
        child: const Text('Valider'),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.all(16)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Surface Material : les choix de compte gardent leur effet au toucher.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: MboaColors.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: MboaColors.redSoft, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(color: MboaColors.redText)),
  );
}
