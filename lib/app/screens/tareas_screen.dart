import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../supabase_manager.dart';
import '../../config/parsable_secrets.dart';
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
          .select('id_operador, nombreoperador, linea, id_maquina, foto_operador, maquinas (nombre)')
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
      final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day).toUtc().toIso8601String();
      final finHoy = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999).toUtc().toIso8601String();

      final filtroOperador =
          'id_operador.eq.${widget.idOperador},and(id_operador.is.null,id_maquina.eq.$idMaquina)';
      final filtroEstado =
          'or(estado.in.("Pendiente","Atrasado"),and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy))';

      final listaTareas = await SupabaseManager.client
          .from('registro_tareas')
          .select('''
            id, id_tarea, fecha_periodo, fecha_limite, estado, fecha_completado, parsable_job_id, motivo_bloqueo,
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
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
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
      ).timeout(const Duration(seconds: 15));

      debugPrint('Parsable create → HTTP ${response.statusCode}: ${response.body}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Error creando Job (${response.statusCode}): ${response.body}');
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

        final stepResponse = await http.post(
          Uri.parse('${ParsableConfig.apiUrl}/jobs'),
          headers: ParsableConfig.headers,
          body: jsonEncode(bodyStep),
        ).timeout(const Duration(seconds: 15));
        debugPrint('Parsable sendExecData → HTTP ${stepResponse.statusCode}: ${stepResponse.body}');
      }

      return jobId;
    } catch (e) {
      debugPrint('Excepción Parsable: $e');
      return null;
    }
  }

  Future<void> _confirmarReapertura(
      Map<String, dynamic> registro, Map<String, dynamic>? tarea) async {
    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tarea completada'),
        content: Text('«$nombreTarea» ya fue completada.\n¿Deseas reabrirla?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, reabrir'),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) {
      _procesarYNavigar(registro, tarea, estaCompletado: true);
    }
  }

  Future<void> _procesarYNavigar(
      Map<String, dynamic> registro, Map<String, dynamic>? tarea,
      {bool estaCompletado = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _accentGreen),
                SizedBox(height: 16),
                Text(
                  'Preparando tarea...',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
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
            estaCompletado: estaCompletado,
          ),
        ),
      );
      if (resultado == true && mounted) _cargarDatos();
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
        return const Icon(Icons.task_alt, color: Colors.white, size: 28);
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

  String _formatearFechaCompletado(String? raw) {
    if (raw == null) return '';
    try {
      final fecha = DateTime.parse(raw).toLocal();
      final ahora = DateTime.now();
      final esHoy = fecha.year == ahora.year &&
          fecha.month == ahora.month &&
          fecha.day == ahora.day;
      final hora =
          '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
      return esHoy ? 'Completado hoy a las $hora' : 'Completado el ${fecha.day}/${fecha.month} a las $hora';
    } catch (_) {
      return '';
    }
  }

  Widget _motivoChip(String motivo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 13, color: Colors.orange.shade700),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Aplazada: $motivo',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTareaCard(Map<String, dynamic> registro) {
    final tarea = registro['tareas'] as Map<String, dynamic>?;
    final estado = registro['estado'] ?? 'Pendiente';
    final frecuencia = tarea?['frecuencia'] ?? 'Otro';
    final tipo = tarea?['tipo'] ?? 'Otro';
    final nombreTarea = tarea?['nombre_tarea'] ?? 'Tarea Desconocida';
    final completado = estado.toString().toLowerCase() == 'completado';
    final motivo = registro['motivo_bloqueo']?.toString();
    final subtitleColor = completado ? Colors.grey.shade500 : Colors.grey.shade700;
    final subtitleDecoration = completado ? TextDecoration.lineThrough : null;

    final segundaLinea = completado
        ? _formatearFechaCompletado(registro['fecha_completado']?.toString())
        : 'Fecha límite: ${_formatearFechaLimite(registro['fecha_limite']?.toString())}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: completado ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: completado
                ? () => _confirmarReapertura(registro, tarea)
                : () => _procesarYNavigar(registro, tarea),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: completado
                        ? Colors.grey.shade300
                        : _colorFrecuencia(frecuencia),
                    child: _iconoTipoTarea(tipo),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                nombreTarea,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  decoration: subtitleDecoration,
                                  color: completado
                                      ? Colors.grey.shade500
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _iconoEstado(estado),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Frecuencia: $frecuencia',
                          style: TextStyle(
                              fontSize: 13,
                              color: subtitleColor,
                              decoration: subtitleDecoration),
                        ),
                        if (segundaLinea.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            segundaLinea,
                            style: TextStyle(
                              fontSize: 13,
                              color: completado
                                  ? Colors.green.shade600
                                  : subtitleColor,
                              decoration: completado ? null : subtitleDecoration,
                              fontWeight: completado
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                        if (!completado && motivo != null && motivo.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _motivoChip(motivo),
                        ],
                      ],
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

  Widget _buildInfoCard() {
    final nombre = operador?['nombreoperador'] ?? '-';
    final maquina = operador?['maquinas']?['nombre'] ?? '-';
    final linea = operador?['linea'] ?? '-';
    final foto = operador?['foto_operador']?.toString() ?? '';

    return Card(
      color: Colors.green.shade50,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: _accentGreen,
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              onBackgroundImageError: foto.isNotEmpty ? (_, __) {} : null,
              child: foto.isEmpty
                  ? const Icon(Icons.person, color: Colors.white, size: 38)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.factory, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        maquina,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.line_weight, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Línea $linea',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildResumenTareas(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, int> get _resumenTareas {
    int pendientes = 0, atrasadas = 0, completadas = 0;
    for (final r in tareasOrdenadas) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      if (estado == 'completado') { completadas++; }
      else if (estado == 'atrasado') { atrasadas++; }
      else { pendientes++; }
    }
    return {'pendientes': pendientes, 'atrasadas': atrasadas, 'completadas': completadas};
  }

  Widget _buildResumenTareas() {
    final r = _resumenTareas;
    final parts = <Widget>[];

    if (r['atrasadas']! > 0) {
      parts.add(_resumenChip(
        '${r['atrasadas']} atrasada${r['atrasadas']! > 1 ? 's' : ''}',
        Colors.red.shade600,
        Colors.red.shade50,
      ));
    }
    if (r['pendientes']! > 0) {
      parts.add(_resumenChip(
        '${r['pendientes']} pendiente${r['pendientes']! > 1 ? 's' : ''}',
        Colors.orange.shade700,
        Colors.orange.shade50,
      ));
    }
    if (r['completadas']! > 0) {
      parts.add(_resumenChip(
        '${r['completadas']} completada${r['completadas']! > 1 ? 's' : ''}',
        Colors.green.shade700,
        Colors.green.shade50,
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 4, children: parts);
  }

  Widget _resumenChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
      ),
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.red.shade400, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Heineken - ECILT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator(color: _accentGreen))
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _cargarDatos,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text(
                            'Tareas asignadas',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: tareasOrdenadas.isEmpty
                            ? RefreshIndicator(
                                color: _accentGreen,
                                onRefresh: _cargarDatos,
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: SizedBox(
                                    height: 400,
                                    child: _sinTareasWidget(),
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                color: _accentGreen,
                                onRefresh: _cargarDatos,
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context).copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                    },
                                  ),
                                  child: ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    cacheExtent: 400,
                                    itemCount: tareasOrdenadas.length,
                                    itemBuilder: (_, index) => RepaintBoundary(
                                      child: _buildTareaCard(tareasOrdenadas[index]),
                                    ),
                                  ),
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
  static const String teamId = "a42e72dd-334a-4395-b76a-9d81f0c8d213";
  static const String templateId = "7feea96e-f049-42a3-a652-dedd8c3c34c5";
  static const String stepIdNombre = "6846c276-d7ec-4d69-af72-0eea2a125cad";
  static const String fieldIdNombre = "db5ba0f0-62f1-47e5-9cb2-b27996ede80b";
  static const String jobRoleId = "fc49020e-3c13-48ec-a29a-cd367fc89d18";

  // Credenciales en archivo separado (gitignored)
  static const String token = ParsableSecrets.token;
  static const String defaultEmail = ParsableSecrets.defaultEmail;

  static const Map<String, String> headers = {
    "Content-Type": "application/json",
    "accept": "application/json",
    "PARSABLE-CUSTOM-TOUCHSTONE": "heineken/heineken",
    "Authorization": token,
  };
}
