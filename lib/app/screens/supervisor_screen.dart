import 'package:flutter/material.dart';
import '../../supabase_manager.dart';
import 'tareas_screen.dart';
import 'bienvenida_screen.dart';

class SupervisorScreen extends StatefulWidget {
  final String nombreSupervisor;
  final String tipo;

  const SupervisorScreen({
    Key? key,
    required this.nombreSupervisor,
    required this.tipo,
  }) : super(key: key);

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  List<dynamic> maquinas = [];
  List<dynamic> operadores = [];
  String? maquinaSeleccionada;
  String? operadorSeleccionado;
  bool cargando = true;

  final Color accentGreen = const Color(0xFF007A3D);
  final Color background = const Color(0xFFF8FAFB);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() { cargando = true; });

    final maquinasResp = await SupabaseManager.client
        .from('maquinas')
        .select('id_maquina, nombre')
        .order('nombre')
        .execute();

    final operadoresResp = await SupabaseManager.client
        .from('operadores')
        .select('id_operador, nombreoperador, id_maquina')
        .order('nombreoperador')
        .execute();

    setState(() {
      maquinas = maquinasResp.data ?? [];
      operadores = operadoresResp.data ?? [];
      cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: accentGreen,
        title: const Text('Supervisor', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const BienvenidaScreen()),
              (route) => false,
            );
          },
        ),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: accentGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 28),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: accentGreen,
                                child: const Icon(Icons.person, color: Colors.white, size: 32),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.nombreSupervisor,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF222222),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentGreen.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.verified_user, color: Color(0xFF007A3D), size: 16),
                                          SizedBox(width: 4),
                                          Text(
                                            'Rol: Supervisor',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF007A3D),
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text('Selecciona máquina', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: accentGreen)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: Icon(Icons.precision_manufacturing, color: accentGreen),
                          ),
                          value: maquinaSeleccionada,
                          items: maquinas.map<DropdownMenuItem<String>>((m) {
                            return DropdownMenuItem(
                              value: m['id_maquina'],
                              child: Text(m['nombre']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              maquinaSeleccionada = value;
                              operadorSeleccionado = null;
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        Text('Selecciona operador', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: accentGreen)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: Icon(Icons.person, color: accentGreen),
                          ),
                          value: operadorSeleccionado,
                          items: operadores
                              .where((o) => maquinaSeleccionada == null || o['id_maquina'] == maquinaSeleccionada)
                              .map<DropdownMenuItem<String>>((o) {
                                return DropdownMenuItem(
                                  value: o['id_operador'],
                                  child: Text(o['nombreoperador']),
                                );
                              }).toList(),
                          onChanged: (value) {
                            setState(() {
                              operadorSeleccionado = value;
                            });
                          },
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.search),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              elevation: 2,
                            ),
                            onPressed: maquinaSeleccionada != null && operadorSeleccionado != null
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TareasScreen(
                                          idOperador: operadorSeleccionado!,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            label: const Text('Ver tareas del operador'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}