import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../supabase_manager.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart';

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
            id, id_tarea, fecha_periodo, fecha_limite, estado, fecha_completado,
            tareas!inner(nombre_tarea, frecuencia, tipo, es_compartida)
          ''')
          .or('id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)')
          .order('fecha_limite', ascending: true)
          .execute();

      if (tareasResponse.status != 200 || tareasResponse.data == null) {
        setState(() {
          error = 'Error al cargar tareas.';
          cargando = false;
        });
        return;
      }

      List<dynamic> todasTareas = tareasResponse.data as List;

      final hoy = DateTime.now().toUtc();
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

      List<dynamic> tareasFiltradas = todasTareas.where((tarea) {
        final estado = (tarea['estado'] ?? '').toString().toLowerCase();
        if (estado == 'pendiente' || estado == 'atrasado') {
          return true;
        }
        if (estado == 'completado') {
          final fechaCompletadoRaw = tarea['fecha_completado'];
          if (fechaCompletadoRaw == null) return false;
          final fechaCompletado = DateTime.parse(fechaCompletadoRaw).toUtc();
          final fechaCompletadoSinHora = DateTime(fechaCompletado.year, fechaCompletado.month, fechaCompletado.day);
          return fechaCompletadoSinHora.year == hoySinHora.year &&
                 fechaCompletadoSinHora.month == hoySinHora.month &&
                 fechaCompletadoSinHora.day == hoySinHora.day;
        }
        return false;
      }).toList();

      setState(() {
        tareasAsignadas = tareasFiltradas;
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

  Color _colorFrecuencia(String? frecuencia) {
    switch (frecuencia?.toLowerCase()) {
      case 'diario':
        return Colors.red.shade200;
      case 'semanal':
        return const Color.fromARGB(255, 255, 222, 89);
      case 'quincenal':
        return Colors.lightBlue.shade200;
      case 'mensual':
        return Colors.green.shade200;
      case 'semestral':
        return const Color.fromARGB(255, 185, 165, 214);  
      default:
        return Colors.grey.shade300;
    }
  }

Icon _iconoTipoTarea(String? tipo) {
  switch (tipo?.toLowerCase()) {
    case 'limpieza':
      return Icon(Icons.cleaning_services, color: Colors.white, size: 28);
    case 'inspección':
    case 'inspeccion':
      return Icon(Icons.visibility, color: Colors.white, size: 28);
    case 'lubricación':
    case 'lubricacion':
      return Icon(Icons.oil_barrel, color: Colors.white, size: 28);
    case 'ajuste':
      return Icon(Icons.construction, color: Colors.white, size: 28);
    default:
      return Icon(Icons.visibility, color: Colors.white, size: 28);
  }
}


  Icon _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado':
        return Icon(Icons.error_outline, color: Colors.redAccent, size: 28);
      case 'pendiente':
        return Icon(Icons.hourglass_top, color: Colors.grey.shade700, size: 28);
      case 'completado':
        return Icon(Icons.check_circle_outline, color: Colors.green, size: 28);
      default:
        return Icon(Icons.help_outline, color: Colors.grey.shade700, size: 28);
    }
  }

String _formatearFechaLimite(String? fechaLimiteRaw) {
  if (fechaLimiteRaw == null) return '-';
  try {
    final fechaLimite = DateTime.parse(fechaLimiteRaw).toLocal();
    final ahora = DateTime.now();

    final fechaLimiteSinHora = DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
    final ahoraSinHora = DateTime(ahora.year, ahora.month, ahora.day);

    final diferencia = fechaLimiteSinHora.difference(ahoraSinHora).inDays;

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

    List<dynamic> tareasOrdenadas = List.from(tareasAsignadas);
    tareasOrdenadas.sort((a, b) {
      String estadoA = (a['estado'] ?? '').toString().toLowerCase();
      String estadoB = (b['estado'] ?? '').toString().toLowerCase();

      if ((estadoA == 'pendiente' || estadoA == 'atrasado') && estadoB == 'completado') return -1;
      if ((estadoB == 'pendiente' || estadoB == 'atrasado') && estadoA == 'completado') return 1;

      DateTime fechaA = DateTime.tryParse(a['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime fechaB = DateTime.tryParse(b['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return fechaA.compareTo(fechaB);
    });

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: accentGreen,
        leading: IconButton(
          icon: Icon(Icons.home,color: Colors.white, size: 28),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        centerTitle: true,
        elevation: 4,
      ),
      body: cargando
          ? Center(child: CircularProgressIndicator(color: accentGreen))
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: Colors.redAccent, fontSize: 16)))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        color: Colors.green.shade50,
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
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
                      Text('Tareas asignadas',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                      SizedBox(height: 16),
                      tareasOrdenadas.isEmpty
                          ? _sinTareasWidget()
                          : Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.trackpad,
                                  },
                                ),
                                child: ListView.builder(
                                  physics: ClampingScrollPhysics(),
                                  itemCount: tareasOrdenadas.length,
                                  itemBuilder: (context, index) {
                                    final registro = tareasOrdenadas[index];
                                    final tarea = registro['tareas'];
                                    final estado = registro['estado'] ?? 'Pendiente';
                                    final frecuencia = tarea['frecuencia'] ?? 'Otro';
                                    final tipo = tarea['tipo'] ?? 'Otro';
                                    final fechaLimiteRaw = registro['fecha_limite']?.toString();
                                    final fechaLimite = _formatearFechaLimite(fechaLimiteRaw);

                                    final bool completado = estado.toLowerCase() == 'completado';

                                    return Card(
                                      color: Colors.white,
                                      elevation: 4,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      margin: EdgeInsets.symmetric(vertical: 8),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          radius: 26,
                                          backgroundColor: _colorFrecuencia(frecuencia),
                                          child: _iconoTipoTarea(tipo),
                                        ),
                                        title: Text(
                                          tarea['nombre_tarea'] ?? 'Sin nombre',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            decoration:
                                                completado ? TextDecoration.lineThrough : null,
                                            color: completado ? Colors.grey.shade600 : Colors.black87,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Frecuencia: $frecuencia',
                                              style: TextStyle(
                                                color: completado ? Colors.grey.shade600 : Colors.grey.shade700,
                                                fontSize: 14,
                                                decoration:
                                                    completado ? TextDecoration.lineThrough : null,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Fecha límite: $fechaLimite',
                                              style: TextStyle(
                                                color: completado ? Colors.grey.shade600 : Colors.grey.shade700,
                                                fontSize: 14,
                                                decoration:
                                                    completado ? TextDecoration.lineThrough : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: _iconoEstado(estado),
                                        onTap: () => _verPasosTarea(registro, tarea),
                                      ),
                                    );
                                  },
                                ),
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
          Text('¡No hay tareas pendientes!',
              style: TextStyle(fontSize: 20, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Disfruta tu día', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
