import 'package:flutter/material.dart';
import 'screens/main_layout.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DemandCast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const MainLayout(initialIndex: 0),
        '/dashboard': (_) => const MainLayout(initialIndex: 0),
        '/forecast':  (_) => const MainLayout(initialIndex: 1),
        '/settings':  (_) => const MainLayout(initialIndex: 2),
      },
    );
  }
}
