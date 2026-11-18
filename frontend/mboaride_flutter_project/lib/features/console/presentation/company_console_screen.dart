import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/console_repository.dart';
import '../domain/console.dart';

/// Console entreprise, pensée pour un écran large (Flutter web).
///
/// US13 · Inviter les employés et suivre l'adoption.
/// US14 · Voir les économies réalisées et le CO2 évité.
class CompanyConsoleScreen extends StatefulWidget {
  const CompanyConsoleScreen({
    super.key,
    required this.repository,
    this.onOpenCsv,
  });

  final ConsoleRepository repository;

  /// Ouverture de l'export CSV. Sur le web, brancher `url_launcher` ou
  /// `window.open` ; en test, une fonction qui mémorise l'adresse.
  final void Function(String url)? onOpenCsv;

  @override
  State<CompanyConsoleScreen> createState() => _CompanyConsoleScreenState();
}

class _CompanyConsoleScreenState extends State<CompanyConsoleScreen> {
  Organisation? _organisation;
  Adoption? _adoption;
  Impact? _impact;
  List<Invitation> _invitations = const [];
  bool _loading = true;
  String? _error;
  int? _busyInvitation;

  final _emails = TextEditingController();
  final _service = TextEditingController();
  bool _sending = false;
  InvitationResult? _lastSend;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emails.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final organisations = await widget.repository.organisations();
      final admin = organisations.where((o) => o.isAdmin).toList();
      if (admin.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              'Votre compte n\'administre aucune organisation. La console est '
              'réservée aux administrateurs.';
        });
        return;
      }
      final organisation = admin.first;
      final adoption = await widget.repository.adoption(organisation.id);
      final impact = await widget.repository.impact(organisation.id);
      final invitations = await widget.repository.invitations(organisation.id);
      if (!mounted) return;
      setState(() {
        _organisation = organisation;
        _adoption = adoption;
        _impact = impact;
        _invitations = invitations;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _invite() async {
    final organisation = _organisation;
    if (organisation == null) return;
    final emails = _emails.text
        .split(RegExp(r'[,;\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    if (emails.isEmpty) {
      setState(
        () => _lastSend = const InvitationResult(
          sent: [],
          rejected: [],
          note: 'Collez au moins une adresse.',
        ),
      );
      return;
    }
    setState(() {
      _sending = true;
      _lastSend = null;
    });
    try {
      final result = await widget.repository.invite(
        organisationId: organisation.id,
        emails: emails,
        service: _service.text.trim(),
      );
      final invitations = await widget.repository.invitations(organisation.id);
      final adoption = await widget.repository.adoption(organisation.id);
      if (!mounted) return;
      setState(() {
        _lastSend = result;
        _invitations = invitations;
        _adoption = adoption;
        _sending = false;
        if (result.sent.isNotEmpty) _emails.clear();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _lastSend = InvitationResult(
          sent: const [],
          rejected: const [],
          note: error.message,
        );
      });
    }
  }

  Future<void> _remind(Invitation invitation) async {
    final organisation = _organisation;
    if (organisation == null) return;
    setState(() => _busyInvitation = invitation.id);
    try {
      final updated = await widget.repository.remind(
        organisation.id,
        invitation.id,
      );
      if (!mounted) return;
      setState(() {
        _invitations = _invitations
            .map(
              (i) => i.id == updated.id
                  ? Invitation(
                      id: i.id,
                      email: i.email,
                      status: i.status,
                      reminders: updated.reminders,
                      service: i.service,
                      member: i.member,
                      trips: i.trips,
                      sentOn: i.sentOn,
                      expiresOn: i.expiresOn,
                    )
                  : i,
            )
            .toList(growable: false);
        _busyInvitation = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busyInvitation = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _openCsv() {
    final organisation = _organisation;
    if (organisation == null) return;
    final url = widget.repository.impactCsvUrl(organisation.id);
    final open = widget.onOpenCsv;
    if (open != null) {
      open(url);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export disponible à $url')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _organisation == null
            ? 'Console entreprise'
            : 'Console entreprise · ${_organisation!.name}',
      ),
      actions: [
        if (_impact != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _openCsv,
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
            ),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MboaColors.red),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdoptionPanel(adoption: _adoption!),
                  const SizedBox(height: 20),
                  _InvitePanel(
                    emails: _emails,
                    service: _service,
                    sending: _sending,
                    result: _lastSend,
                    onSend: _invite,
                  ),
                ],
              );
              final right = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImpactPanel(impact: _impact!),
                  const SizedBox(height: 20),
                  _InvitationsPanel(
                    invitations: _invitations,
                    busyId: _busyInvitation,
                    onRemind: _remind,
                  ),
                ],
              );
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: left),
                              const SizedBox(width: 24),
                              Expanded(child: right),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              left,
                              const SizedBox(height: 20),
                              right,
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MboaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 13,
                color: MboaColors.mutedText,
              ),
            ),
          ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: highlight ? MboaColors.night : MboaColors.sand,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: highlight ? MboaColors.sun : MboaColors.green,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: highlight ? Colors.white70 : MboaColors.mutedText,
          ),
        ),
      ],
    ),
  );
}

class _AdoptionPanel extends StatelessWidget {
  const _AdoptionPanel({required this.adoption});

  final Adoption adoption;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Adoption',
    subtitle:
        'Objectif ${adoption.targetLabel} de l\'effectif. '
        '${adoption.targetReached ? 'Objectif atteint.' : '${adoption.missingForTarget ?? 0} membre(s) manquant(s).'}',
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Figure(
            value: adoption.rateLabel,
            label: 'taux d\'adoption',
            highlight: true,
          ),
          _Figure(
            value: '${adoption.members} / ${adoption.headcount}',
            label: 'membres sur l\'effectif',
          ),
          _Figure(
            value: adoption.activeMembers30d.toString(),
            label: 'actifs sur 30 jours',
          ),
          _Figure(
            value: adoption.approvedDrivers.toString(),
            label: 'conducteurs agréés',
          ),
        ],
      ),
      if (adoption.byService.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text(
          'Par service',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 8),
        ...adoption.byService.map(
          (row) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.service.isEmpty ? 'Sans service' : row.service,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MboaColors.night,
                    ),
                  ),
                ),
                Text(
                  '${row.members} membre(s) · ${row.active} actif(s)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MboaColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class _ImpactPanel extends StatelessWidget {
  const _ImpactPanel({required this.impact});

  final Impact impact;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Économies et CO2 évité',
    subtitle: 'Du ${impact.from} au ${impact.to}',
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Figure(
            value:
                '${impact.co2CarefulKg.round()} à ${impact.co2HighKg.round()} kg',
            label: 'CO2 évité (prudent à haut)',
            highlight: true,
          ),
          _Figure(
            value: formatFcfa(impact.employeeSavingsFcfa),
            label: 'économisés par les employés',
          ),
          _Figure(
            value: '${impact.kmAvoided.round()} km',
            label: 'kilomètres voiture évités',
          ),
          _Figure(
            value: impact.sharedTrips.toString(),
            label: 'trajets partagés',
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        'Abonnement : ${impact.subscribers} abonnés, '
        '${formatFcfa(impact.subscriptionCostFcfa)} sur la période'
        '${impact.savingsPerFcfa == null ? '' : ', soit ${impact.savingsPerFcfa!.toStringAsFixed(1)} FCFA économisés par franc dépensé'}.',
        style: const TextStyle(fontSize: 13, color: MboaColors.night),
      ),
      const SizedBox(height: 6),
      Text(
        'Hypothèses : 8 L/100 km, 2,31 kg de CO2 par litre. Scénario prudent : '
        'un passager sur trois aurait conduit seul. Dépense des employés sur '
        'MboaRide : ${formatFcfa(impact.employeeSpendFcfa)}.',
        style: const TextStyle(fontSize: 12, color: MboaColors.mutedText),
      ),
    ],
  );
}

class _InvitePanel extends StatelessWidget {
  const _InvitePanel({
    required this.emails,
    required this.service,
    required this.sending,
    required this.result,
    required this.onSend,
  });

  final TextEditingController emails;
  final TextEditingController service;
  final bool sending;
  final InvitationResult? result;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Inviter des employés',
    subtitle:
        'Collez les adresses séparées par une virgule, un point-virgule ou un '
        'retour à la ligne. Les adresses hors du domaine de l\'entreprise sont '
        'écartées avec leur motif.',
    children: [
      TextField(
        controller: emails,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Adresses professionnelles',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: service,
        decoration: const InputDecoration(
          labelText: 'Service (facultatif)',
          helperText: 'Sert au suivi de l\'adoption par service',
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: sending ? null : onSend,
          icon: const Icon(Icons.send),
          label: Text(sending ? 'Envoi...' : 'Envoyer les invitations'),
        ),
      ),
      if (result != null) ...[
        const SizedBox(height: 14),
        if (result!.note.isNotEmpty)
          Text(
            result!.note,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MboaColors.night,
            ),
          ),
        ...result!.sent.map(
          (email) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Invitée : $email',
              style: const TextStyle(fontSize: 13, color: MboaColors.green),
            ),
          ),
        ),
        ...result!.rejected.map(
          (row) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Écartée : ${row.email} · ${row.reason}',
              style: const TextStyle(fontSize: 13, color: MboaColors.red),
            ),
          ),
        ),
      ],
    ],
  );
}

class _InvitationsPanel extends StatelessWidget {
  const _InvitationsPanel({
    required this.invitations,
    required this.busyId,
    required this.onRemind,
  });

  final List<Invitation> invitations;
  final int? busyId;
  final Future<void> Function(Invitation) onRemind;

  @override
  Widget build(BuildContext context) {
    final sorted = [...invitations]
      ..sort((a, b) {
        const order = {'envoyee': 0, 'expiree': 1, 'refusee': 2, 'acceptee': 3};
        final byStatus = (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
        return byStatus != 0 ? byStatus : a.email.compareTo(b.email);
      });
    return _Panel(
      title: 'Invitations',
      subtitle:
          'Les invitations en attente passent en premier. Trois relances au '
          'maximum par adresse.',
      children: [
        if (sorted.isEmpty)
          const Text(
            'Aucune invitation pour le moment.',
            style: TextStyle(color: MboaColors.mutedText),
          ),
        ...sorted.map(
          (invitation) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MboaColors.sand,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation.member ?? invitation.email,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MboaColors.night,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${invitation.statusLabel}'
                        '${invitation.service == null || invitation.service!.isEmpty ? '' : ' · ${invitation.service}'}'
                        '${invitation.reminders == 0 ? '' : ' · ${invitation.reminders} relance(s)'}'
                        '${invitation.trips == 0 ? '' : ' · ${invitation.trips} trajet(s)'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: MboaColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busyId == invitation.id)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (invitation.canRemind)
                  OutlinedButton(
                    onPressed: () => onRemind(invitation),
                    child: const Text('Relancer'),
                  )
                else if (invitation.status == 'envoyee')
                  const Text(
                    'Limite atteinte',
                    style: TextStyle(fontSize: 12, color: MboaColors.red),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
