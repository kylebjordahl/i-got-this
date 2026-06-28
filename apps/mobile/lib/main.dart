import 'package:flutter/material.dart';

/// Phase 0 shell. Real screens (feeds, rules, unowned dashboard, claim/swap,
/// calendar-connect onboarding) land in Phase 5. The OpenAPI-generated API
/// client will live under lib/api/generated/ (see /tools).
void main() {
  runApp(const CaretakerApp());
}

class CaretakerApp extends StatelessWidget {
  const CaretakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caretaker',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3A7D5D),
        useMaterial3: true,
      ),
      home: const _HomePlaceholder(),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caretaker')),
      body: const Center(
        child: Text('Family logistics — coming soon'),
      ),
    );
  }
}
