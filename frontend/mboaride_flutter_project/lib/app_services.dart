import 'core/api_client.dart';
import 'core/app_config.dart';
import 'features/children/data/children_repository.dart';
import 'features/driver/data/driver_repository.dart';
import 'features/intercity/data/intercity_repository.dart';
import 'features/offers/data/offers_repository.dart';
import 'features/payment/data/payment_repository.dart';
import 'features/preferences/data/preferences_repository.dart';
import 'features/ride_request/data/api_ride_request_repository.dart';
import 'features/ride_request/data/ride_request_repository.dart';

/// Sources de données de l'application : l'API Python, ou des données simulées
/// avec `--dart-define=FAKE_API=true`. Un seul endroit décide, tous les écrans suivent.
class AppServices {
  AppServices._();

  static final ApiClient client = ApiClient();
  static const bool _fake = AppConfig.useFakeApi;

  static final RideRequestRepository rideRequests =
      _fake ? FakeRideRequestRepository() : ApiRideRequestRepository(client: client);
  static final OffersRepository offers =
      _fake ? FakeOffersRepository() : ApiOffersRepository(client: client);
  static final PreferencesRepository preferences =
      _fake ? FakePreferencesRepository() : ApiPreferencesRepository(client: client);
  static final ChildrenRepository children =
      _fake ? FakeChildrenRepository() : ApiChildrenRepository(client: client);
  static final IntercityRepository intercity =
      _fake ? FakeIntercityRepository() : ApiIntercityRepository(client: client);
  static final PaymentRepository payments =
      _fake ? FakePaymentRepository() : ApiPaymentRepository(client: client);
  static final DriverRepository driver =
      _fake ? FakeDriverRepository() : ApiDriverRepository(client: client);
}
