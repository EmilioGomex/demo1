import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';  // Importar cached_network_image
import '../../supabase_manager.dart';

class PasosTareaScreen extends StatefulWidget {
  final String idRegistro;
  final String idTarea;
  final String nombreTarea;

  const PasosTareaScreen({
    Key? key,
    required this.idRegistro,
    required this.idTarea,
    required this.nombreTarea,
  }) : super(key: key);

  @override
  State<PasosTareaScreen> createState() => _PasosTareaScreenState();
}

class _PasosTareaScreenState extends State<PasosTareaScreen> {
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

  Future<void> _cargarPasos() async {
    final response = await SupabaseManager.client
        .from('pasos_tarea')
        .select()
        .eq('id_tarea', widget.idTarea)
        .order('numeropaso')
        .execute();

    if (response.status == 200 && response.data != null) {
      List<dynamic> data = response.data;
      data.sort((a, b) => (a['numeropaso'] ?? 0).compareTo(b['numeropaso'] ?? 0));
      setState(() {
        pasos = data;
        cargando = false;
      });
    } else {
      setState(() {
        cargando = false;
      });
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      paginaActual = index;
    });
  }

  Future<void> _confirmarTarea() async {
    await SupabaseManager.client
        .from('registro_tareas')
        .update({
          'estado': 'Completado',
          'fecha_completado': DateTime.now().toIso8601String(),
        })
        .eq('id', widget.idRegistro)
        .execute();

    if (mounted) Navigator.pop(context, true);
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
            color: paginaActual == index ? const Color(0xFF007A3D) : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verdeHeineken = const Color(0xFF007A3D);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreTarea),
        backgroundColor: verdeHeineken,
      ),
      body: cargando
          ? Center(child: CircularProgressIndicator(color: verdeHeineken))
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
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.info_outline,
                                  size: 80,
                                  color: Colors.grey,
                                ),
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
                                final paso = pasos[index];
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: paso['imagenurl'] ?? '',
                                      fit: BoxFit.contain,
                                      placeholder: (context, url) => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                      errorWidget: (context, url, error) => Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            Icon(Icons.broken_image,
                                                size: 80, color: Colors.redAccent),
                                            SizedBox(height: 8),
                                            Text('Error al cargar imagen',
                                                style: TextStyle(color: Colors.redAccent)),
                                          ],
                                        ),
                                      ),
                                    ),
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
                        onPressed: () => Navigator.pop(context),
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: verdeHeineken,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
