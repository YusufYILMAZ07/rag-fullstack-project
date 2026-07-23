import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rag_frontend/main.dart';

void main() {
  testWidgets('PDF upload screen renders core fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PDF Upload'), findsOneWidget);
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('Course Name'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Study Focus'), findsOneWidget);
    expect(find.text('PDF Seç'), findsOneWidget);
    expect(find.text('Yükle'), findsOneWidget);
  });

  testWidgets('Upload requires selecting a PDF file', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.ensureVisible(find.text('Yükle'));
    await tester.tap(find.text('Yükle'));
    await tester.pumpAndSettle();

    expect(find.text('Lütfen önce bir PDF dosyası seçin.'), findsOneWidget);
  });

  testWidgets('Invalid backend URL shows validation message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Backend URL'),
      'invalid-url',
    );
    await tester.ensureVisible(find.text('Yükle'));
    await tester.tap(find.text('Yükle'));
    await tester.pumpAndSettle();

    expect(find.text('Geçerli bir URL girin.'), findsOneWidget);
  });
}
