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
  static const _mensajeInicial = 'Escanea tu tarjeta para registrar actividad';

  final TextEditingController _controller = TextEditingController();
  late FocusNode _focusNode;

  String _mensajeEstado = _mensajeInicial;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  bool _operadorValido = false;
  String? _fotoOperador;
  String? _nombreOperador;

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

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _fadeAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.repeat(reverse: true);

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
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
      // En caso de error de conexión, aquí sí podrías querer avisar discretamente,
      // o dejarlo silencioso también según tu preferencia.
    });
    _rfidChannel.subscribe();

    _buscarLecturaPendiente();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scaleController.dispose();
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
      // 1. CAMBIO IMPORTANTE: Quitamos el filtro .eq('id_maquina', ...)
      // Buscamos al operador solo por su ID de tarjeta para ver quién es primero.
      final response = await SupabaseManager.client
          .from('operadores')
          .select()
          .eq('id_operador', trimmedId)
          .maybeSingle();

      if (response == null) {
        // El operador no existe en la base de datos
        debugPrint('Operador no encontrado');
        _resetearEstadoSilencioso();
        return;
      }

      // 2. OBTENEMOS LOS DATOS
      final tipo = (response['tipo'] ?? '').toString().toLowerCase().trim();
      final idMaquinaOperador = response['id_maquina']?.toString();
      final nombre = response['nombreoperador'] ?? 'Usuario';

      // 3. LÓGICA DE PERMISOS (Aquí está la magia)
      // - Si es supervisor: PASA SIEMPRE.
      // - Si NO es supervisor: Solo pasa si su máquina coincide con la tablet.
      
      bool esSupervisor = tipo == 'supervisor';
      bool esMaquinaCorrecta = idMaquinaOperador == widget.idMaquinaLocal;

      if (!esSupervisor && !esMaquinaCorrecta) {
        // Es un operador normal intentando entrar en la máquina equivocada
        debugPrint('Acceso denegado: Operador de $idMaquinaOperador en tablet ${widget.idMaquinaLocal}');
        _resetearEstadoSilencioso();
        return;
      }

      // --- SI LLEGA AQUÍ, EL ACCESO ES VÁLIDO ---

      setState(() {
        _mensajeEstado = 'Bienvenido, $nombre';
        _operadorValido = true;
        _fotoOperador = response['foto_operador'];
        _nombreOperador = nombre;
      });

      _scaleController.forward(from: 0.0);

      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      // Navegación según el tipo
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
        // Si es operador, pasamos también la máquina para asegurar consistencia
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
          ],
        ),
      ),
    );
  }

  Widget _buildScanScreen() {
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
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
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
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner, color: _accentGreen, size: 28),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: _accentGreen, width: 1.8),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
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
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: _accentGreen,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_isValidando) ...[
                              const SizedBox(width: 12),
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: _accentGreen,
                                  strokeWidth: 3,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
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