import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../supabase_manager.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TareasScreen extends StatefulWidget {
  final String idOperador;
  final String idMaquinaLocal; // Necesario para saber a qué Home volver

  const TareasScreen({
    super.key,
    required this.idOperador,
    required this.idMaquinaLocal,
  });

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

  // --- CARGA DE DATOS Y LÓGICA PRINCIPAL ---
  Future<void> _cargarDatos() async {
    setState(() {
      cargando = true;
      error = null;
    });

    try {
      // 1. Obtener datos del operador
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

      // 2. Preparar filtros de fechas
      final hoy = DateTime.now();
      final inicioHoy = DateTime.utc(hoy.year, hoy.month, hoy.day).toIso8601String();
      final finHoy = DateTime.utc(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999).toIso8601String();

      // Filtro A: Tareas asignadas a ÉL -O- Tareas de la máquina SIN asignar
      final filtroOperador = 'id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)';
      
      // Filtro B: Estado Pendiente/Atrasado -O- Completado HOY
      final filtroEstado = 'or(estado.in.("Pendiente","Atrasado"),and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy))';

      // 3. Consultar Tareas
      final tareasResponse = await SupabaseManager.client
          .from('registro_tareas')
          .select('''
            id, id_tarea, fecha_periodo, fecha_limite, estado, fecha_completado, parsable_job_id,
            tareas(nombre_tarea, frecuencia, tipo, es_compartida) 
          ''')
          .or(filtroOperador)
          .or(filtroEstado)
          .order('fecha_limite', ascending: true)
          .execute();

      if (tareasResponse.status != 200 || tareasResponse.data == null) {
        setState(() {
          error = 'Error al cargar tareas.';
          cargando = false;
        });
        return;
      }

      final listaTareas = tareasResponse.data as List;

      setState(() {
        tareasAsignadas = listaTareas;
        cargando = false;
      });

      // 4. ACTUALIZAR SEMÁFORO (Solo con las tareas de este operador)
      _calcularYActualizarSemaforo(listaTareas);

    } catch (e) {
      setState(() {
        error = 'Error: $e';
        cargando = false;
      });
    }
  }

  // --- LÓGICA SEMÁFORO ---
  Future<void> _calcularYActualizarSemaforo(List<dynamic> tareasDelOperador) async {
    String nuevoColor = 'Verde'; // Por defecto
    
    final ahora = DateTime.now();
    final hoyInicio = DateTime(ahora.year, ahora.month, ahora.day);

    for (var registro in tareasDelOperador) {
      final estado = (registro['estado'] ?? 'Pendiente').toString();
      final fechaLimiteStr = registro['fecha_limite'];
      bool esAtrasado = false;

      // Detectar atraso real
      if (estado == 'Atrasado') {
        esAtrasado = true;
      } else if (estado == 'Pendiente' && fechaLimiteStr != null) {
        try {
          final fechaLimite = DateTime.parse(fechaLimiteStr).toLocal();
          final fechaLimiteDia = DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
          if (fechaLimiteDia.isBefore(hoyInicio)) {
            esAtrasado = true;
          }
        } catch (_) {}
      }

      // Prioridades
      if (esAtrasado) {
        nuevoColor = 'Rojo';
        break; // Prioridad máxima, salimos.
      } else if (nuevoColor != 'Rojo' && estado == 'Pendiente') {
        nuevoColor = 'Amarillo';
      }
    }

    // Actualizar BD (Dispara Trigger PowerBI)
    try {
      await SupabaseManager.client.from('semaforo_maquina').upsert({
        'id_maquina': widget.idMaquinaLocal,
        'estado': nuevoColor,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      }, onConflict: 'id_maquina');
      
      print("🚦 Semáforo actualizado a: $nuevoColor");
    } catch (e) {
      print("⚠️ Error actualizando semáforo: $e");
    }
  }

  // --- LÓGICA PARSABLE (API) ---
  Future<String?> _crearYPrepararJob(String linea, String tipo, String nombreTarea, String nombreOperador) async {
    final title = "CILT - $linea - $tipo - $nombreTarea";

    // Paso 1: Crear Job Modular
    final bodyCreate = {
      "method": "createModular",
      "arguments": {
        "params": {
          "skipPlanning": true,
          "typ": 0,
          "teamId": ParsableConfig.teamId,
          "title": title,
          "templateRefs": [ { "templateId": ParsableConfig.templateId } ],
          "users": [
            { "email": ParsableConfig.defaultEmail, "jobRoleId": ParsableConfig.jobRoleId }
          ],
          "attributes": [
            { "id": "24b32634-9e99-4d7c-a2ac-8fe23c5e0444", "values": [{ "id": "f8a92cac-fab8-4c63-966b-ff13dbd457b8" }] },
            { "id": "f4115da4-a62c-40f1-8fde-555ab4fb35bb", "values": [{ "id": "b2f259f9-18c0-457a-9158-ffa5e991637d" }] },
            { "id": "eeb9b86a-a293-460d-8316-56a25ae5c70c", "values": [{ "id": "a79fe6ce-9563-4efd-935d-a38fa555fbf9" }] }
          ]
        }
      }
    };

    try {
      print("🔵 Parsable: Creando Job...");
      final response = await http.post(
        Uri.parse('${ParsableConfig.apiUrl}/jobs'),
        headers: ParsableConfig.headers,
        body: jsonEncode(bodyCreate),
      );

      if (response.statusCode != 200) {
        print("❌ Error Creando Job: ${response.body}");
        return null;
      }

      final data = jsonDecode(response.body);
      final jobId = data['result']?['success']?['id'];
      print("✅ Job Creado ID: $jobId");

      // Paso 2: Obtener jobBaseStepId dinámicamente
      String? jobBaseStepId;
      try {
        final stepGroup = data['result']['success']['stepGroup'];
        jobBaseStepId = stepGroup['children'][0]['children'][0]['jobBaseStepId'];
      } catch (e) {
        print("⚠️ No se pudo extraer jobBaseStepId: $e");
      }

      // Paso 3: Llenar Nombre del Operador
      if (jobId != null && jobBaseStepId != null) {
        final bodyStep = {
          "method": "sendExecDataWithResult",
          "arguments": {
            "jobId": jobId,
            "execSnippets": [
              {
                "stepExecData": {
                  "stepId": ParsableConfig.stepIdNombre, 
                  "jobBaseStepId": jobBaseStepId,
                  "fieldExecutionData": [
                    {
                      "fieldId": ParsableConfig.fieldIdNombre,
                      "execData": { "text": nombreOperador },
                      "seqId": 1
                    }
                  ],
                  "stepComplete": true,
                  "isComplete": true
                }
              }
            ]
          }
        };

        await http.post(
           Uri.parse('${ParsableConfig.apiUrl}/jobs'),
           headers: ParsableConfig.headers,
           body: jsonEncode(bodyStep)
        );
        print("✅ Nombre enviado a Parsable.");
      }

      return jobId;

    } catch (e) {
      print("❌ Excepción Parsable: $e");
      return null;
    }
  }

  // --- NAVEGACIÓN ---
  Future<void> _procesarYNavigar(Map<String, dynamic> registro, Map<String, dynamic>? tarea) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFF007A3D))),
    );

    final operadorNombre = operador?['nombreoperador'] ?? 'Operador';
    final linea = operador?['linea'] ?? 'General';
    final tipo = tarea?['tipo'] ?? 'Tarea';
    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea sin nombre';

    String? parsableJobId = registro['parsable_job_id'];

    // Si no tiene Job, lo creamos
    if (parsableJobId == null) {
      parsableJobId = await _crearYPrepararJob(linea, tipo, nombreTarea, operadorNombre);
      
      if (parsableJobId != null) {
        await SupabaseManager.client
            .from('registro_tareas')
            .update({'parsable_job_id': parsableJobId})
            .eq('id', registro['id']);
      }
    }

    if (mounted) {
      Navigator.pop(context); // Cerrar loading

      final resultado = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PasosTareaScreen(
            idRegistro: registro['id'],
            idTarea: registro['id_tarea'],
            nombreTarea: nombreTarea,
            parsableJobId: parsableJobId,
          ),
        ),
      );

      // Si regresamos con éxito, recargamos (y recalculamos el semáforo)
      if (resultado == true) {
        _cargarDatos();
      }
    }
  }

  // --- HELPERS UI ---
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
      case 'limpieza': return const Icon(Icons.cleaning_services, color: Colors.white, size: 28);
      case 'inspección': case 'inspeccion': return const Icon(Icons.visibility, color: Colors.white, size: 28);
      case 'lubricación': case 'lubricacion': return const Icon(Icons.oil_barrel, color: Colors.white, size: 28);
      case 'ajuste': return const Icon(Icons.construction, color: Colors.white, size: 28);
      default: return const Icon(Icons.visibility, color: Colors.white, size: 28);
    }
  }

  Icon _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado': return const Icon(Icons.error_outline, color: Colors.redAccent, size: 28);
      case 'pendiente': return Icon(Icons.hourglass_top, color: Colors.grey.shade700, size: 28);
      case 'completado': return const Icon(Icons.check_circle_outline, color: Colors.green, size: 28);
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
    final Color accentGreen = const Color(0xFF007A3D);
    final background = const Color(0xFFF8FAFB);

    List<dynamic> tareasOrdenadas = List.from(tareasAsignadas);
    tareasOrdenadas.sort((a, b) {
      String estadoA = (a['estado'] ?? '').toString().toLowerCase();
      String estadoB = (b['estado'] ?? '').toString().toLowerCase();
      // Orden: Pendiente/Atrasado primero, Completado al final
      if ((estadoA == 'pendiente' || estadoA == 'atrasado') && estadoB == 'completado') return -1;
      if ((estadoB == 'pendiente' || estadoB == 'atrasado') && estadoA == 'completado') return 1;
      // Luego por fecha
      DateTime fechaA = DateTime.tryParse(a['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime fechaB = DateTime.tryParse(b['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return fechaA.compareTo(fechaB);
    });

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: accentGreen,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white, size: 28),
          onPressed: () {
            // Regresamos a la pantalla de bienvenida con la máquina correcta
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal)),
            );
          },
        ),
        title: Text(
          'Tareas de ${operador?['nombreoperador'] ?? 'Operador'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: cargando
          ? Center(child: CircularProgressIndicator(color: accentGreen))
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: Colors.redAccent)))
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
                      const SizedBox(height: 30),
                      const Text('Tareas asignadas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      tareasOrdenadas.isEmpty
                          ? _sinTareasWidget()
                          : Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(
                                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                                ),
                                child: ListView.builder(
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: tareasOrdenadas.length,
                                  itemBuilder: (context, index) {
                                    final registro = tareasOrdenadas[index];
                                    final tarea = registro['tareas'];
                                    final estado = registro['estado'] ?? 'Pendiente';
                                    final frecuencia = tarea?['frecuencia'] ?? 'Otro';
                                    final tipo = tarea?['tipo'] ?? 'Otro';
                                    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea Desconocida';
                                    final fechaLimite = _formatearFechaLimite(registro['fecha_limite']?.toString());
                                    final bool completado = estado.toLowerCase() == 'completado';

                                    return Card(
                                      color: Colors.white,
                                      elevation: 4,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      margin: const EdgeInsets.symmetric(vertical: 8),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          radius: 26,
                                          backgroundColor: _colorFrecuencia(frecuencia),
                                          child: _iconoTipoTarea(tipo),
                                        ),
                                        title: Text(nombreTarea,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                                decoration: completado ? TextDecoration.lineThrough : null,
                                                color: completado ? Colors.grey.shade600 : Colors.black87)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Frecuencia: $frecuencia',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    color: completado ? Colors.grey.shade600 : Colors.grey.shade700,
                                                    decoration: completado ? TextDecoration.lineThrough : null)),
                                            const SizedBox(height: 4),
                                            Text('Fecha límite: $fechaLimite',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    color: completado ? Colors.grey.shade600 : Colors.grey.shade700,
                                                    decoration: completado ? TextDecoration.lineThrough : null)),
                                          ],
                                        ),
                                        trailing: _iconoEstado(estado),
                                        onTap: () => _procesarYNavigar(registro, tarea),
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
        Icon(icon, color: const Color(0xFF007A3D), size: 28),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey.shade800)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
      ],
    );
  }

  Widget _sinTareasWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade300),
          const SizedBox(height: 20),
          Text('¡No hay tareas pendientes!',
              style: TextStyle(fontSize: 20, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Disfruta tu día', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// --- CONFIGURACIÓN PARSABLE (IDS ORIGINALES) ---
class ParsableConfig {
  static const String apiUrl = "https://api.eu-west-1.parsable.net/api";
  
  // TUS DATOS (Mantenidos intactos)
  static const String token = "Token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NTM5MDA2MDEsImlzcyI6ImF1dGg6cHJvZHVjdGlvbiIsInNlcmE6Y3J0ciI6IjY4NmI4M2ZlLWY3YmYtNDA3Ni1iZWJkLTUzNjM1YTgwZmNkNSIsInNlcmE6c2lkIjoiZjk4NDI5Y2MtYzBkMy00Y2VjLWI2YjctZjlmMmQ1ZjA3NmFiIiwic2VyYTp0ZWFtSWQiOiJhNDJlNzJkZC0zMzRhLTQzOTUtYjc2YS05ZDgxZjBjOGQyMTMiLCJzZXJhOnR5cCI6InBlcnNpc3RlbnQiLCJzdWIiOiIzYWYxYmU0NS0zOTQyLTQzZDEtOTVmZC1jMjg5NTQzMmVmMTcifQ.oyskbCMhYyLoSW_S2SLyGf7LdKoynMaRa8W8wTh6QDM";
  
  static const String teamId = "a42e72dd-334a-4395-b76a-9d81f0c8d213";
  static const String templateId = "7feea96e-f049-42a3-a652-dedd8c3c34c5";
  
  static const String stepIdNombre = "6846c276-d7ec-4d69-af72-0eea2a125cad";
  static const String fieldIdNombre = "db5ba0f0-62f1-47e5-9cb2-b27996ede80b";

  static const String defaultEmail = "gomeze44@heiway.net";
  static const String jobRoleId = "fc49020e-3c13-48ec-a29a-cd367fc89d18";

  static Map<String, String> get headers => {
    "Content-Type": "application/json",
    "accept": "application/json",
    "PARSABLE-CUSTOM-TOUCHSTONE": "heineken/heineken",
    "Authorization": token
  };
}