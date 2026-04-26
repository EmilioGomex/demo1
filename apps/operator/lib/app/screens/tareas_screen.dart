import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../supabase_manager.dart';
import '../utils/app_routes.dart';
import '../widgets/inactivity_wrapper.dart';
import '../../config/parsable_secrets.dart';
import 'pasos_tarea_screen.dart';
import 'bienvenida_screen.dart';
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import '../utils/time_manager.dart';

// Retorna la fecha actual del dispositivo controlada por TimeManager
DateTime get mockNow => TimeManager.now();

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
  List<dynamic> tareasHoy = [];
  List<dynamic> tareasFuturas = [];
  List<dynamic> tareasCompletadas = [];
  bool cargando = true;
  String? error;
  String _nombresMaquinas = '-';

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
      final hoy = mockNow;
      final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day).toUtc().toIso8601String();
      final finHoy = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999).toUtc().toIso8601String();
      
      final maquinas = widget.idMaquinaLocal.split(',').map((e) => e.trim()).toList();

      // NUEVO: Una sola llamada RPC que trae Operador, Máquinas y Tareas
      final response = await SupabaseManager.client.rpc(
        'get_dashboard_data',
        params: {
          'p_id_operador_texto': widget.idOperador,
          'p_id_maquinas': maquinas,
          'p_inicio_hoy': inicioHoy,
          'p_fin_hoy': finHoy,
        },
      ).timeout(const Duration(seconds: 15));

      if (response == null) {
        setState(() {
          error = 'No se pudo obtener la información del servidor.';
          cargando = false;
        });
        return;
      }

      final data = response as Map<String, dynamic>;
      
      setState(() {
        operador = data['operador'];
        _nombresMaquinas = (data['maquinas'] as List).map((m) => m['nombre'].toString()).join('  •  ');
        
        final listaTareas = data['tareas'] as List<dynamic>;
        _clasificarTareas(listaTareas);
        cargando = false;
        
        _calcularYActualizarSemaforo(listaTareas);
      });
    } on TimeoutException {
      setState(() {
        error = 'Sin conexión. Verifica la red e intenta de nuevo.';
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = 'Error al cargar las tareas. Intenta de nuevo.';
        cargando = false;
      });
      debugPrint('Error _cargarDatos: $e');
    }
  }

  void _clasificarTareas(List<dynamic> tareas) {
    tareasHoy.clear();
    tareasFuturas.clear();
    tareasCompletadas.clear();

    final hoy = mockNow;
    final hoyInicio = DateTime(hoy.year, hoy.month, hoy.day);

    for (var r in tareas) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      if (estado == 'completado') {
        tareasCompletadas.add(r);
        continue;
      }
      
      bool esFutura = false;
      final fechaStr = r['fecha_limite']?.toString();
      if (fechaStr != null) {
        try {
          final fl = DateTime.parse(fechaStr).toLocal();
          final limiteDia = DateTime(fl.year, fl.month, fl.day);
          if (limiteDia.isAfter(hoyInicio)) {
            esFutura = true;
          }
        } catch (_) {}
      }

      if (esFutura) {
        tareasFuturas.add(r);
      } else {
        tareasHoy.add(r);
      }
    }

    int compareFecha(a, b) {
      final fa = DateTime.tryParse(a['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse(b['fecha_limite'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return fa.compareTo(fb);
    }

    tareasHoy.sort(compareFecha);
    tareasFuturas.sort(compareFecha);
    
    tareasCompletadas.sort((a, b) {
      final fa = DateTime.tryParse(a['fecha_completado'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse(b['fecha_completado'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return fb.compareTo(fa); 
    });
  }

  String _obtenerSaludo() {
    final hora = mockNow.hour;
    if (hora >= 5 && hora < 12) return 'Buenos días';
    if (hora >= 12 && hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Future<void> _calcularYActualizarSemaforo(List<dynamic> tareas) async {
    final ahora = mockNow;
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
        break;
      } else if (estado == 'Pendiente') {
        // ...
      }
    }

    try {
      // El backend (trigger tr_evaluar_semaforo en registro_tareas) 
      // ya se encarga de actualizar semaforo_maquina automáticamente.
      // Ya no necesitamos hacer upsert manual desde el cliente.
    } catch (e) {
      debugPrint('Error actualizando semáforo: $e');
    }
  }

  Future<String?> _crearYPrepararJob(
      String linea, String maquina, String tipo, String nombreTarea, String nombreOperador) async {
    final title = "CILT - $linea - $maquina - $tipo - $nombreTarea";

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
      final createResp = await SupabaseManager.client.functions
          .invoke('parsable-proxy', body: bodyCreate)
          .timeout(const Duration(seconds: 15));

      debugPrint('Parsable create → HTTP ${createResp.status}: ${createResp.data}');

      if ((createResp.status ?? 0) < 200 || (createResp.status ?? 0) >= 300) {
        debugPrint('Error creando Job (${createResp.status}): ${createResp.data}');
        return null;
      }

      final data = createResp.data is String
          ? jsonDecode(createResp.data as String)
          : createResp.data;
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

        final stepResponse = await SupabaseManager.client.functions
            .invoke('parsable-proxy', body: bodyStep)
            .timeout(const Duration(seconds: 15));
        debugPrint('Parsable sendExecData → HTTP ${stepResponse.status}: ${stepResponse.data}');
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
      HapticFeedback.mediumImpact();
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
    final frecuencia = tarea?['frecuencia'] ?? 'Otro';

    String? parsableJobId = registro['parsable_job_id'];
    final maquinaName = _nombresMaquinas;

    if (parsableJobId == null) {
      parsableJobId = await _crearYPrepararJob(linea, maquinaName, tipo, nombreTarea, operadorNombre);
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
        AppRoutes.slide(PasosTareaScreen(
          idRegistro: registro['id'],
          idTarea: registro['id_tarea'],
          nombreTarea: nombreTarea,
          tipo: tipo,
          frecuencia: frecuencia,
          parsableJobId: parsableJobId,
          estaCompletado: estaCompletado,
        )),
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
      final ahora = mockNow;
      final fl = DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
      final hoy = DateTime(ahora.year, ahora.month, ahora.day);
      final diff = fl.difference(hoy).inDays;
      if (diff < 0) {
        final d = diff.abs();
        return 'Venció hace $d día${d > 1 ? 's' : ''}';
      }
      if (diff == 0) {
        final hora = '${fechaLimite.hour.toString().padLeft(2, '0')}:${fechaLimite.minute.toString().padLeft(2, '0')}';
        return 'Vence hoy a las $hora';
      }
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
      final ahora = mockNow;
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

  Widget _motivoChip(String motivo, int veces) {
    final label = veces > 1 ? 'Aplazada ×$veces: $motivo' : 'Aplazada: $motivo';
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
              label,
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

  Widget _buildTareaCard(Map<String, dynamic> registro, {bool esFutura = false}) {
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

    // Opacidad sutil para tareas futuras
    final double opacidadBase = esFutura && !completado ? 0.75 : 1.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: completado ? Colors.grey.shade100 : (esFutura ? Colors.white70 : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: esFutura ? Colors.grey.shade200 : Colors.grey.shade300),
                boxShadow: esFutura || completado ? [] : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (completado) {
                        _confirmarReapertura(registro, tarea);
                      } else {
                        _procesarYNavigar(registro, tarea);
                      }
                    },
                    child: Opacity(
                      opacity: opacidadBase,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Hero(
                              tag: 'hero_icon_${registro['id']}',
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: completado
                                    ? Colors.grey.shade300
                                    : _colorFrecuencia(frecuencia),
                                child: _iconoTipoTarea(tipo),
                              ),
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
                                    _motivoChip(motivo, (registro['veces_aplazada'] as int?) ?? 1),
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
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    final nombre = operador?['nombreoperador'] ?? '-';
    final maquina = _nombresMaquinas;
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
              backgroundImage: foto.isNotEmpty ? CachedNetworkImageProvider(foto) : null,
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
                    '${_obtenerSaludo()},',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
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
    int pendientes = 0, atrasadas = 0, completadas = 0, aplazadas = 0;
    final hoy = mockNow;
    final hoyInicio = DateTime(hoy.year, hoy.month, hoy.day);
    
    final todas = [...tareasHoy, ...tareasFuturas, ...tareasCompletadas];
    
    for (final r in todas) {
      final estado = (r['estado'] ?? '').toString().toLowerCase();
      final motivo = r['motivo_bloqueo']?.toString() ?? '';
      if (estado == 'completado') {
        completadas++;
      } else if (estado == 'atrasado') {
        atrasadas++;
      } else {
        bool esAtrasada = false;
        final fechaStr = r['fecha_limite']?.toString();
        if (fechaStr != null) {
          try {
            final fl = DateTime.parse(fechaStr).toLocal();
            esAtrasada = DateTime(fl.year, fl.month, fl.day).isBefore(hoyInicio);
          } catch (_) {}
        }
        if (esAtrasada) {
          atrasadas++;
        } else if (motivo.isNotEmpty) {
          aplazadas++;
        } else {
          pendientes++;
        }
      }
    }
    return {'pendientes': pendientes, 'atrasadas': atrasadas, 'completadas': completadas, 'aplazadas': aplazadas};
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
    if (r['aplazadas']! > 0) {
      parts.add(_resumenChip(
        '${r['aplazadas']} aplazada${r['aplazadas']! > 1 ? 's' : ''}',
        Colors.orange.shade800,
        Colors.orange.shade50,
      ));
    }
    if (r['pendientes']! > 0) {
      parts.add(_resumenChip(
        '${r['pendientes']} pendiente${r['pendientes']! > 1 ? 's' : ''}',
        Colors.grey.shade700,
        Colors.grey.shade100,
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

  Widget _buildProgressBar() {
    // Filtramos para el progreso solo lo que es de HOY o ATRASADO
    final hoy = mockNow;
    final completadasHoy = tareasCompletadas.where((t) {
      final fs = t['fecha_completado']?.toString();
      if (fs == null) return false;
      final dt = DateTime.parse(fs).toLocal();
      return dt.year == hoy.year && dt.month == hoy.month && dt.day == hoy.day;
    }).length;

    final totalHoy = completadasHoy + tareasHoy.length;

    if (totalHoy == 0) return const SizedBox.shrink();

    final porcentaje = completadasHoy / totalHoy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progreso de la jornada',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '${(porcentaje * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _accentGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: porcentaje,
              minHeight: 12,
              backgroundColor: Colors.grey.shade100,
              valueColor: const AlwaysStoppedAnimation<Color>(_accentGreen),
            ),
          ),
          if (porcentaje == 1.0) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.celebration, size: 14, color: Colors.orange),
                SizedBox(width: 6),
                Text(
                  '¡Excelente! Has completado todas tus tareas.',
                  style: TextStyle(fontSize: 12, color: _accentGreen, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ],
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

  Widget _buildSectionHeader(String title, IconData icon, Color color, {int count = 0}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        ],
      ),
    );
  }

  void _autoLogout() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppRoutes.fade(BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InactivityWrapper(
      onTimeout: _autoLogout,
      child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _accentGreen,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white, size: 28),
          onPressed: () => Navigator.pushReplacement(
            context,
            AppRoutes.fade(BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal)),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.red.shade400, size: 20),
            const SizedBox(width: 8),
            const Text(
              'E-CILT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: cargando
          ? _buildShimmerLoading()
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
                      const SizedBox(height: 12),
                      _buildProgressBar(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: (tareasHoy.isEmpty && tareasFuturas.isEmpty && tareasCompletadas.isEmpty)
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
                                  child: CustomScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    slivers: [
                                      if (tareasHoy.isNotEmpty) ...[
                                        SliverToBoxAdapter(child: _buildSectionHeader('Para Hoy', Icons.assignment_late_outlined, Colors.orange.shade800, count: tareasHoy.length)),
                                        SliverList(
                                          delegate: SliverChildBuilderDelegate(
                                            (_, index) => _buildTareaCard(tareasHoy[index], esFutura: false),
                                            childCount: tareasHoy.length,
                                          ),
                                        ),
                                      ],
                                      if (tareasFuturas.isNotEmpty) ...[
                                        SliverToBoxAdapter(child: _buildSectionHeader('Próximas a realizar', Icons.calendar_month_outlined, Colors.blue.shade700, count: tareasFuturas.length)),
                                        SliverList(
                                          delegate: SliverChildBuilderDelegate(
                                            (_, index) => _buildTareaCard(tareasFuturas[index], esFutura: true),
                                            childCount: tareasFuturas.length,
                                          ),
                                        ),
                                      ],
                                      if (tareasCompletadas.isNotEmpty) ...[
                                        SliverToBoxAdapter(child: _buildSectionHeader('Completadas', Icons.check_circle_outline, Colors.green.shade700, count: tareasCompletadas.length)),
                                        SliverList(
                                          delegate: SliverChildBuilderDelegate(
                                            (_, index) => _buildTareaCard(tareasCompletadas[index], esFutura: false),
                                            childCount: tareasCompletadas.length,
                                          ),
                                        ),
                                      ],
                                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Card Shimmer
          _shimmerWrapper(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 20, width: 180, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(height: 14, width: 120, color: Colors.white),
                        const SizedBox(height: 12),
                        Container(
                          height: 24,
                          width: 100,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Progress Bar Shimmer
          _shimmerWrapper(
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Section Title Shimmer
          _shimmerWrapper(
            child: Container(height: 20, width: 120, color: Colors.white),
          ),
          const SizedBox(height: 12),
          // Task Cards Shimmer
          Expanded(
            child: ListView.builder(
              itemCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (_, __) => _shimmerWrapper(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 18, width: double.infinity, color: Colors.white),
                            const SizedBox(height: 8),
                            Container(height: 13, width: 120, color: Colors.white),
                            const SizedBox(height: 6),
                            Container(height: 13, width: 180, color: Colors.white),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerWrapper({required Widget child}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.white,
      period: const Duration(milliseconds: 1500),
      child: child,
    );
  }
}

// --- CONFIGURACIÓN PARSABLE ---
class ParsableConfig {
  static const String teamId = "a42e72dd-334a-4395-b76a-9d81f0c8d213";
  static const String templateId = "7feea96e-f049-42a3-a652-dedd8c3c34c5";
  static const String stepIdNombre = "6846c276-d7ec-4d69-af72-0eea2a125cad";
  static const String fieldIdNombre = "db5ba0f0-62f1-47e5-9cb2-b27996ede80b";
  static const String jobRoleId = "fc49020e-3c13-48ec-a29a-cd367fc89d18";
  static const String defaultEmail = ParsableSecrets.defaultEmail;
}
