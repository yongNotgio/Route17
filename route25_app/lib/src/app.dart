import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class Route25App extends StatelessWidget {
  const Route25App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Route25',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

