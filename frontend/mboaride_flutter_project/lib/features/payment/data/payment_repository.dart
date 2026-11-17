import '../../../core/api_client.dart';
import '../domain/payment.dart';

/// Trajets du passager et argent : comptes Mobile Money, paiement simulé (US10),
/// portefeuille MboaRide, « Mes trajets », suivi de la course et fin de course.
abstract class PaymentRepository {
  Future<List<MobileMoneyAccount>> accounts();

  Future<MobileMoneyAccount> addAccount({
    required MobileMoneyOperator operator,
    required String phone,
    required String holder,
  });

  Future<void> deleteAccount(int accountId);

  /// Lance le paiement : l'opérateur envoie une demande de validation au téléphone.
  Future<PaymentReceipt> startPayment({required int paymentId, required int accountId});

  /// Réponse simulée de l'opérateur : le payeur valide (code secret) ou refuse.
  Future<PaymentReceipt> answerOnPhone({required int paymentId, required bool approved});

  /// Paiement immédiat avec le solde du portefeuille (409 si le solde ne suffit pas).
  Future<PaymentReceipt> payWithWallet(int paymentId);

  Future<List<MyTrip>> myTrips();

  /// Renoncer à un trajet choisi : place libérée, paiement remboursé s'il avait eu lieu.
  Future<void> cancelTrip(int bookingId);

  // --- Portefeuille ---
  Future<Wallet> wallet();

  /// Recharge depuis un compte Mobile Money, validée par le code secret (jamais enregistré).
  Future<Wallet> topUpWallet({required int accountId, required int amountFcfa, required String pin});

  /// Virement du solde vers un compte Mobile Money (par défaut si [accountId] est nul).
  Future<Wallet> withdrawFromWallet({required int amountFcfa, int? accountId});

  /// Conducteur : gains virés aussitôt vers son compte Mobile Money par défaut.
  Future<Wallet> setAutoTransfer(bool enabled);

  // --- Course ---
  Future<RideTracking> tracking(int bookingId);

  /// Arrivé à destination : le passager valide la fin, note le conducteur et commente.
  Future<EndOfRideResult> validateEndOfRide(
    int bookingId, {
    required int rating,
    String? comment,
    bool serious = false,
  });
}

class ApiPaymentRepository implements PaymentRepository {
  ApiPaymentRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<MobileMoneyAccount>> accounts() async => [
    for (final a in (await _client.get('/api/moi/comptes-mobile-money') as List<dynamic>))
      MobileMoneyAccount.fromJson(a as Map<String, dynamic>),
  ];

  @override
  Future<MobileMoneyAccount> addAccount({
    required MobileMoneyOperator operator,
    required String phone,
    required String holder,
  }) async => MobileMoneyAccount.fromJson(
    await _client.post('/api/moi/comptes-mobile-money', {
      'operateur': operator.code,
      'telephone': phone.trim(),
      'titulaire': holder.trim(),
      'par_defaut': true,
    }) as Map<String, dynamic>,
  );

  @override
  Future<void> deleteAccount(int accountId) => _client.delete('/api/moi/comptes-mobile-money/$accountId');

  @override
  Future<PaymentReceipt> startPayment({required int paymentId, required int accountId}) async =>
      PaymentReceipt.fromJson(
        await _client.post('/api/paiements/$paymentId/mobile-money', {'id_compte': accountId})
            as Map<String, dynamic>,
      );

  @override
  Future<PaymentReceipt> answerOnPhone({required int paymentId, required bool approved}) async =>
      PaymentReceipt.fromJson(
        await _client.post('/api/paiements/$paymentId/simulation-operateur', {
          'resultat': approved ? 'valide' : 'refuse',
        }) as Map<String, dynamic>,
      );

  @override
  Future<PaymentReceipt> payWithWallet(int paymentId) async => PaymentReceipt.fromJson(
    await _client.post('/api/paiements/$paymentId/portefeuille') as Map<String, dynamic>,
  );

  @override
  Future<List<MyTrip>> myTrips() async => [
    for (final t in (await _client.get('/api/moi/reservations') as List<dynamic>))
      MyTrip.fromJson(t as Map<String, dynamic>),
  ];

  @override
  Future<void> cancelTrip(int bookingId) => _client.post('/api/moi/reservations/$bookingId/annulation');

  @override
  Future<Wallet> wallet() async =>
      Wallet.fromJson(await _client.get('/api/moi/portefeuille') as Map<String, dynamic>);

  @override
  Future<Wallet> topUpWallet({required int accountId, required int amountFcfa, required String pin}) async =>
      Wallet.fromJson(await _client.post('/api/moi/portefeuille/recharge', {
        'id_compte': accountId,
        'montant_fcfa': amountFcfa,
        'code_secret': pin,
      }) as Map<String, dynamic>);

  @override
  Future<Wallet> withdrawFromWallet({required int amountFcfa, int? accountId}) async =>
      Wallet.fromJson(await _client.post('/api/moi/portefeuille/retrait', {
        'montant_fcfa': amountFcfa,
        if (accountId != null) 'id_compte': accountId,
      }) as Map<String, dynamic>);

  @override
  Future<Wallet> setAutoTransfer(bool enabled) async => Wallet.fromJson(
    await _client.put('/api/moi/portefeuille/virement-auto', {'actif': enabled}) as Map<String, dynamic>,
  );

  @override
  Future<RideTracking> tracking(int bookingId) async =>
      RideTracking.fromJson(await _client.get('/api/moi/reservations/$bookingId/suivi') as Map<String, dynamic>);

  @override
  Future<EndOfRideResult> validateEndOfRide(
    int bookingId, {
    required int rating,
    String? comment,
    bool serious = false,
  }) async => EndOfRideResult.fromJson(
    await _client.post('/api/moi/reservations/$bookingId/fin-de-course', {
      'note': rating,
      if (comment != null && comment.trim().isNotEmpty) 'commentaire': comment.trim(),
      'signalement_grave': serious,
    }) as Map<String, dynamic>,
  );
}

/// Données simulées (FAKE_API=true) : un trajet à confirmer, un trajet confirmé.
class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({List<MobileMoneyAccount>? accounts, this.balanceFcfa = 0})
    : _accounts = [...?accounts];

  final List<MobileMoneyAccount> _accounts;
  int balanceFcfa;
  int _nextId = 1;
  bool _paid = false;
  bool _cancelled = false;
  bool autoTransfer = false;
  final List<WalletMovement> _movements = [];

  /// Fin de course validée : note et commentaire reçus.
  int? lastRating;
  String? lastComment;

  @override
  Future<List<MobileMoneyAccount>> accounts() async => List.unmodifiable(_accounts);

  @override
  Future<MobileMoneyAccount> addAccount({
    required MobileMoneyOperator operator,
    required String phone,
    required String holder,
  }) async {
    final error = operator.checkNumber(phone);
    if (error != null) throw ApiException(error, statusCode: 422);
    final account = MobileMoneyAccount(
      id: _nextId++,
      operator: operator,
      phone: '+237${MobileMoneyOperator.localNumber(phone)}',
      holder: holder.trim(),
      isDefault: true,
    );
    _accounts
      ..removeWhere((a) => a.phone == account.phone)
      ..insert(0, account);
    return account;
  }

  @override
  Future<void> deleteAccount(int accountId) async => _accounts.removeWhere((a) => a.id == accountId);

  @override
  Future<PaymentReceipt> startPayment({required int paymentId, required int accountId}) async {
    final account = _accounts.firstWhere((a) => a.id == accountId);
    return PaymentReceipt(
      paymentId: paymentId,
      status: PaymentStatus.pending,
      amountFcfa: 350,
      operatorLabel: account.operator.label,
      phone: account.phone,
      reference: 'MBR-DEMO',
      message: 'Une demande de paiement de 350 FCFA a été envoyée au ${account.displayPhone}. '
          'Validez-la avec votre code secret ${account.operator.label}.',
    );
  }

  @override
  Future<PaymentReceipt> answerOnPhone({required int paymentId, required bool approved}) async {
    _paid = approved;
    return PaymentReceipt(
      paymentId: paymentId,
      status: approved ? PaymentStatus.succeeded : PaymentStatus.failed,
      amountFcfa: 350,
      reference: 'MBR-DEMO',
      failureReason: approved ? null : 'Paiement refusé sur le téléphone du payeur',
      attemptsLeft: 2,
    );
  }

  void _move(WalletMovementType type, int amount, String label) {
    if (balanceFcfa + amount < 0) {
      throw ApiException(
        'Solde insuffisant : $balanceFcfa FCFA dans votre portefeuille pour ${-amount} FCFA à payer',
        statusCode: 409,
      );
    }
    balanceFcfa += amount;
    _movements.insert(
      0,
      WalletMovement(
        type: type,
        typeLabel: type.code,
        amountFcfa: amount,
        balanceAfterFcfa: balanceFcfa,
        label: label,
        reference: 'PF-DEMO',
        createdAt: DateTime(2026, 11, 17, 8),
      ),
    );
  }

  @override
  Future<PaymentReceipt> payWithWallet(int paymentId) async {
    _move(WalletMovementType.payment, -350, 'Trajet Kotto → Bonanjo avec Armand');
    _paid = true;
    return PaymentReceipt(
      paymentId: paymentId,
      status: PaymentStatus.succeeded,
      amountFcfa: 350,
      reference: 'MBR-PF',
      operatorLabel: 'Portefeuille MboaRide',
    );
  }

  @override
  Future<List<MyTrip>> myTrips() async => [
    MyTrip(
      bookingId: 1,
      state: _cancelled
          ? TripState.cancelled
          : (lastRating != null ? TripState.done : (_paid ? TripState.confirmed : TripState.toConfirm)),
      date: DateTime(2026, 11, 18),
      route: 'Kotto → Bonanjo',
      pickupTime: '06:58',
      arrivalTime: '07:34',
      priceFcfa: 350,
      driver: 'Armand',
      vehicle: 'Berline 2012 · LT-001-AA',
      paymentId: 1,
      paymentStatus: _paid ? PaymentStatus.succeeded : PaymentStatus.pending,
      reference: _paid ? 'MBR-DEMO' : null,
      driverPhone: _paid ? '+237690000101' : null,
      pickupPoint: 'Carrefour Kotto, devant la pharmacie',
      endValidated: lastRating != null,
      myRating: lastRating,
    ),
    MyTrip(
      bookingId: 2,
      state: TripState.confirmed,
      date: DateTime(2026, 11, 17),
      route: 'Kotto → Bonanjo',
      pickupTime: '06:58',
      arrivalTime: '07:34',
      priceFcfa: 350,
      driver: 'Armand',
      vehicle: 'Berline 2012 · LT-001-AA',
      paymentId: 2,
      paymentStatus: PaymentStatus.succeeded,
      reference: 'MBR-1A2B3C4D',
      operatorLabel: 'Orange Money',
      driverPhone: '+237690000101',
      pickupPoint: 'Carrefour Kotto, devant la pharmacie',
      pickupInstructions: 'Berline grise, je klaxonne deux fois',
      courseStatus: CourseStatus.running,
    ),
  ];

  @override
  Future<void> cancelTrip(int bookingId) async => _cancelled = true;

  Wallet _wallet() => Wallet(
    balanceFcfa: balanceFcfa,
    autoTransfer: autoTransfer,
    defaultAccount: _accounts.firstOrNull,
    pendingEarningsFcfa: 630,
    pendingPassengers: 2,
    escrowFcfa: _paid ? 350 : 0,
    movements: List.unmodifiable(_movements),
  );

  @override
  Future<Wallet> wallet() async => _wallet();

  @override
  Future<Wallet> topUpWallet({required int accountId, required int amountFcfa, required String pin}) async {
    if (pin.length < 4) throw ApiException('Code secret à 4 ou 5 chiffres.', statusCode: 422);
    final account = _accounts.firstWhere((a) => a.id == accountId);
    _move(WalletMovementType.topUp, amountFcfa, 'Recharge depuis ${account.operator.label} ${account.displayPhone}');
    return _wallet();
  }

  @override
  Future<Wallet> withdrawFromWallet({required int amountFcfa, int? accountId}) async {
    final account = accountId == null ? _accounts.firstOrNull : _accounts.firstWhere((a) => a.id == accountId);
    if (account == null) throw ApiException("Enregistrez d'abord un compte Mobile Money", statusCode: 404);
    _move(WalletMovementType.withdrawal, -amountFcfa, 'Virement vers ${account.operator.label} ${account.displayPhone}');
    return _wallet();
  }

  @override
  Future<Wallet> setAutoTransfer(bool enabled) async {
    if (enabled && _accounts.isEmpty) {
      throw ApiException("Enregistrez d'abord un compte Mobile Money", statusCode: 404);
    }
    autoTransfer = enabled;
    return _wallet();
  }

  /// Course de démonstration : Kotto → Bonanjo, à Douala.
  static RideTracking demoTracking({int bookingId = 2}) => RideTracking(
    bookingId: bookingId,
    date: DateTime(2026, 11, 17),
    paid: true,
    courseStatus: CourseStatus.running,
    endValidated: false,
    canValidate: true,
    driver: 'Armand',
    driverLastName: 'Tchoua',
    driverPhone: '+237690000101',
    vehicle: 'Berline 2012 · LT-001-AA',
    pickupTime: '06:58',
    arrivalTime: '07:34',
    priceFcfa: 350,
    pickupPoint: 'Carrefour Kotto, devant la pharmacie',
    pickupInstructions: 'Berline grise, je klaxonne deux fois',
    from: const GeoPlace(label: 'Kotto', lat: 4.0720, lng: 9.7660),
    to: const GeoPlace(label: 'Bonanjo', lat: 4.0435, lng: 9.6908),
  );

  @override
  Future<RideTracking> tracking(int bookingId) async => demoTracking(bookingId: bookingId);

  @override
  Future<EndOfRideResult> validateEndOfRide(
    int bookingId, {
    required int rating,
    String? comment,
    bool serious = false,
  }) async {
    if (lastRating != null) throw ApiException('Vous avez déjà validé la fin de cette course', statusCode: 409);
    lastRating = rating;
    lastComment = comment;
    return EndOfRideResult(
      message: "Merci d'avoir voyagé avec MboaRide !",
      driver: 'Armand',
      rating: rating,
      driverPaid: false,
      waitingFor: const ['Paul'],
    );
  }
}
