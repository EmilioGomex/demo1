import 'package:flutter/material.dart';
import '../../supabase_manager.dart';
import 'tareas_screen.dart';
import 'bienvenida_screen.dart';

class SupervisorScreen extends StatefulWidget {
  final String nombreSupervisor;
  final String idMaquinaLocal;
  final String? fotoSupervisor;

  const SupervisorScreen({
    super.key,
    required this.nombreSupervisor,
    required this.idMaquinaLocal,
    this.fotoSupervisor,
  });

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  static const _accentGreen = Color(0xFF007A3D);
  static const _background = Color(0xFFF8FAFB);

  List<dynamic> maquinas = [];
  List<dynamic> operadores = [];
  String? maquinaSeleccionada;
  String? operadorSeleccionado;
  bool cargando = true;
  bool _errorCarga = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => cargando = true);

    try {
      final results = await Future.wait([
        SupabaseManager.client
            .from('maquinas')
            .select('id_maquina, nombre')
            .order('nombre'),
        SupabaseManager.client
            .from('operadores')
            .select('id_operador, nombreoperador, id_maquina')
            .neq('tipo', 'supervisor')
            .order('nombreoperador'),
      ]);

      setState(() {
        maquinas = results[0];
        operadores = results[1];
        cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando datos supervisor: $e');
      setState(() {
        cargando = false;
        _errorCarga = true;
      });
    }
  }

  void _irATareas() {
    final op = operadores.firstWhere(
      (o) => o['id_operador'] == operadorSeleccionado,
      orElse: () => {},
    );
    final idMaquina = op['id_maquina']?.toString() ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TareasScreen(
          idOperador: operadorSeleccionado!,
          idMaquinaLocal: idMaquina,
        ),
      ),
    );
  }

  List<dynamic> get _operadoresFiltrados => maquinaSeleccionada == null
      ? operadores
      : operadores.where((o) => o['id_maquina'] == maquinaSeleccionada).toList();

  Widget _buildSupervisorCard() {
    return Container(
      decoration: BoxDecoration(
        color: _accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 28),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _accentGreen,
            backgroundImage: (widget.fotoSupervisor != null &&
                    widget.fotoSupervisor!.isNotEmpty)
                ? NetworkImage(widget.fotoSupervisor!)
                : null,
            onBackgroundImageError: (_, __) {},
            child: (widget.fotoSupervisor == null ||
                    widget.fotoSupervisor!.isEmpty)
                ? const Icon(Icons.person, color: Colors.white, size: 32)
                : null,
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
                    color: _accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: _accentGreen, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Rol: Supervisor',
                        style: TextStyle(
                          fontSize: 13,
                          color: _accentGreen,
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
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required IconData icon,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: _background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: Icon(icon, color: _accentGreen),
        contentPadding: EdgeInsets.zero,
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        hint: Text(hint, style: const TextStyle(color: Colors.black45)),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _accentGreen,
        title: const Text('Supervisor', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal),
            ),
            (route) => false,
          ),
        ),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.black26),
                  const SizedBox(height: 16),
                  const Text(
                    'Error al cargar los datos',
                    style: TextStyle(fontSize: 18, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => _errorCarga = false);
                      _cargarDatos();
                    },
                  ),
                ],
              ),
            )
          : Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSupervisorCard(),
                        const SizedBox(height: 32),
                        const Text(
                          'Selecciona máquina',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _accentGreen,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDropdown<String>(
                          value: maquinaSeleccionada,
                          icon: Icons.precision_manufacturing,
                          hint: 'Todas las máquinas',
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                '— Todas las máquinas —',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                            ...maquinas.map<DropdownMenuItem<String>>((m) =>
                                DropdownMenuItem(
                                  value: m['id_maquina'],
                                  child: Text(m['nombre']),
                                )),
                          ],
                          onChanged: (value) => setState(() {
                            maquinaSeleccionada = value;
                            operadorSeleccionado = null;
                          }),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Selecciona operador',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _accentGreen,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDropdown<String>(
                          value: operadorSeleccionado,
                          icon: Icons.person,
                          hint: 'Selecciona un operador',
                          items: _operadoresFiltrados
                              .map<DropdownMenuItem<String>>((o) =>
                                  DropdownMenuItem(
                                    value: o['id_operador'],
                                    child: Text(o['nombreoperador']),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => operadorSeleccionado = value),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.search),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentGreen,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              elevation: 2,
                            ),
                            onPressed: operadorSeleccionado != null
                                ? _irATareas
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
