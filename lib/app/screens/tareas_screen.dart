import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../supabase_manager.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TareasScreen extends StatefulWidget {
  final String idOperador;
  final String idMaquinaLocal;

  const TareasScreen({
    super.key,
    required this.idOperador,
    required this.idMaquinaLocal,
  });

  @override
  State<TareasScreen> createState() => _TareasScreenState();
}

class _TareasScreenState extends State<TareasScreen> {
  static const _accentGreen = Color(0xFF007A3D);
  static const _background = Color(0xFFF8FAFB);

  Map<String, dynamic>? operador;
  List<dynamic> tareasOrdenadas = [];
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

      final hoy = DateTime.now();
      final inicioHoy = DateTime.utc(hoy.year, hoy.month, hoy.day).toIso8601String();
      final finHoy = DateTime.utc(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999).toIso8601String();

      final filtroOperador =
          'id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)';
      final filtroEstado =
          'or(estado.in.("Pendiente","Atrasado"),and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy))';

      final listaTareas = await SupabaseManager.client
          .from('registro_tareas')
          .select('''
            id, id_tarea, fecha_periodo, fecha_limite, estado, fecha_completado, parsable_job_id,
            tareas(nombre_tarea, frecuencia, tipo, es_compartida)
          ''')
          .or(filtroOperador)
          .or(filtroEstado)
          .order('fecha_limite', ascending: true) as List<dynamic>;

      setState(() {
        tareasOrdenadas = _ordenarTareas(listaTareas);
        cargando = false;
      });

      _calcularYActualizarSemaforo(listaTareas);
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        cargando = false;
      });
    }
  }

  List<dynamic> _ordenarTareas(List<dynamic> tareas) {
    final sorted = List<dynamic>.from(tareas);
    sorted.sort((a, b) {
      final estadoA = (a['estado'] ?? '').toString().toLowerCase();
      final estadoB = (b['estado'] ?? '').toString().toLowerCase();
      final aActivo = estadoA == 'pendiente' || estadoA == 'atrasado';
      final bActivo = estadoB == 'pendiente' || estadoB == 'atrasado';
      if (aActivo && !bActivo) return -1;
      if (!aActivo && bActivo) return 1;
      final fechaA = DateTime.tryParse(a['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final fechaB = DateTime.tryParse(b['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return fechaA.compareTo(fechaB);
    });
    return sorted;
  }

  Future<void> _calcularYActualizarSemaforo(List<dynamic> tareas) async {
    String nuevoColor = 'Verde';
    final ahora = DateTime.now();
    final hoyInicio = DateTime(ahora.year, ahora.month, ahora.day);

    for (final registro in tareas) {
      final estado = (registro['estado'] ?? 'Pendiente').toString();
      final fechaLimiteStr = registro['fecha_limite'];
      bool esAtrasado = estado == 'Atrasado';

      if (!esAtrasado && estado == 'Pendiente' && fechaLimiteStr != null) {
        try {
          final fl = DateTime.parse(fechaLimiteStr).toLocal();
          esAtrasado = DateTime(fl.year, fl.month, fl.day).isBefore(hoyInicio);
        } catch (_) {}
      }

      if (esAtrasado) {
        nuevoColor = 'Rojo';
        break;
      } else if (estado == 'Pendiente') {
        nuevoColor = 'Amarillo';
      }
    }

    try {
      await SupabaseManager.client.from('semaforo_maquina').upsert({
        'id_maquina': widget.idMaquinaLocal,
        'estado': nuevoColor,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      }, onConflict: 'id_maquina');
      debugPrint('Semáforo actualizado a: $nuevoColor');
    } catch (e) {
      debugPrint('Error actualizando semáforo: $e');
    }
  }

  Future<String?> _crearYPrepararJob(
      String linea, String tipo, String nombreTarea, String nombreOperador) async {
    final title = "CILT - $linea - $tipo - $nombreTarea";

    final bodyCreate = {
      "method": "createModular",
      "arguments": {
        "params": {
          "skipPlanning": true,
          "typ": 0,
          "teamId": ParsableConfig.teamId,
          "title": title,
          "templateRefs": [
            {"templateId": ParsableConfig.templateId}
          ],
          "users": [
            {"email": ParsableConfig.defaultEmail, "jobRoleId": ParsableConfig.jobRoleId}
          ],
          "attributes": [
            {
              "id": "24b32634-9e99-4d7c-a2ac-8fe23c5e0444",
              "values": [
                {"id": "f8a92cac-fab8-4c63-966b-ff13dbd457b8"}
              ]
            },
            {
              "id": "f4115da4-a62c-40f1-8fde-555ab4fb35bb",
              "values": [
                {"id": "b2f259f9-18c0-457a-9158-ffa5e991637d"}
              ]
            },
            {
              "id": "eeb9b86a-a293-460d-8316-56a25ae5c70c",
              "values": [
                {"id": "a79fe6ce-9563-4efd-935d-a38fa555fbf9"}
              ]
            }
          ]
        }
      }
    };

    try {
      debugPrint('Parsable: Creando Job "$title"...');
      final response = await http.post(
        Uri.parse('${ParsableConfig.apiUrl}/jobs'),
        headers: ParsableConfig.headers,
        body: jsonEncode(bodyCreate),
      );

      if (response.statusCode != 200) {
        debugPrint('Error creando Job: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      final jobId = data['result']?['success']?['id'];
      debugPrint('Job creado ID: $jobId');

      String? jobBaseStepId;
      try {
        final stepGroup = data['result']['success']['stepGroup'];
        jobBaseStepId = stepGroup['children'][0]['children'][0]['jobBaseStepId'];
      } catch (e) {
        debugPrint('No se pudo extraer jobBaseStepId: $e');
      }

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
                      "execData": {"text": nombreOperador},
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
          body: jsonEncode(bodyStep),
        );
        debugPrint('Nombre enviado a Parsable.');
      }

      return jobId;
    } catch (e) {
      debugPrint('Excepción Parsable: $e');
      return null;
    }
  }

  Future<void> _procesarYNavigar(
      Map<String, dynamic> registro, Map<String, dynamic>? tarea) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _accentGreen)),
    );

    final operadorNombre = operador?['nombreoperador'] ?? 'Operador';
    final linea = operador?['linea'] ?? 'General';
    final tipo = tarea?['tipo'] ?? 'Tarea';
    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea sin nombre';

    String? parsableJobId = registro['parsable_job_id'];

    if (parsableJobId == null) {
      parsableJobId = await _crearYPrepararJob(linea, tipo, nombreTarea, operadorNombre);
      if (parsableJobId != null) {
        await SupabaseManager.client
            .from('registro_tareas')
            .update({'parsable_job_id': parsableJobId}).eq('id', registro['id']);
      }
    }

    if (mounted) {
      Navigator.pop(context);
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
      if (resultado == true) _cargarDatos();
    }
  }

  Color _colorFrecuencia(String? frecuencia) {
    switch (frecuencia?.toLowerCase()) {
      case 'diario':     return Colors.red.shade200;
      case 'semanal':    return const Color.fromARGB(255, 255, 222, 89);
      case 'quincenal':  return Colors.lightBlue.shade200;
      case 'mensual':    return Colors.green.shade200;
      case 'semestral':  return const Color.fromARGB(255, 185, 165, 214);
      default:           return Colors.grey.shade300;
    }
  }

  Icon _iconoTipoTarea(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'limpieza':
        return const Icon(Icons.cleaning_services, color: Colors.white, size: 28);
      case 'inspección':
      case 'inspeccion':
        return const Icon(Icons.visibility, color: Colors.white, size: 28);
      case 'lubricación':
      case 'lubricacion':
        return const Icon(Icons.oil_barrel, color: Colors.white, size: 28);
      case 'ajuste':
        return const Icon(Icons.construction, color: Colors.white, size: 28);
      default:
        return const Icon(Icons.visibility, color: Colors.white, size: 28);
    }
  }

  Icon _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'atrasado':
        return const Icon(Icons.error_outline, color: Colors.redAccent, size: 28);
      case 'pendiente':
        return Icon(Icons.hourglass_top, color: Colors.grey.shade700, size: 28);
      case 'completado':
        return const Icon(Icons.check_circle_outline, color: Colors.green, size: 28);
      default:
        return Icon(Icons.help_outline, color: Colors.grey.shade700, size: 28);
    }
  }

  String _formatearFechaLimite(String? raw) {
    if (raw == null) return '-';
    try {
      final fechaLimite = DateTime.parse(raw).toLocal();
      final ahora = DateTime.now();
      final fl = DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
      final hoy = DateTime(ahora.year, ahora.month, ahora.day);
      final diff = fl.difference(hoy).inDays;
      if (diff < 0) {
        final d = diff.abs();
        return 'Venció hace $d día${d > 1 ? 's' : ''}';
      }
      if (diff == 0) return 'Vence hoy';
      if (diff == 1) return 'Vence mañana';
      return 'Vence en $diff días';
    } catch (_) {
      return raw.split('T')[0];
    }
  }

  Widget _buildTareaCard(Map<String, dynamic> registro) {
    final tarea = registro['tareas'] as Map<String, dynamic>?;
    final estado = registro['estado'] ?? 'Pendiente';
    final frecuencia = tarea?['frecuencia'] ?? 'Otro';
    final tipo = tarea?['tipo'] ?? 'Otro';
    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea Desconocida';
    final fechaLimite = _formatearFechaLimite(registro['fecha_limite']?.toString());
    final completado = estado.toString().toLowerCase() == 'completado';
    final subtitleColor = completado ? Colors.grey.shade600 : Colors.grey.shade700;
    final subtitleDecoration = completado ? TextDecoration.lineThrough : null;

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
        title: Text(
          nombreTarea,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            decoration: subtitleDecoration,
            color: completado ? Colors.grey.shade600 : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frecuencia: $frecuencia',
              style: TextStyle(fontSize: 14, color: subtitleColor, decoration: subtitleDecoration),
            ),
            const SizedBox(height: 4),
            Text(
              'Fecha límite: $fechaLimite',
              style: TextStyle(fontSize: 14, color: subtitleColor, decoration: subtitleDecoration),
            ),
          ],
        ),
        trailing: _iconoEstado(estado),
        onTap: () => _procesarYNavigar(registro, tarea),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
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
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: _accentGreen, size: 28),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey.shade800)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
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
          Text(
            '¡No hay tareas pendientes!',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Disfruta tu día', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _accentGreen,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white, size: 28),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal),
            ),
          ),
        ),
        title: Text(
          'Tareas de ${operador?['nombreoperador'] ?? 'Operador'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator(color: _accentGreen))
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 30),
                      const Text(
                        'Tareas asignadas',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      tareasOrdenadas.isEmpty
                          ? _sinTareasWidget()
                          : Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                  },
                                ),
                                child: ListView.builder(
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: tareasOrdenadas.length,
                                  itemBuilder: (_, index) =>
                                      _buildTareaCard(tareasOrdenadas[index]),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }
}

// --- CONFIGURACIÓN PARSABLE ---
class ParsableConfig {
  static const String apiUrl = "https://api.eu-west-1.parsable.net/api";
  static const String token =
      "Token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NTM5MDA2MDEsImlzcyI6ImF1dGg6cHJvZHVjdGlvbiIsInNlcmE6Y3J0ciI6IjY4NmI4M2ZlLWY3YmYtNDA3Ni1iZWJkLTUzNjM1YTgwZmNkNSIsInNlcmE6c2lkIjoiZjk4NDI5Y2MtYzBkMy00Y2VjLWI2YjctZjlmMmQ1ZjA3NmFiIiwic2VyYTp0ZWFtSWQiOiJhNDJlNzJkZC0zMzRhLTQzOTUtYjc2YS05ZDgxZjBjOGQyMTMiLCJzZXJhOnR5cCI6InBlcnNpc3RlbnQiLCJzdWIiOiIzYWYxYmU0NS0zOTQyLTQzZDEtOTVmZC1jMjg5NTQzMmVmMTcifQ.oyskbCMhYyLoSW_S2SLyGf7LdKoynMaRa8W8wTh6QDM";
  static const String teamId = "a42e72dd-334a-4395-b76a-9d81f0c8d213";
  static const String templateId = "7feea96e-f049-42a3-a652-dedd8c3c34c5";
  static const String stepIdNombre = "6846c276-d7ec-4d69-af72-0eea2a125cad";
  static const String fieldIdNombre = "db5ba0f0-62f1-47e5-9cb2-b27996ede80b";
  static const String defaultEmail = "gomeze44@heiway.net";
  static const String jobRoleId = "fc49020e-3c13-48ec-a29a-cd367fc89d18";

  static const Map<String, String> headers = {
    "Content-Type": "application/json",
    "accept": "application/json",
    "PARSABLE-CUSTOM-TOUCHSTONE": "heineken/heineken",
    "Authorization": token,
  };
}
