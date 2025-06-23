import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static const String supabaseUrl = 'https://czxyfzxjwzaykwoxyjah.supabase.co';
  static const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU';

  static final SupabaseClient client = Supabase.instance.client;
}
