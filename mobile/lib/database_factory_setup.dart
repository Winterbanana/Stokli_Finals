import "database_factory_setup_stub.dart"
    if (dart.library.js_interop) "database_factory_setup_web.dart" as setup;

Future<void> initializeDatabaseFactory() => setup.initializeDatabaseFactory();
