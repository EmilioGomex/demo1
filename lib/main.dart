import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/screens/bienvenida_screen.dart'; // Asegúrate de que la ruta sea correcta según tu estructura de carpetas

const supabaseUrl = 'https://czxyfzxjwzaykwoxyjah.supabase.co';
// Usando la clave que proporcionaste
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      // Aquí definimos que ESTA tablet es la máquina 9183
      home: BienvenidaScreen(idMaquinaLocal: '9183'),
    );
  }
}