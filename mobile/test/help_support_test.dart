import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stokli_mobile/help_support.dart";

void main() {
  testWidgets(
    "FAQ search filters help and excludes admin topics for students",
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HelpSupportPage(isAdmin: false)),
      );
      await tester.enterText(
        find.byType(TextField).first,
        "manage student accounts",
      );
      await tester.pumpAndSettle();
      expect(find.text("No matching help topics."), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, "request equipment");
      await tester.pumpAndSettle();
      expect(find.text("Borrowing"), findsOneWidget);
    },
  );

  testWidgets("chat answers from its bundled guide", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HelpSupportPage(isAdmin: false)),
    );
    await tester.tap(find.text("Chat support"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("How do I borrow equipment?"));
    await tester.pumpAndSettle();

    expect(find.textContaining("Open Inventory"), findsOneWidget);
    expect(
      find.textContaining("I do not look up account-specific records"),
      findsOneWidget,
    );
  });
}
