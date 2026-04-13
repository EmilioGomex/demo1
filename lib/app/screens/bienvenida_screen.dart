import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_manager.dart';
import 'tareas_screen.dart';
import 'supervisor_screen.dart';

class BienvenidaScreen extends StatefulWidget {
  final String idMaquinaLocal;

  const BienvenidaScreen({
    super.key,
    required this.idMaquinaLocal,
  });

  @override
  _BienvenidaScreenState createState() => _BienvenidaScreenState();
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

  @override
  void initState() {
    super.initState();

    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _focusNode.requestFocus();
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
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
      final response = await Supabase.instance.client
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

  Future<void> _validarOperador(String idOperador, {String? idLectura}) async {
    if (_isValidando) return;

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
          .maybeSingle();

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

      if (!mounted) return;

      if (esSupervisor) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SupervisorScreen(
              nombreSupervisor: nombre,
              tipo: tipo,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TareasScreen(
              idOperador: trimmedId,
              idMaquinaLocal: widget.idMaquinaLocal,
            ),
          ),
        );
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
    if (_operadorValido && _fotoOperador != null) {
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
                  child: Image.network(
                    _fotoOperador!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.person, size: 100, color: Colors.grey);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Bienvenido, $_nombreOperador',
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
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
                const SizedBox(height: 40),
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
                  child: const Column(
                    children: [
                      Text(
                        'Registro diario de tareas CILT',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          letterSpacing: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
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
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(width: 16),
                    // Caja de mensaje de estado con transición animada
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
