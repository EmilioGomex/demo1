import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../supabase_manager.dart';
import '../utils/app_routes.dart';
import 'config_screen.dart';
import 'tareas_screen.dart';
import 'supervisor_screen.dart';

import '../utils/time_manager.dart';

// Retorna la fecha actual del dispositivo controlada por TimeManager
DateTime get mockNow => TimeManager.now();

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
  bool _esSupervisor = false;
  int? _tareasAtrasadas;
  int? _tareasPendientes;
  int? _tareasAplazadas;

  late RealtimeChannel _rfidChannel;
  bool _isValidando = false;
  bool _selectorAbierto = false;
  String? _nombreMaquina;
  String _horaDisplay = '';
  Timer? _clockTimer;

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
        // Solo re-enfocar si la pantalla de Bienvenida es la que está al frente (activa).
        // Esto evita que robe el foco cuando el usuario navega a Configuración.
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (!isCurrent) return;

        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && !_operadorValido) {
            final stillCurrent = ModalRoute.of(context)?.isCurrent ?? false;
            if (stillCurrent) _focusNode.requestFocus();
          }
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

    _horaDisplay = _calcularHora();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _horaDisplay = _calcularHora());
    });

    _buscarLecturaPendiente();
    _cargarNombreMaquina();
    _precargarOperadores();
    _actualizarTareasVencidas();
  }

  /// Marca como 'Atrasado' todas las tareas Pendiente con fecha_limite vencida.
  /// Corre en background al iniciar, sin bloquear la UI.
  Future<void> _actualizarTareasVencidas() async {
    try {
      final hoyInicio = mockNow;
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
      final maquinas = widget.idMaquinaLocal.split(',').map((e) => e.trim()).toList();
      if (maquinas.isEmpty || maquinas.first.isEmpty) {
        if (mounted) setState(() { _operadoresPrecargados = []; _operadoresCargados = true; });
        return;
      }

      final maquinasIn = maquinas.map((e) => '"$e"').join(',');
      final hoy = mockNow.toIso8601String().split('T')[0];

      final responseTurnos = await SupabaseManager.client
          .from('turnos_semana')
          .select('id_operador')
          .eq('fecha', hoy)
          .filter('id_maquina', 'in', '($maquinasIn)');

      final Set<String> idsValidos = (responseTurnos as List)
          .map((e) => e['id_operador'].toString())
          .toSet();

      if (idsValidos.isEmpty) {
        if (mounted) {
          setState(() {
            _operadoresPrecargados = [];
            _operadoresCargados = true;
          });
        }
        return;
      }

      final idsIn = idsValidos.map((e) => '"$e"').join(',');

      final responseOps = await SupabaseManager.client
          .from('operadores')
          .select('id_operador, nombreoperador, foto_operador, linea')
          .filter('id_operador', 'in', '($idsIn)')
          .neq('tipo', 'supervisor')
          .order('nombreoperador');

      if (mounted) {
        setState(() {
          _operadoresPrecargados = List<Map<String, dynamic>>.from(responseOps);
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
      final maquinas = widget.idMaquinaLocal.split(',').map((e) => e.trim()).toList();
      final resp = await SupabaseManager.client
          .from('maquinas')
          .select('nombre')
          .filter('id_maquina', 'in', '(${maquinas.map((e) => '"$e"').join(',')})');
          
      if (mounted) {
        final nombres = (resp as List).map((m) => m['nombre'].toString()).join('  •  ');
        setState(() => _nombreMaquina = nombres);
      }
    } catch (e) {
      debugPrint('Error cargando nombre máquina: $e');
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    _progressController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _rfidChannel.unsubscribe();
    super.dispose();
  }

  String _calcularHora() {
    final now = mockNow;
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _turnoActual() {
    final hora = mockNow.hour;
    if (hora >= 6 && hora < 14) return 'Turno Mañana';
    if (hora >= 14 && hora < 22) return 'Turno Tarde';
    return 'Turno Noche';
  }

  Future<void> _cargarResumenBienvenida(String idOp, String maquinasStr) async {
    try {
      final hoy = mockNow;
      final hoyInicio = DateTime(hoy.year, hoy.month, hoy.day);
      final inicioHoy = hoyInicio.toUtc().toIso8601String();
      final finHoy = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999)
          .toUtc()
          .toIso8601String();

      final maquinas = maquinasStr.split(',').map((e) => e.trim()).toList();
      final maquinasIn = maquinas.map((e) => '"$e"').join(',');

      final tareas = await SupabaseManager.client
          .from('registro_tareas')
          .select('estado, fecha_limite, motivo_bloqueo')
          .or('id_operador.eq.$idOp,and(id_operador.is.null,id_maquina.in.($maquinasIn))')
          .or(
            'estado.in.("Pendiente","Atrasado"),'
            'and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy)',
          )
          .timeout(const Duration(seconds: 5));

      int atrasadas = 0, pendientes = 0, aplazadas = 0;
      for (final t in tareas as List) {
        final estado = (t['estado'] ?? '').toString().toLowerCase();
        final motivo = t['motivo_bloqueo']?.toString() ?? '';
        if (estado == 'completado') continue;
        if (motivo.isNotEmpty) {
          aplazadas++;
        } else if (estado == 'atrasado') {
          atrasadas++;
        } else {
          bool esAtrasada = false;
          final fechaStr = t['fecha_limite']?.toString();
          if (fechaStr != null) {
            try {
              final fl = DateTime.parse(fechaStr).toLocal();
              esAtrasada =
                  DateTime(fl.year, fl.month, fl.day).isBefore(hoyInicio);
            } catch (_) {}
          }
          if (esAtrasada) { atrasadas++; } else { pendientes++; }
        }
      }

      if (mounted) {
        setState(() {
          _tareasAtrasadas = atrasadas;
          _tareasPendientes = pendientes;
          _tareasAplazadas = aplazadas;
        });
      }
    } catch (_) {}
  }

  Widget _bienvenidaChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Future<void> _buscarLecturaPendiente() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_isValidando || !mounted) return;

    try {
      final oneMinuteAgo = mockNow.toUtc().subtract(const Duration(minutes: 1));
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

    // Feedback físico al detectar tarjeta
    HapticFeedback.heavyImpact();

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
          .select('id_operador, nombreoperador, foto_operador, tipo, linea')
          .eq('id_operador', trimmedId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response == null) {
        debugPrint('Operador no encontrado');
        _resetearEstadoSilencioso();
        return;
      }

      final tipo = (response['tipo'] ?? '').toString().toLowerCase().trim();
      final nombre = response['nombreoperador'] ?? 'Usuario';

      bool esSupervisor = tipo == 'supervisor';

      setState(() {
        _mensajeEstado = 'Bienvenido, $nombre';
        _operadorValido = true;
        _fotoOperador = response['foto_operador'];
        _nombreOperador = nombre;
        _esSupervisor = esSupervisor;
        _tareasAtrasadas = null;
        _tareasPendientes = null;
        _tareasAplazadas = null;
      });

      _scaleController.forward(from: 0.0);
      _progressController.forward(from: 0.0);

      if (!esSupervisor) {
        _cargarResumenBienvenida(trimmedId, widget.idMaquinaLocal);
      }

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
        _esSupervisor = false;
        _tareasAtrasadas = null;
        _tareasPendientes = null;
        _tareasAplazadas = null;
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
    final total = (_tareasAtrasadas ?? 0) + (_tareasPendientes ?? 0) + (_tareasAplazadas ?? 0);

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header verde — igual que la pantalla de escaneo
            Container(
              decoration: BoxDecoration(
                color: _accentGreen,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentGreen.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 26),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFFF4444), size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'E-CILT',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Foto del operador
            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  height: 200,
                  width: 200,
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
            ),

            const SizedBox(height: 18),

            Text(
              '${_saludo()},',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.black45),
            ),
            Text(
              _nombreOperador ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),

            const SizedBox(height: 22),

            // Resumen de tareas
            if (_esSupervisor)
              Center(child: _bienvenidaChip('Modo Supervisor', _accentGreen, _accentGreen.withValues(alpha: 0.08)))
            else if (_tareasAtrasadas == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(color: _accentGreen, strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text('Cargando tus tareas...', style: TextStyle(color: Colors.black38, fontSize: 14)),
                ],
              )
            else if (total == 0)
              Center(child: _bienvenidaChip('¡Todo al día hoy! ✓', _accentGreen, _accentGreen.withValues(alpha: 0.08)))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if ((_tareasAtrasadas ?? 0) > 0)
                      _bienvenidaChip(
                        '$_tareasAtrasadas atrasada${_tareasAtrasadas! > 1 ? 's' : ''}',
                        Colors.red.shade600, Colors.red.shade50,
                      ),
                    if ((_tareasAplazadas ?? 0) > 0)
                      _bienvenidaChip(
                        '$_tareasAplazadas aplazada${_tareasAplazadas! > 1 ? 's' : ''}',
                        Colors.orange.shade700, Colors.orange.shade50,
                      ),
                    if ((_tareasPendientes ?? 0) > 0)
                      _bienvenidaChip(
                        '$_tareasPendientes pendiente${_tareasPendientes! > 1 ? 's' : ''}',
                        Colors.grey.shade700, Colors.grey.shade100,
                      ),
                  ],
                ),
              ),

            const Spacer(),

            // Barra de progreso + countdown
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) {
                  final seg = (3 - (_progressController.value * 3)).ceil();
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
                        'Entrando en ${seg}s...',
                        style: const TextStyle(fontSize: 13, color: Colors.black45),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header verde ─────────────────────────────────────────────
            GestureDetector(
              onLongPress: () => Navigator.push(
                context,
                AppRoutes.slide(const ConfigScreen()),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: _accentGreen,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentGreen.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star, color: Color(0xFFC8102E), size: 28),
                            const SizedBox(width: 10),
                            const Text(
                              'E-CILT',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                        if (_nombreMaquina != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(Icons.precision_manufacturing,
                                  size: 13, color: Colors.white70),
                              const SizedBox(width: 5),
                              Text(
                                _nombreMaquina!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // Hora + turno
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _horaDisplay,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _turnoActual(),
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ── NFC hero ─────────────────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final v1 = _pulseController.value;
                  final v2 = (_pulseController.value + 0.5) % 1.0;
                  return SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: (1 - v1) * 0.55,
                          child: Container(
                            width: 88 + 52 * v1,
                            height: 88 + 52 * v1,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: statusColor,
                                  width: 2.0 * (1 - v1) + 0.5),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: (1 - v2) * 0.55,
                          child: Container(
                            width: 88 + 52 * v2,
                            height: 88 + 52 * v2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: statusColor,
                                  width: 2.0 * (1 - v2) + 0.5),
                            ),
                          ),
                        ),
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor.withValues(alpha: 0.08),
                            border: Border.all(color: statusColor, width: 2),
                          ),
                          child: Icon(Icons.nfc, color: statusColor, size: 48),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // ── Mensaje de estado ─────────────────────────────────────────
            Center(
              child: IntrinsicWidth(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: statusColor, width: 1.8),
                    borderRadius: BorderRadius.circular(14),
                    color: _accesoDenegado
                        ? _accentRed.withValues(alpha: 0.07)
                        : Colors.white,
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 3))
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _mensajeEstado,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: statusColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (_isValidando) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: statusColor, strokeWidth: 3),
                        ),
                      ],
                      if (_accesoDenegado) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.block, color: _accentRed, size: 22),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // ── Ingresar sin tarjeta ──────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¿No tienes tu tarjeta?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _abrirSelectorOperador,
                    icon: const Icon(Icons.badge_outlined, size: 20),
                    label: const Text('Ingresar sin tarjeta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accentGreen,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                          color: _accentGreen.withValues(alpha: 0.6), width: 1.5),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),

            // TextField invisible para el lector de tarjetas
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: 1,
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
            ),
          ],
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
      final maquinas = widget.idMaquinaLocal.split(',').map((e) => e.trim()).toList();
      if (maquinas.isEmpty || maquinas.first.isEmpty) {
        if (mounted) setState(() { _operadores = []; _cargando = false; });
        return;
      }

      final maquinasIn = maquinas.map((e) => '"$e"').join(',');
      final hoy = mockNow.toIso8601String().split('T')[0];

      final responseTurnos = await SupabaseManager.client
          .from('turnos_semana')
          .select('id_operador')
          .eq('fecha', hoy)
          .filter('id_maquina', 'in', '($maquinasIn)');

      final Set<String> idsValidos = (responseTurnos as List)
          .map((e) => e['id_operador'].toString())
          .toSet();

      if (idsValidos.isEmpty) {
        if (mounted) {
          setState(() {
            _operadores = [];
            _cargando = false;
          });
        }
        return;
      }

      final idsIn = idsValidos.map((e) => '"$e"').join(',');

      final responseOps = await SupabaseManager.client
          .from('operadores')
          .select()
          .filter('id_operador', 'in', '($idsIn)')
          .neq('tipo', 'supervisor')
          .order('nombreoperador');

      if (mounted) {
        setState(() {
          _operadores = List<Map<String, dynamic>>.from(responseOps);
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
