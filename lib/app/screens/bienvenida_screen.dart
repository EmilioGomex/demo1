import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../supabase_manager.dart';
import '../utils/app_routes.dart';
import 'config_screen.dart';
import 'tareas_screen.dart';
import 'supervisor_screen.dart';

class BienvenidaScreen extends StatefulWidget {
  final String idMaquinaLocal;

  const BienvenidaScreen({
    super.key,
    required this.idMaquinaLocal,
  });

  @override
  State<BienvenidaScreen> createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends State<BienvenidaScreen>
    with TickerProviderStateMixin {
  static const _backgroundColor = Color(0xFFF5F5F7);
  static const _accentGreen = Color(0xFF007A3D);
  static const _accentRed = Color(0xFFD32F2F);
  static const _mensajeInicial = 'Escanea tu tarjeta para registrar actividad';

  final TextEditingController _controller = TextEditingController();
  late FocusNode _focusNode;

  String _mensajeEstado = _mensajeInicial;

  // Animación de pulso radial para el icono NFC
  late AnimationController _pulseController;

  // Animación de escala para la foto del operador
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // Barra de progreso en pantalla de bienvenida (3s)
  late AnimationController _progressController;

  bool _operadorValido = false;
  String? _fotoOperador;
  String? _nombreOperador;
  bool _accesoDenegado = false;

  late RealtimeChannel _rfidChannel;
  bool _isValidando = false;
  bool _selectorAbierto = false;
  String? _nombreMaquina;

  // Pre-carga en segundo plano
  List<Map<String, dynamic>> _operadoresPrecargados = [];
  bool _operadoresCargados = false;

  @override
  void initState() {
    super.initState();

    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && !_operadorValido) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && !_operadorValido) _focusNode.requestFocus();
        });
      }
    });

    // Pulso continuo para el icono NFC — 2s, repeat hacia adelante
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // Progreso suave de 3 segundos para la pantalla de bienvenida
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // --- SUSCRIPCIÓN REALTIME ---
    _rfidChannel = Supabase.instance.client
        .channel('public:lecturas_rfid')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: 'INSERT',
            schema: 'public',
            table: 'lecturas_rfid',
            filter: 'procesado=eq.false',
          ),
          (payload, [ref]) {
            final data = payload['new'] ?? payload['record'] ?? payload;
            final idOperador = data['id_operador']?.toString();
            final idLectura = data['id']?.toString();

            if (idOperador != null &&
                idOperador.isNotEmpty &&
                idLectura != null) {
              _validarOperador(idOperador, idLectura: idLectura);
            }
          },
        );

    _rfidChannel.onError((e) {
      debugPrint('Error Realtime: $e');
    });
    _rfidChannel.subscribe();

    _buscarLecturaPendiente();
    _cargarNombreMaquina();
    _precargarOperadores();
    _actualizarTareasVencidas();
  }

  /// Marca como 'Atrasado' todas las tareas Pendiente con fecha_limite vencida.
  /// Corre en background al iniciar, sin bloquear la UI.
  Future<void> _actualizarTareasVencidas() async {
    try {
      final hoyInicio = DateTime.now();
      final limiteFecha = DateTime(hoyInicio.year, hoyInicio.month, hoyInicio.day)
          .toUtc()
          .toIso8601String();
      await SupabaseManager.client
          .from('registro_tareas')
          .update({'estado': 'Atrasado'})
          .eq('estado', 'Pendiente')
          .lt('fecha_limite', limiteFecha);
      debugPrint('Tareas vencidas actualizadas a Atrasado');
    } catch (e) {
      debugPrint('Error actualizando tareas vencidas: $e');
    }
  }

  Future<void> _precargarOperadores() async {
    try {
      final response = await SupabaseManager.client
          .from('operadores')
          .select()
          .eq('id_maquina', widget.idMaquinaLocal)
          .neq('tipo', 'supervisor')
          .order('nombreoperador');
      if (mounted) {
        setState(() {
          _operadoresPrecargados = List<Map<String, dynamic>>.from(response);
          _operadoresCargados = true;
        });
      }
    } catch (e) {
      debugPrint('Error precargando operadores: $e');
      if (mounted) setState(() => _operadoresCargados = true);
    }
  }

  Future<void> _cargarNombreMaquina() async {
    try {
      final resp = await SupabaseManager.client
          .from('maquinas')
          .select('nombre')
          .eq('id_maquina', widget.idMaquinaLocal)
          .maybeSingle();
      if (resp != null && mounted) {
        setState(() => _nombreMaquina = resp['nombre']?.toString());
      }
    } catch (e) {
      debugPrint('Error cargando nombre máquina: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _progressController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _rfidChannel.unsubscribe();
    super.dispose();
  }

  Future<void> _buscarLecturaPendiente() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_isValidando || !mounted) return;

    try {
      final oneMinuteAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final response = await SupabaseManager.client
          .from('lecturas_rfid')
          .select('id, id_operador')
          .eq('procesado', false)
          .gte('fecha_lectura', oneMinuteAgo.toIso8601String())
          .order('fecha_lectura', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && mounted) {
        final String idLectura = response['id'];
        final String idOperador = response['id_operador'];
        _validarOperador(idOperador, idLectura: idLectura);
      }
    } catch (e) {
      debugPrint('Error buscando lectura pendiente: $e');
    }
  }

  Widget _avatarBienvenida() {
    return Container(
      color: Colors.grey.shade100,
      child: const Icon(Icons.person, size: 100, color: Colors.grey),
    );
  }

  String _saludo() {
    final hora = TimeOfDay.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Future<void> _validarOperador(String idOperador, {String? idLectura}) async {
    if (_isValidando) return;
    if (_selectorAbierto) {
      _selectorAbierto = false;
      if (mounted) Navigator.pop(context);
    }

    final trimmedId = idOperador.trim();
    if (trimmedId.isEmpty) return;

    setState(() {
      _isValidando = true;
      _mensajeEstado = 'Validando...';
    });

    if (idLectura != null) {
      try {
        await SupabaseManager.client
            .from('lecturas_rfid')
            .update({'procesado': true}).eq('id', idLectura);
      } catch (e) {
        debugPrint('Error update procesado: $e');
      }
    }

    try {
      final response = await SupabaseManager.client
          .from('operadores')
          .select()
          .eq('id_operador', trimmedId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response == null) {
        debugPrint('Operador no encontrado');
        _resetearEstadoSilencioso();
        return;
      }

      final tipo = (response['tipo'] ?? '').toString().toLowerCase().trim();
      final idMaquinaOperador = response['id_maquina']?.toString();
      final nombre = response['nombreoperador'] ?? 'Usuario';

      bool esSupervisor = tipo == 'supervisor';
      bool esMaquinaCorrecta = idMaquinaOperador == widget.idMaquinaLocal;

      if (!esSupervisor && !esMaquinaCorrecta) {
        debugPrint('Acceso denegado: Operador de $idMaquinaOperador en tablet ${widget.idMaquinaLocal}');
        _mostrarAccesoDenegado();
        return;
      }

      setState(() {
        _mensajeEstado = 'Bienvenido, $nombre';
        _operadorValido = true;
        _fotoOperador = response['foto_operador'];
        _nombreOperador = nombre;
      });

      _scaleController.forward(from: 0.0);
      _progressController.forward(from: 0.0);

      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) {
        _isValidando = false;
        return;
      }

      if (esSupervisor) {
        Navigator.pushReplacement(
          context,
          AppRoutes.fade(SupervisorScreen(
            nombreSupervisor: nombre,
            idMaquinaLocal: widget.idMaquinaLocal,
            fotoSupervisor: response['foto_operador']?.toString(),
          )),
        );
      } else {
        Navigator.pushReplacement(
          context,
          AppRoutes.fade(TareasScreen(
            idOperador: trimmedId,
            idMaquinaLocal: widget.idMaquinaLocal,
          )),
        );
      }
    } on TimeoutException {
      debugPrint('Timeout validando operador');
      if (mounted) {
        setState(() {
          _isValidando = false;
          _mensajeEstado = 'Sin conexión. Intenta de nuevo.';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _mensajeEstado = _mensajeInicial);
      }
    } catch (e) {
      debugPrint('Error en validación: $e');
      _resetearEstadoSilencioso();
    }
  }

  void _resetearEstadoSilencioso() {
    if (mounted) {
      setState(() {
        _isValidando = false;
        _mensajeEstado = _mensajeInicial;
      });
    }
  }

  void _abrirSelectorOperador() {
    _selectorAbierto = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OperadorSelectorSheet(
        idMaquinaLocal: widget.idMaquinaLocal,
        operadoresPrecargados: _operadoresCargados ? _operadoresPrecargados : null,
        onOperadorSeleccionado: (idOperador) {
          _selectorAbierto = false;
          Navigator.pop(context);
          _validarOperador(idOperador);
        },
      ),
    ).whenComplete(() => _selectorAbierto = false);
  }

  Future<void> _mostrarAccesoDenegado() async {
    if (!mounted) return;
    setState(() {
      _accesoDenegado = true;
      _isValidando = false;
      _mensajeEstado = 'Acceso no autorizado';
    });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _accesoDenegado = false;
        _mensajeEstado = _mensajeInicial;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_operadorValido) {
      return _buildWelcomeScreen();
    }
    return _buildScanScreen();
  }

  Widget _buildWelcomeScreen() {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                height: 250,
                width: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _accentGreen.withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: _accentGreen, width: 4),
                ),
                child: ClipOval(
                  child: _fotoOperador != null && _fotoOperador!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _fotoOperador!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _avatarBienvenida(),
                        )
                      : _avatarBienvenida(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${_saludo()}, $_nombreOperador',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 28),
            // Barra de progreso + countdown antes de navegar
            SizedBox(
              width: 260,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) {
                  final segundosRestantes =
                      (3 - (_progressController.value * 3)).ceil();
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progressController.value,
                          minHeight: 6,
                          backgroundColor: Colors.black12,
                          color: _accentGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entrando en ${segundosRestantes}s...',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanScreen() {
    final Color statusColor = _accesoDenegado ? _accentRed : _accentGreen;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50),
          child: Column(
            children: [
              const Spacer(),
              GestureDetector(
                onLongPress: () => Navigator.push(
                  context,
                  AppRoutes.slide(const ConfigScreen()),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _accentGreen.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo_heineken.png',
                    height: 100,
                    fit: BoxFit.contain,
                    color: _accentGreen.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(height: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
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
                  child: Column(
                    children: [
                      const Text(
                        'E-CILT',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: 4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Limpieza, Inspección, Lubricación, Apriete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.black54,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_nombreMaquina != null) ...[
                        const SizedBox(height: 12),
                        const Divider(color: Colors.black12, height: 1),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.precision_manufacturing,
                                size: 16, color: _accentGreen),
                            const SizedBox(width: 6),
                            Text(
                              _nombreMaquina!,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icono NFC con ondas de pulso radial
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final v1 = _pulseController.value;
                        final v2 = (_pulseController.value + 0.5) % 1.0;
                        return SizedBox(
                          width: 90,
                          height: 90,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Onda exterior 1
                              Opacity(
                                opacity: (1 - v1) * 0.55,
                                child: Container(
                                  width: 56 + 34 * v1,
                                  height: 56 + 34 * v1,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: statusColor,
                                      width: 2.0 * (1 - v1) + 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Onda exterior 2 (desfasada 0.5)
                              Opacity(
                                opacity: (1 - v2) * 0.55,
                                child: Container(
                                  width: 56 + 34 * v2,
                                  height: 56 + 34 * v2,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: statusColor,
                                      width: 2.0 * (1 - v2) + 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Icono NFC central
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor.withValues(alpha: 0.08),
                                  border:
                                      Border.all(color: statusColor, width: 2),
                                ),
                                child: Icon(Icons.nfc,
                                    color: statusColor, size: 30),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    // Caja de mensaje de estado con transición animada
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: statusColor, width: 1.8),
                        borderRadius: BorderRadius.circular(12),
                        color: _accesoDenegado
                            ? _accentRed.withValues(alpha: 0.07)
                            : Colors.white,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _mensajeEstado,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_isValidando) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: statusColor,
                                strokeWidth: 3,
                              ),
                            ),
                          ],
                          if (_accesoDenegado) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.block,
                                color: _accentRed, size: 22),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    onSubmitted: (idOperador) {
                      _validarOperador(idOperador);
                      _controller.clear();
                    },
                    keyboardType: TextInputType.text,
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _abrirSelectorOperador,
                  icon: const Icon(Icons.person_outline, size: 20),
                  label: const Text('Ingresar sin tarjeta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black45,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black26, width: 1.2),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                    elevation: 0,
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom sheet: carrusel de operadores de la máquina
// ─────────────────────────────────────────────────────────────

class _OperadorSelectorSheet extends StatefulWidget {
  final String idMaquinaLocal;
  final void Function(String idOperador) onOperadorSeleccionado;
  final List<Map<String, dynamic>>? operadoresPrecargados;

  const _OperadorSelectorSheet({
    required this.idMaquinaLocal,
    required this.onOperadorSeleccionado,
    this.operadoresPrecargados,
  });

  @override
  State<_OperadorSelectorSheet> createState() => _OperadorSelectorSheetState();
}

class _OperadorSelectorSheetState extends State<_OperadorSelectorSheet> {
  static const _accentGreen = Color(0xFF007A3D);

  List<Map<String, dynamic>> _operadores = [];
  bool _cargando = true;
  late PageController _pageController;
  int _paginaActual = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.72);
    if (widget.operadoresPrecargados != null) {
      _operadores = widget.operadoresPrecargados!;
      _cargando = false;
    } else {
      _cargarOperadores();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _cargarOperadores() async {
    try {
      final response = await SupabaseManager.client
          .from('operadores')
          .select()
          .eq('id_maquina', widget.idMaquinaLocal)
          .neq('tipo', 'supervisor')
          .order('nombreoperador');

      if (mounted) {
        setState(() {
          _operadores = List<Map<String, dynamic>>.from(response);
          _cargando = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando operadores: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Selecciona tu usuario',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(color: _accentGreen),
            )
          else if (_operadores.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 32),
              child: Text(
                'No hay operadores registrados\npara esta máquina.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          else ...[
            SizedBox(
              height: 260,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _operadores.length,
                onPageChanged: (i) => setState(() => _paginaActual = i),
                itemBuilder: (context, index) {
                  final op = _operadores[index];
                  final bool activo = index == _paginaActual;
                  final foto = op['foto_operador']?.toString() ?? '';

                  return GestureDetector(
                    onTap: () {
                      if (activo) {
                        widget.onOperadorSeleccionado(op['id_operador'].toString());
                      } else {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: AnimatedScale(
                      scale: activo ? 1.0 : 0.88,
                      duration: const Duration(milliseconds: 200),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: activo ? _accentGreen : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: activo
                                    ? _accentGreen.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.07),
                                blurRadius: activo ? 16 : 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: activo
                                        ? _accentGreen
                                        : Colors.grey.shade300,
                                    width: 3,
                                  ),
                                ),
                                child: ClipOval(child: _buildFoto(foto)),
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  op['nombreoperador'] ?? 'Operador',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            // Indicador de puntos
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_operadores.length, (i) {
                final bool activo = i == _paginaActual;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: activo ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: activo ? _accentGreen : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  onPressed: () {
                    final op = _operadores[_paginaActual];
                    widget.onOperadorSeleccionado(
                        op['id_operador'].toString());
                  },
                  child: const Text(
                    'Iniciar sesión',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoto(String url) {
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _avatarGenerico(),
      );
    }
    return _avatarGenerico();
  }

  Widget _avatarGenerico() {
    return Container(
      color: Colors.grey.shade100,
      child: const Icon(Icons.person, size: 64, color: Colors.grey),
    );
  }
}
