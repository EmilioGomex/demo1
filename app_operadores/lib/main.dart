import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/screens/bienvenida_screen.dart';
import 'app/screens/config_screen.dart';
import 'config/parsable_secrets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bloquear orientación portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: AppSecrets.supabaseUrl,
    anonKey: AppSecrets.supabaseKey,
  );

  final prefs = await SharedPreferences.getInstance();
  final idMaquina = prefs.getString('id_maquina_local') ?? '';

  runApp(MyApp(idMaquinaLocal: idMaquina));
}

class MyApp extends StatelessWidget {
  final String idMaquinaLocal;

  const MyApp({super.key, required this.idMaquinaLocal});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: idMaquinaLocal.isEmpty
          ? const ConfigScreen(primerInicio: true)
          : BienvenidaScreen(idMaquinaLocal: idMaquinaLocal),
    );
  }
}
