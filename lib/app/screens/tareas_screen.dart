import 'package:flutter/material.dart';
import '../../supabase_manager.dart';
import 'package:intl/intl.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart'; // Asegúrate de importar tu pantalla de bienvenida

class TareasScreen extends StatefulWidget {
  final String idOperador;

  const TareasScreen({Key? key, required this.idOperador}) : super(key: key);

  @override
  _TareasScreenState createState() => _TareasScreenState();
}

class _TareasScreenState extends State<TareasScreen> {
  Map<String, dynamic>? operador;
  List<dynamic> tareasAsignadas = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final operadorResp = await SupabaseManager.client
          .from('operadores')
          .select('id_operador, nombreoperador, linea, id_maquina, maquinas (nombre)')
          .eq('id_operador', widget.idOperador)
          .maybeSingle();

      if (operadorResp == null) {
        setState(() {
          error = 'Operador no encontrado.';
          cargando = false;
        });
        return;
      }

      operador = operadorResp;
      final idMaquina = operador!['id_maquina'] ?? '';

      final tareasResponse = await SupabaseManager.client
          .from('registro_tareas')
          .select('''
            id, id_tarea, fecha_periodo, fecha_limite, estado,
            tareas!inner(nombre_tarea, frecuencia, es_compartida)
          ''')
          .or('id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)')
          .in_('estado', ['Pendiente', 'Atrasado'])
          .order('fecha_limite', ascending: true)
          .execute();

      if (tareasResponse.status != 200 || tareasResponse.data == null) {
        setState(() {
          error = 'Error al cargar tareas.';
          cargando = false;
        });
        return;
      }

      tareasAsignadas = tareasResponse.data as List;

      setState(() {
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = 'Error inesperado: $e';
        cargando = false;
      });
    }
  }

  Future<void> _verPasosTarea(Map<String, dynamic> registro, Map<String, dynamic> tarea) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasosTareaScreen(
          idRegistro: registro['id'],
          idTarea: registro['id_tarea'],
          nombreTarea: tarea['nombre_tarea'] ?? 'Tarea',
        ),
      ),
    );
    if (resultado == true) {
      _cargarDatos();
    }
  }

  Color _colorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado':
        return Colors.redAccent.shade100;
      case 'pendiente':
        return Colors.grey.shade200;
      case 'completado':
        return Colors.green.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  Icon _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado':
        return Icon(Icons.error_outline, color: Colors.redAccent, size: 30);
      case 'pendiente':
        return Icon(Icons.schedule_outlined, color: Colors.grey.shade700, size: 28);
      case 'completado':
        return Icon(Icons.check_circle_outline, color: Colors.green, size: 30);
      default:
        return Icon(Icons.help_outline, color: Colors.grey.shade700, size: 28);
    }
  }

  String _formatearFechaLimite(String fechaLimiteRaw) {
    try {
      final fechaLimite = DateTime.parse(fechaLimiteRaw).toLocal();
      final ahora = DateTime.now();
      final diferencia = fechaLimite.difference(DateTime(ahora.year, ahora.month, ahora.day)).inDays;

      if (diferencia < 0) {
        final diasAtraso = diferencia.abs();
        return 'Venció hace $diasAtraso día${diasAtraso > 1 ? 's' : ''}';
      } else if (diferencia == 0) {
        return 'Vence hoy';
      } else if (diferencia == 1) {
        return 'Vence mañana';
      } else {
        return 'Vence en $diferencia días';
      }
    } catch (e) {
      return fechaLimiteRaw.split('T')[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accentGreen = Color(0xFF007A3D);
    final background = Color(0xFFF8FAFB);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: accentGreen,
        leading: IconButton(
          icon: Icon(Icons.home, size: 28),
          tooltip: 'Volver a Inicio',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => BienvenidaScreen()),
            );
          },
        ),
        title: Text(
          'Tareas de ${operador?['nombreoperador'] ?? 'Operador'}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
        elevation: 4,
      ),
      body: cargando
          ? Center(child: CircularProgressIndicator(color: accentGreen))
          : error != null
              ? Center(
                  child: Text(error!,
                      style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        color: Colors.green.shade50,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _infoItem(Icons.person, 'Operador', operador?['nombreoperador'] ?? '-'),
                              _infoItem(Icons.factory, 'Máquina', operador?['maquinas']?['nombre'] ?? '-'),
                              _infoItem(Icons.line_weight, 'Línea', operador?['linea'] ?? '-'),
                              _infoItem(Icons.work, 'Rol', 'Operador'),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 30),
                      Text(
                        'Tareas pendientes',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      SizedBox(height: 16),
                      Expanded(
                        child: tareasAsignadas.isEmpty
                            ? _sinTareasWidget()
                            : ListView.builder(
                                physics: AlwaysScrollableScrollPhysics(),
                                itemCount: tareasAsignadas.length,
                                itemBuilder: (context, index) {
                                  final registro = tareasAsignadas[index];
                                  final tarea = registro['tareas'];
                                  final estado = registro['estado'] ?? 'Pendiente';
                                  final fechaLimiteRaw = registro['fecha_limite']?.toString() ?? '-';
                                  final fechaLimite = _formatearFechaLimite(fechaLimiteRaw);

                                  return Card(
                                    color: _colorEstado(estado),
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                    margin: EdgeInsets.symmetric(vertical: 8),
                                    child: ListTile(
                                      leading: _iconoEstado(estado),
                                      title: Text(
                                        tarea['nombre_tarea'] ?? 'Sin nombre',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18),
                                      ),
                                      subtitle: Text(
                                        'Frecuencia: ${tarea['frecuencia'] ?? '-'}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Fecha límite',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w600),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            fechaLimite,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: estado.toLowerCase() == 'atrasado'
                                                    ? Colors.redAccent
                                                    : Colors.black87),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _verPasosTarea(registro, tarea),
                                    ),
                                  );
                                },
                              ),
                      )
                    ],
                  ),
                ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Color(0xFF007A3D), size: 28),
        SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.grey.shade800)),
        SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87)),
      ],
    );
  }

  Widget _sinTareasWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade300),
          SizedBox(height: 20),
          Text(
            '¡No hay tareas pendientes!',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Disfruta tu día',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
