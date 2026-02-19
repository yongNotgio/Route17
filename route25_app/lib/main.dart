import 'src/app.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/services/route_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const defaultSupabaseUrl = 'https://ldkhvyhxqnqptldbungk.supabase.co';
  const defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxka2h2eWh4cW5xcHRsZGJ1bmdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0MDk5NzEsImV4cCI6MjA4Njk4NTk3MX0.Ftop7pN7I2YzqzscwMnVW26uT3dKeXcDmeMetrk-3KY';

  const supabaseUrlFromDefine = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKeyFromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  final supabaseUrl =
      supabaseUrlFromDefine.isNotEmpty ? supabaseUrlFromDefine : defaultSupabaseUrl;
  final supabaseAnonKey = supabaseAnonKeyFromDefine.isNotEmpty
      ? supabaseAnonKeyFromDefine
      : defaultSupabaseAnonKey;

  RouteRepository repository = const RouteRepository();

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    repository = RouteRepository(
      supabaseClient: Supabase.instance.client,
    );
  }

  runApp(Route25App(repository: repository));
}
