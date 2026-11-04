// Default entry point so plain `flutter run` works; same as main_dev.dart.
import 'app/bootstrap.dart';
import 'app/flavor.dart';

Future<void> main() => bootstrap(Flavor.dev);
