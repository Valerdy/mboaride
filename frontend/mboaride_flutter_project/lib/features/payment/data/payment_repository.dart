import '../../../core/api_client.dart';
import '../domain/payment.dart';

/// Comptes Mobile Money, paiement simulé et « Mes trajets » (US10).
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

  Future<List<MyTrip>> myTrips();

  /// Renoncer à un trajet choisi : place libérée, paiement remboursé s'il avait eu lieu.
  Future<void> cancelTrip(int bookingId);
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
  Future<List<MyTrip>> myTrips() async => [
    for (final t in (await _client.get('/api/moi/reservations') as List<dynamic>))
      MyTrip.fromJson(t as Map<String, dynamic>),
  ];

  @override
  Future<void> cancelTrip(int bookingId) => _client.post('/api/moi/reservations/$bookingId/annulation');
}

/// Données simulées (FAKE_API=true) : un trajet à confirmer, un trajet confirmé.
class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({List<MobileMoneyAccount>? accounts}) : _accounts = [...?accounts];

  final List<MobileMoneyAccount> _accounts;
  int _nextId = 1;
  bool _paid = false;
  bool _cancelled = false;

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
      amountFcfa: 336,
      operatorLabel: account.operator.label,
      phone: account.phone,
      reference: 'MBR-DEMO',
      message: 'Une demande de paiement de 336 FCFA a été envoyée au ${account.displayPhone}. '
          'Validez-la avec votre code secret ${account.operator.label}.',
    );
  }

  @override
  Future<PaymentReceipt> answerOnPhone({required int paymentId, required bool approved}) async {
    _paid = approved;
    return PaymentReceipt(
      paymentId: paymentId,
      status: approved ? PaymentStatus.succeeded : PaymentStatus.failed,
      amountFcfa: 336,
      reference: 'MBR-DEMO',
      failureReason: approved ? null : 'Paiement refusé sur le téléphone du payeur',
      attemptsLeft: 2,
    );
  }

  @override
  Future<List<MyTrip>> myTrips() async => [
    MyTrip(
      bookingId: 1,
      state: _cancelled ? TripState.cancelled : (_paid ? TripState.confirmed : TripState.toConfirm),
      date: DateTime(2026, 11, 18),
      route: 'Kotto → Bonanjo',
      pickupTime: '06:58',
      arrivalTime: '07:34',
      priceFcfa: 336,
      driver: 'Armand',
      vehicle: 'Berline 2012 · LT-001-AA',
      paymentId: 1,
      paymentStatus: _paid ? PaymentStatus.succeeded : PaymentStatus.pending,
      reference: _paid ? 'MBR-DEMO' : null,
    ),
    MyTrip(
      bookingId: 2,
      state: TripState.confirmed,
      date: DateTime(2026, 11, 17),
      route: 'Kotto → Bonanjo',
      pickupTime: '06:58',
      arrivalTime: '07:34',
      priceFcfa: 336,
      driver: 'Armand',
      vehicle: 'Berline 2012 · LT-001-AA',
      paymentId: 2,
      paymentStatus: PaymentStatus.succeeded,
      reference: 'MBR-1A2B3C4D',
      operatorLabel: 'Orange Money',
    ),
  ];

  @override
  Future<void> cancelTrip(int bookingId) async => _cancelled = true;
}
