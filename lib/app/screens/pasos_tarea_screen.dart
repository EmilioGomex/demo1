import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../supabase_manager.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PasosTareaScreen extends StatefulWidget {
  final String idRegistro;
  final String idTarea;
  final String nombreTarea;
  final String? parsableJobId;

  const PasosTareaScreen({
    super.key,
    required this.idRegistro,
    required this.idTarea,
    required this.nombreTarea,
    this.parsableJobId,
  });

  @override
  State<PasosTareaScreen> createState() => _PasosTareaScreenState();
}

class _PasosTareaScreenState extends State<PasosTareaScreen> {
  static const _verdeHeineken = Color(0xFF007A3D);
  static const _parsableRpcUrl =
      "https://api.eu-west-1.parsable.net/api/jobs#completeWithOpts";
  static const _parsableToken =
      "Token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NTM5MDA2MDEsImlzcyI6ImF1dGg6cHJvZHVjdGlvbiIsInNlcmE6Y3J0ciI6IjY4NmI4M2ZlLWY3YmYtNDA3Ni1iZWJkLTUzNjM1YTgwZmNkNSIsInNlcmE6c2lkIjoiZjk4NDI5Y2MtYzBkMy00Y2VjLWI2YjctZjlmMmQ1ZjA3NmFiIiwic2VyYTp0ZWFtSWQiOiJhNDJlNzJkZC0zMzRhLTQzOTUtYjc2YS05ZDgxZjBjOGQyMTMiLCJzZXJhOnR5cCI6InBlcnNpc3RlbnQiLCJzdWIiOiIzYWYxYmU0NS0zOTQyLTQzZDEtOTVmZC1jMjg5NTQzMmVmMTcifQ.oyskbCMhYyLoSW_S2SLyGf7LdKoynMaRa8W8wTh6QDM";
  static const _parsableHeaders = {
    "Content-Type": "application/json",
    "accept": "application/json",
    "Authorization": _parsableToken,
    "PARSABLE-CUSTOM-TOUCHSTONE": "heineken/heineken",
  };

  List<dynamic> pasos = [];
  bool cargando = true;
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
        precacheImage(CachedNetworkImageProvider(_transformarUrl(url)), context);
      }
    }
  }

  Future<void> _cargarPasos() async {
    final response = await SupabaseManager.client
        .from('pasos_tarea')
        .select()
        .eq('id_tarea', widget.idTarea)
        .order('numeropaso')
        .execute();

    if (response.status == 200 && response.data != null) {
      setState(() {
        pasos = response.data as List<dynamic>;
        cargando = false;
      });
      if (pasos.isNotEmpty) _preCacheImagenes();
    } else {
      setState(() => cargando = false);
    }
  }

  void _onPageChanged(int index) => setState(() => paginaActual = index);

  Future<void> _callParsableRpc(String method, String reason) async {
    if (widget.parsableJobId == null) return;

    final body = {
      "method": method,
      "arguments": {"jobId": widget.parsableJobId, "reason": reason},
    };

    debugPrint('Parsable RPC [$method] → ${jsonEncode(body)}');

    try {
      final response = await http.post(
        Uri.parse(_parsableRpcUrl),
        headers: _parsableHeaders,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        debugPrint('Parsable [$method] OK: ${response.body}');
      } else {
        debugPrint('Parsable [$method] error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Parsable [$method] exception: $e');
    }
  }

  Future<void> _confirmarTarea() async {
    setState(() => cargando = true);
    try {
      await SupabaseManager.client
          .from('registro_tareas')
          .update({
            'estado': 'Completado',
            'fecha_completado': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.idRegistro)
          .execute();

      await _callParsableRpc('complete', 'Completado desde ECILT');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tarea completada y sincronizada'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error confirmando tarea: $e');
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> _marcarPendiente() async {
    setState(() => cargando = true);
    try {
      await _callParsableRpc('reopen', 'Reabierto desde ECILT');

      await SupabaseManager.client
          .from('registro_tareas')
          .update({'estado': 'Pendiente', 'fecha_completado': null})
          .eq('id', widget.idRegistro)
          .execute();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tarea marcada como pendiente'),
            backgroundColor: Colors.orange.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error marcando pendiente: $e');
      if (mounted) setState(() => cargando = false);
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
                if (pasos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildDots(),
                ],
                const SizedBox(height: 16),
                Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: _marcarPendiente,
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _verdeHeineken,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        onPressed: _confirmarTarea,
                        child: const Text(
                          'Sí, Confirmar',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
