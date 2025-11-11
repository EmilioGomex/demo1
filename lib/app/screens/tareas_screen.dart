import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../supabase_manager.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io'; // Importar para SocketException

class TareasScreen extends StatefulWidget {
  final String idOperador;

  const TareasScreen({super.key, required this.idOperador});

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

  Future<void> enviarWebhook(DateTime fecha, int estado, String operadorNombre) async {
    // ... (tu función de webhook, sin cambios)
    final url = Uri.parse(
        "https://prod-34.westeurope.logic.azure.com:443/workflows/78b16d627488439a9bd7f0d54129e613/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=PqLeUOugoiB9i6nbSJoqZVu_PQ5HzsseO8Bx49YE5oc");
    final timestamp = (fecha.millisecondsSinceEpoch / 1000).round();
    final body = {
      "fecha": timestamp,
      "estado": estado,
      "operador": operadorNombre,
    };
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 || response.statusCode == 202) {
        print("✅ Webhook enviado correctamente");
      } else {
        print("⚠️ Error al enviar webhook: ${response.statusCode}");
        print("Respuesta: ${response.body}");
      }
    } catch (e) {
      print("❌ Excepción al enviar webhook: $e");
    }
  }

  Future<void> _cargarDatos() async {
    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final operadorResp = await SupabaseManager.client
          .from('operadores')
          .select(
              'id_operador, nombreoperador, linea, id_maquina, maquinas (nombre)')
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

      // --- CORRECCIÓN 1: Usar la hora local para definir "hoy" ---
      final hoy = DateTime.now(); // <-- CAMBIO AQUÍ (quitado .toUtc())

      // 'inicioHoy' es hoy a las 00:00:00 en UTC (basado en tu día local)
      final inicioHoy =
          DateTime.utc(hoy.year, hoy.month, hoy.day).toIso8601String();
      // 'finHoy' es hoy a las 23:59:59 en UTC (basado en tu día local)
      final finHoy =
          DateTime.utc(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999)
              .toIso8601String();

      final filtroOperador =
          'id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)';

      final filtroEstado =
          'or(estado.in.("Pendiente","Atrasado"),and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy))';

      final tareasResponse = await SupabaseManager.client
          .from('registro_tareas')
          .select('''
            id, id_tarea, fecha_periodo, fecha_limite, estado, fecha_completado,
            
            tareas(nombre_tarea, frecuencia, tipo, es_compartida) 
          
          ''') // <-- CORRECCIÓN 2: CAMBIO AQUÍ (quitado !inner)
          .or(filtroOperador)
          .or(filtroEstado) // Esto está bien, se combinan con AND
          .order('fecha_limite', ascending: true)
          .execute();
      
      if (tareasResponse.status != 200 || tareasResponse.data == null) {
        setState(() {
          error = 'Error al cargar tareas. Por favor intenta de nuevo.';
          cargando = false;
        });
        return;
      }

      List<dynamic> tareasFiltradas = tareasResponse.data as List;

      setState(() {
        tareasAsignadas = tareasFiltradas;
        cargando = false;
      });
    } on SocketException catch (_) {
      setState(() {
        error = 'Error de red. Revisa tu conexión a internet.';
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = 'Error inesperado: $e';
        cargando = false;
      });
    }
  }

  Future<void> _verPasosTarea(
      Map<String, dynamic> registro, Map<String, dynamic>? tarea) async { // <-- Acepta tarea nula
    final operadorNombre = operador?['nombreoperador'] ?? 'Operador desconocido';
    
    // Webhook no bloqueante (sin cambios)
    enviarWebhook(DateTime.now(), 1, operadorNombre);

    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasosTareaScreen(
          idRegistro: registro['id'],
          idTarea: registro['id_tarea'],
          // --- CORRECCIÓN 3: Manejo de tarea nula ---
          nombreTarea: tarea?['nombre_tarea'] ?? 'Tarea no encontrada', // <-- CAMBIO AQUÍ
        ),
      ),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  // ... (tus funciones _colorFrecuencia, _iconoTipoTarea, _iconoEstado, _formatearFechaLimite no cambian) ...
  Color _colorFrecuencia(String? frecuencia) {
    switch (frecuencia?.toLowerCase()) {
      case 'diario': return Colors.red.shade200;
      case 'semanal': return const Color.fromARGB(255, 255, 222, 89);
      case 'quincenal': return Colors.lightBlue.shade200;
      case 'mensual': return Colors.green.shade200;
      case 'semestral': return const Color.fromARGB(255, 185, 165, 214); 
      default: return Colors.grey.shade300;
    }
  }
  Icon _iconoTipoTarea(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'limpieza': return Icon(Icons.cleaning_services, color: Colors.white, size: 28);
      case 'inspección': case 'inspeccion': return Icon(Icons.visibility, color: Colors.white, size: 28);
      case 'lubricación': case 'lubricacion': return Icon(Icons.oil_barrel, color: Colors.white, size: 28);
      case 'ajuste': return Icon(Icons.construction, color: Colors.white, size: 28);
      default: return Icon(Icons.visibility, color: Colors.white, size: 28);
    }
  }
  Icon _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado': return Icon(Icons.error_outline, color: Colors.redAccent, size: 28);
      case 'pendiente': return Icon(Icons.hourglass_top, color: Colors.grey.shade700, size: 28);
      case 'completado': return Icon(Icons.check_circle_outline, color: Colors.green, size: 28);
      default: return Icon(Icons.help_outline, color: Colors.grey.shade700, size: 28);
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
    // ... (tu lógica de build, appBar, etc. no cambia) ...
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
                                    final tarea = registro['tareas']; // Puede ser null ahora
                                    final estado = registro['estado'] ?? 'Pendiente';
                                    
                                    // --- CORRECCIÓN 4: Manejo de tarea nula ---
                                    final frecuencia = tarea?['frecuencia'] ?? 'Otro'; // <-- CAMBIO AQUÍ
                                    final tipo = tarea?['tipo'] ?? 'Otro'; // <-- CAMBIO AQUÍ
                                    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea Desconocida'; // <-- CAMBIO AQUÍ
                                    
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
                                          nombreTarea, // <-- Usar la variable segura
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

  // ... (tus widgets _infoItem y _sinTareasWidget no cambian) ...
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