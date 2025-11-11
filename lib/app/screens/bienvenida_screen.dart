import 'dart:io'; // Importar para SocketException
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_manager.dart';
import 'tareas_screen.dart';
import 'supervisor_screen.dart';

class BienvenidaScreen extends StatefulWidget {
  const BienvenidaScreen({super.key});

  @override
  _BienvenidaScreenState createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends State<BienvenidaScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late FocusNode _focusNode;

  String? _error;
  String _mensajeEstado = 'Escanea tu tarjeta para registrar actividad';

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  bool _operadorValido = false;
  String? _fotoOperador;
  String? _nombreOperador;

  late RealtimeChannel _rfidChannel;

  // Optimización: "Lock" para evitar validaciones múltiples (Debouncing)
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

    // --- SUSCRIPCIÓN REALTIME RFID (Actualizada) ---
    _rfidChannel = Supabase.instance.client
        .channel('public:lecturas_rfid')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: 'INSERT',
            schema: 'public',
            table: 'lecturas_rfid',
            // Nuevo: Filtra para que solo nos lleguen lecturas no procesadas
            filter: 'procesado=eq.false',
          ),
          (payload, [ref]) {
            final data = payload['new'] ?? payload['record'] ?? payload;
            final idOperador = data['id_operador']?.toString();
            // Nuevo: Obtenemos el ID de la fila (UUID)
            final idLectura = data['id']?.toString();

            if (idOperador != null &&
                idOperador.isNotEmpty &&
                idLectura != null) {
              // Nuevo: Pasamos ambos IDs a la función de validación
              _validarOperador(idOperador, idLectura: idLectura);
            }
          },
        );
    // Nuevo: Manejador de errores para el canal Realtime
    _rfidChannel.onError((e) {
      debugPrint('Error en el canal Realtime: $e');
      if (mounted) {
        setState(() {
          _mensajeEstado = 'Error de conexión Realtime';
          _error = 'No se pudo conectar al lector RFID';
        });
      }
    });
    _rfidChannel.subscribe();

    // --- NUEVO: Buscar lecturas pendientes al iniciar ---
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

  // --- NUEVO: Función para buscar lecturas pendientes ---
  Future<void> _buscarLecturaPendiente() async {
    // Damos un respiro para que la UI se construya
    await Future.delayed(const Duration(milliseconds: 500));

    // Si ya está validando o el widget no está montado, no hacer nada
    if (_isValidando || !mounted) return;

    try {
      // Calcula "hace un minuto"
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));

      final response = await Supabase.instance.client
          .from('lecturas_rfid')
          .select('id, id_operador') // Traemos el id de la lectura y del operador
          .eq('procesado', false) // Que no esté procesada
          .gte('fecha_lectura',
              oneMinuteAgo.toIso8601String()) // De hace 1 min
          .order('fecha_lectura', ascending: false) // La más reciente primero
          .limit(1) // Solo queremos una
          .maybeSingle();

      if (response != null && mounted) {
        // ¡Encontramos una lectura pendiente!
        final String idLectura = response['id'];
        final String idOperador = response['id_operador'];

        // La mandamos al validador, que la marcará como procesada
        _validarOperador(idOperador, idLectura: idLectura);
      }
    } catch (e) {
      debugPrint('Error buscando lectura pendiente: $e');
      // No es crítico, el usuario simplemente tendrá que escanear de nuevo.
    }
  }

  // --- FUNCIÓN _validarOperador (Actualizada) ---
  void _validarOperador(String idOperador, {String? idLectura}) async {
    // Optimización: Debounce check
    if (_isValidando) return;

    final trimmedId = idOperador.trim();
    if (trimmedId.isEmpty) {
      setState(() {
        _error = 'ID inválido, intenta de nuevo';
        _mensajeEstado = '';
      });
      return;
    }

    setState(() {
      _isValidando = true; // "Bloquea" para evitar dobles validaciones
      _error = null;
      _mensajeEstado = 'Validando operador...';
    });

    // Nuevo: Si la validación viene de un RFID (Realtime o pendiente),
    // la "reclamamos" marcándola como procesada.
    if (idLectura != null) {
      try {
        await SupabaseManager.client
            .from('lecturas_rfid')
            .update({'procesado': true}).eq('id', idLectura);
      } catch (e) {
        debugPrint('Error al marcar lectura como procesada: $e');
        // No detenemos el flujo de login, pero es bueno registrarlo.
      }
    }

    // Optimización: Manejo de errores de red y Supabase
    try {
      final response = await SupabaseManager.client
          .from('operadores')
          .select()
          .eq('id_operador', trimmedId)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _error = '';
          _mensajeEstado = 'Operador no válido, intenta de nuevo';
        });

        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() {
            _error = null;
            _mensajeEstado = 'Escanea tu tarjeta para registrar actividad';
            _isValidando = false; // "Libera" el lock
          });
        });

        return;
      } else {
        final tipo = (response['tipo'] ?? '').toString().toLowerCase();
        final nombre = response['nombreoperador'] ?? 'Supervisor';
        setState(() {
          _mensajeEstado = 'Bienvenido, $nombre';
          _error = null;
          _operadorValido = true;
          _fotoOperador = response['foto_operador'];
          _nombreOperador = nombre;
        });

        _scaleController.forward(from: 0.0);

        await Future.delayed(const Duration(seconds: 3));

        if (!mounted) return;

        if (tipo == 'supervisor') {
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
              builder: (context) => TareasScreen(idOperador: trimmedId),
            ),
          );
        }
      }
    } on SocketException catch (_) {
      // Error de conexión
      setState(() {
        _error = 'Error de red. Revisa tu conexión a internet.';
        _mensajeEstado = '';
        _isValidando = false; // "Libera" el lock
      });
    } on PostgrestException catch (e) {
      // Error de Supabase (ej. permisos, tabla no existe)
      setState(() {
        _error = 'Error de base de datos: ${e.message}';
        _mensajeEstado = '';
        _isValidando = false; // "Libera" el lock
      });
    } catch (e) {
      // Error inesperado
      setState(() {
        _error = 'Error inesperado: $e';
        _mensajeEstado = '';
        _isValidando = false; // "Libera" el lock
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = const Color(0xFFF5F5F7);
    final Color accentGreen = const Color(0xFF007A3D);

    // --- Pantalla de Bienvenida (con foto) ---
    // Optimización UX: Se eliminó el "Cargando tareas..."
    if (_operadorValido && _fotoOperador != null) {
      return Scaffold(
        backgroundColor: backgroundColor,
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
                        color: accentGreen.withOpacity(0.25),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: accentGreen,
                      width: 4,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.network(
                      _fotoOperador!,
                      fit: BoxFit.cover,
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return AnimatedOpacity(
                            opacity: 1,
                            duration: const Duration(milliseconds: 500),
                            child: child,
                          );
                        } else {
                          return AnimatedOpacity(
                            opacity: 0,
                            duration: const Duration(milliseconds: 500),
                            child: child,
                          );
                        }
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: accentGreen,
                            strokeWidth: 4,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person_off,
                          size: 120,
                          color: Colors.grey,
                        );
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
              // Indicador de carga y texto "Cargando..." ELIMINADOS
            ],
          ),
        ),
      );
    }

    // --- Pantalla Principal (de escaneo) ---
    return Scaffold(
      backgroundColor: backgroundColor,
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
                        color: accentGreen.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo_heineken.png',
                    height: 100,
                    fit: BoxFit.contain,
                    color: accentGreen.withOpacity(0.85),
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
                  child: Column(
                    children: const [
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
                      if (_error == null)
                        Icon(Icons.qr_code_scanner,
                            color: accentGreen, size: 28)
                      else
                        const Icon(Icons.error,
                            color: Colors.redAccent, size: 28),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: accentGreen, width: 1.8),
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
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: _error == null
                                    ? accentGreen
                                    : Colors.redAccent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_mensajeEstado == 'Validando operador...')
                              const SizedBox(width: 12),
                            if (_mensajeEstado == 'Validando operador...')
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: accentGreen,
                                  strokeWidth: 3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    // Actualizado: Llama a la nueva firma de la función
                    // y limpia el controlador.
                    onSubmitted: (idOperador) {
                      _validarOperador(idOperador, idLectura: null);
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