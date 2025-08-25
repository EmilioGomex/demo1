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

    // --- SUSCRIPCIÓN REALTIME RFID ---
    _rfidChannel = Supabase.instance.client
        .channel('public:lecturas_rfid')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: 'INSERT',
            schema: 'public',
            table: 'lecturas_rfid',
          ),
          (payload, [ref]) {
            final data = payload['new'] ?? payload['record'] ?? payload;
            final idOperador = data['id_operador']?.toString();
            if (idOperador != null && idOperador.isNotEmpty) {
              _validarOperador(idOperador);
            }
          },
        );
    _rfidChannel.subscribe();
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

  void _validarOperador(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) {
      setState(() {
        _error = 'ID inválido, intenta de nuevo';
        _mensajeEstado = '';
      });
      return;
    }

    setState(() {
      _error = null;
      _mensajeEstado = 'Validando operador...';
    });

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
    } catch (e) {
      setState(() {
        _error = 'Error inesperado: $e';
        _mensajeEstado = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = const Color(0xFFF5F5F7);
    final Color accentGreen = const Color(0xFF007A3D);

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
              const SizedBox(height: 20),
              CircularProgressIndicator(
                color: accentGreen,
              ),
              const SizedBox(height: 12),
              const Text(
                'Cargando tareas...',
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
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
                      onSubmitted: _validarOperador,
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
