import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../supabase_manager.dart';
import 'tareas_screen.dart' show ParsableConfig;
import 'dart:convert';
import 'package:http/http.dart' as http;

class PasosTareaScreen extends StatefulWidget {
  final String idRegistro;
  final String idTarea;
  final String nombreTarea;
  final String? parsableJobId;
  final bool estaCompletado;

  const PasosTareaScreen({
    super.key,
    required this.idRegistro,
    required this.idTarea,
    required this.nombreTarea,
    this.parsableJobId,
    this.estaCompletado = false,
  });

  @override
  State<PasosTareaScreen> createState() => _PasosTareaScreenState();
}

class _PasosTareaScreenState extends State<PasosTareaScreen> {
  static const _verdeHeineken = Color(0xFF007A3D);
  static const _parsableRpcUrl =
      "https://api.eu-west-1.parsable.net/api/jobs";

  List<dynamic> pasos = [];
  bool cargando = true;
  bool _errorCarga = false;
  bool _procesando = false;
  int paginaActual = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _cargarPasos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _transformarUrl(String url, {bool esGif = false}) {
    if (esGif || url.isEmpty) return url;
    return '$url?transform=w_800,q_80,format_auto';
  }

  Future<void> _preCacheImagenes() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    for (int i = 0; i < pasos.length && i < 5; i++) {
      final url = pasos[i]['imagenurl'] ?? '';
      if (url.isNotEmpty && !url.toLowerCase().endsWith('.gif')) {
        try {
          await precacheImage(CachedNetworkImageProvider(_transformarUrl(url)), context);
        } catch (e) {
          debugPrint('precacheImage error (paso $i): $e');
        }
      }
    }
  }

  Future<void> _cargarPasos() async {
    try {
      final data = await SupabaseManager.client
          .from('pasos_tarea')
          .select()
          .eq('id_tarea', widget.idTarea)
          .order('numeropaso');

      if (mounted) {
        setState(() {
          pasos = data as List<dynamic>;
          cargando = false;
        });
        if (pasos.isNotEmpty) _preCacheImagenes();
      }
    } catch (e) {
      debugPrint('Error cargando pasos: $e');
      if (mounted) {
        setState(() {
          cargando = false;
          _errorCarga = true;
        });
      }
    }
  }

  void _onPageChanged(int index) => setState(() => paginaActual = index);

  Future<void> _callParsableRpc(String method, {String? reason}) async {
    if (widget.parsableJobId == null) return;

    // Cada método tiene su propia estructura de argumentos
    final Map<String, dynamic> arguments;
    if (method == 'completeWithOpts') {
      arguments = {
        "jobId": widget.parsableJobId,
        "opts": {"reason": reason ?? ''},
      };
    } else if (method == 'uncomplete') {
      arguments = {"jobId": widget.parsableJobId};
    } else {
      arguments = {"jobId": widget.parsableJobId, "reason": reason ?? ''};
    }

    final body = {"method": method, "arguments": arguments};
    debugPrint('Parsable RPC [$method] → ${jsonEncode(body)}');

    try {
      final response = await http.post(
        Uri.parse(_parsableRpcUrl),
        headers: ParsableConfig.headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('Parsable [$method] OK: ${response.body}');
      } else {
        debugPrint('Parsable [$method] error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Parsable [$method] exception: $e');
    }
  }

  Future<void> _aplazarTarea() async {
    if (_procesando) return;

    String? razonSeleccionada;
    int diasExtension = 1;
    final textController = TextEditingController();

    const razones = [
      'Máquina en funcionamiento',
      'Sin materiales',
      'Personal insuficiente',
      'Esperando repuesto',
      'Otro',
    ];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('No puedo realizar esta tarea'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nombreTarea,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text('Motivo:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: razones.map((r) => ChoiceChip(
                    label: Text(r),
                    selected: razonSeleccionada == r,
                    selectedColor: _verdeHeineken.withValues(alpha: 0.15),
                    checkmarkColor: _verdeHeineken,
                    onSelected: (v) => setStateDialog(() {
                      razonSeleccionada = v ? r : null;
                    }),
                  )).toList(),
                ),
                if (razonSeleccionada == 'Otro') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: 'Describe el motivo...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Aplazar por:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [1, 2, 3, 7].map((d) => ChoiceChip(
                    label: Text('$d día${d > 1 ? 's' : ''}'),
                    selected: diasExtension == d,
                    selectedColor: _verdeHeineken.withValues(alpha: 0.15),
                    checkmarkColor: _verdeHeineken,
                    onSelected: (_) => setStateDialog(() => diasExtension = d),
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _verdeHeineken,
                foregroundColor: Colors.white,
              ),
              onPressed: razonSeleccionada == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Aplazar tarea'),
            ),
          ],
        ),
      ),
    );

    final motivo = razonSeleccionada == 'Otro'
        ? textController.text.trim()
        : razonSeleccionada ?? '';
    textController.dispose();

    if (confirmar != true || !mounted) return;
    if (motivo.isEmpty) return;

    setState(() { cargando = true; _procesando = true; });

    try {
      final reg = await SupabaseManager.client
          .from('registro_tareas')
          .select('fecha_limite')
          .eq('id', widget.idRegistro)
          .single();

      final fechaActual =
          DateTime.tryParse(reg['fecha_limite']?.toString() ?? '') ??
              DateTime.now();
      final nuevaFecha = fechaActual.add(Duration(days: diasExtension));

      await SupabaseManager.client
          .from('registro_tareas')
          .update({
            'fecha_limite': nuevaFecha.toUtc().toIso8601String(),
            'motivo_bloqueo': motivo,
          })
          .eq('id', widget.idRegistro);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aplazada $diasExtension día${diasExtension > 1 ? 's' : ''}: $motivo',
          ),
          backgroundColor: Colors.orange.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error aplazando tarea: $e');
      if (mounted) setState(() { cargando = false; _procesando = false; });
    }
  }

  Future<void> _confirmarTarea() async {
    if (_procesando) return;
    setState(() { cargando = true; _procesando = true; });
    try {
      await SupabaseManager.client
          .from('registro_tareas')
          .update({
            'estado': 'Completado',
            'fecha_completado': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.idRegistro);

      await _callParsableRpc('completeWithOpts', reason: 'Completado desde ECILT');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tarea completada y sincronizada'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error confirmando tarea: $e');
      if (mounted) setState(() { cargando = false; _procesando = false; });
    }
  }

  Future<void> _marcarPendiente() async {
    if (_procesando) return;
    setState(() { cargando = true; _procesando = true; });
    try {
      // Solo llamar uncomplete si la tarea ya estaba completada en Parsable
      if (widget.estaCompletado) {
        await _callParsableRpc('uncomplete');
      }

      await SupabaseManager.client
          .from('registro_tareas')
          .update({'estado': 'Pendiente', 'fecha_completado': null})
          .eq('id', widget.idRegistro);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tarea marcada como pendiente'),
          backgroundColor: Colors.orange.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error marcando pendiente: $e');
      if (mounted) setState(() { cargando = false; _procesando = false; });
    }
  }

  Widget _buildPasoImage(Map<dynamic, dynamic> paso) {
    final url = paso['imagenurl'] ?? '';
    final esGif = url.toLowerCase().endsWith('.gif');
    final urlFinal = _transformarUrl(url, esGif: esGif);

    if (esGif) {
      return Image.network(urlFinal, fit: BoxFit.contain);
    }
    return CachedNetworkImage(
      imageUrl: urlFinal,
      fit: BoxFit.contain,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) => const Center(
        child: Icon(Icons.broken_image, size: 80, color: Colors.redAccent),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pasos.length, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: paginaActual == index ? 16 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: paginaActual == index ? _verdeHeineken : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.nombreTarea,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _verdeHeineken,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator(color: _verdeHeineken))
          : _errorCarga
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.black26),
                  const SizedBox(height: 16),
                  const Text(
                    'Error al cargar los pasos',
                    style: TextStyle(fontSize: 18, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _verdeHeineken,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() { cargando = true; _errorCarga = false; });
                      _cargarPasos();
                    },
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: pasos.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline, size: 80, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No hay pasos para mostrar.',
                                  style: TextStyle(fontSize: 20, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                              },
                            ),
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: _onPageChanged,
                              itemCount: pasos.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildPasoImage(pasos[index]),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ),
                if (pasos.length > 1) ...[
                  const SizedBox(height: 10),
                  _buildDots(),
                ],
                const SizedBox(height: 16),
                Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        '¿Completaste todos los pasos?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (widget.estaCompletado)
                            OutlinedButton(
                              onPressed: _procesando ? null : _marcarPendiente,
                              child: const Text('No'),
                            )
                          else
                            TextButton.icon(
                              icon: Icon(Icons.event_busy,
                                  size: 16, color: Colors.orange.shade700),
                              label: Text(
                                'No puedo realizarla',
                                style: TextStyle(color: Colors.orange.shade700),
                              ),
                              onPressed: _procesando ? null : _aplazarTarea,
                            ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _verdeHeineken,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade600,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            onPressed: (_procesando ||
                                    (pasos.length > 1 &&
                                        paginaActual < pasos.length - 1))
                                ? null
                                : _confirmarTarea,
                            child: Text(
                              pasos.length > 1 && paginaActual < pasos.length - 1
                                  ? 'Ver todos los pasos'
                                  : 'Sí, Confirmar',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
