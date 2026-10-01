import "package:flutter_test/flutter_test.dart";
import "package:stokli_mobile/api_exception.dart";
import "package:stokli_mobile/api_client.dart";

void main() {
  group("normalizeApiEndpoint", () {
    test("adds the project API path to a host address", () {
      expect(
        normalizeApiEndpoint("http://192.168.1.10"),
        "http://192.168.1.10/Stokli%20BMC/api/index.php",
      );
    });

    test("adds index.php to an API directory", () {
      expect(
        normalizeApiEndpoint("http://localhost:8080/Stokli%20BMC/api"),
        "http://localhost:8080/Stokli%20BMC/api/index.php",
      );
    });

    test("preserves a complete endpoint and removes its query", () {
      expect(
        normalizeApiEndpoint("https://stokli.example/api/index.php?old=value"),
        "https://stokli.example/api/index.php",
      );
    });

    test("rejects addresses without an HTTP scheme", () {
      expect(
        () => normalizeApiEndpoint("192.168.1.10"),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
