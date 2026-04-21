import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../supabase_manager.dart';
import '../utils/app_routes.dart';
import '../widgets/inactivity_wrapper.dart';
import 'tareas_screen.dart';
import 'bienvenida_screen.dart';
import '../utils/time_manager.dart';

class SupervisorScreen extends StatefulWidget {
  final String nombreSupervisor;
  final String idMaquinaLocal;
  final String? fotoSupervisor;

  const SupervisorScreen({
    super.key,
    required this.nombreSupervisor,
    required this.idMaquinaLocal,
    this.fotoSupervisor,
  });

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _DatosDia {
  final DateTime fecha;
  final int total;
  final int completadas;
  _DatosDia(this.fecha, this.total, this.completadas);
  double get porcentaje => total == 0 ? 0 : completadas / total * 100;
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  static const _accentGreen = Color(0xFF007A3D);
  static const _background = Color(0xFFF8FAFB);

  List<dynamic> maquinas = [];
  List<dynamic> operadores = [];
  String? maquinaSeleccionada;
  bool cargando = true;
  bool _errorCarga = false;

  Map<String, Map<String, int>> _resumen = {};
  bool _cargandoResumen = false;
  String? _filtroAlerta;

  List<_DatosDia> _datosChart = [];
  bool _cargandoChart = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      cargando = true;
      _errorCarga = false;
    });

    try {
      final results = await Future.wait([
        SupabaseManager.client
            .from('maquinas')
            .select('id_maquina, nombre, linea')
            .eq('implementado', true)
            .order('nombre')
            .timeout(const Duration(seconds: 10)),
        SupabaseManager.client
            .from('operadores')
            .select('id_operador, nombreoperador, id_maquina, foto_operador')
            .neq('tipo', 'supervisor')
            .order('nombreoperador')
            .timeout(const Duration(seconds: 10)),
      ]);

      setState(() {
        maquinas = results[0];
        operadores = results[1];
        cargando = false;
      });
      _cargarResumen();
      _cargarDatosChart();
    } catch (e) {
      debugPrint('Error cargando datos supervisor: $e');
      setState(() {
        cargando = false;
        _errorCarga = true;
      });
    }
  }

  Future<void> _cargarResumen() async {
    final ops = _operadoresFiltrados;
    if (ops.isEmpty) return;
    setState(() => _cargandoResumen = true);

    try {
      final ids = ops.map((o) => o['id_operador'].toString()).toList();
      final hoy = TimeManager.now();
      final hoyInicio = DateTime(hoy.year, hoy.month, hoy.day);
      final inicioHoy = hoyInicio.toUtc().toIso8601String();
      final finHoy = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59, 999)
          .toUtc()
          .toIso8601String();

      // machineId → operatorIds: para atribuir tareas compartidas a sus operadores
      final machineMap = <String, List<String>>{};
      for (final op in ops) {
        final mId = op['id_maquina']?.toString();
        if (mId != null) {
          machineMap.putIfAbsent(mId, () => []).add(op['id_operador'].toString());
        }
      }
      final machineIds = machineMap.keys.toList();

      final nuevo = <String, Map<String, int>>{
        for (final op in ops)
          op['id_operador'].toString(): {
            'atrasadas': 0,
            'pendientes': 0,
            'completadas': 0,
            'aplazadas': 0,
          }
      };

      final estadoFiltro =
          'estado.in.("Pendiente","Atrasado"),'
          'and(estado.eq.Completado,fecha_completado.gte.$inicioHoy,fecha_completado.lte.$finHoy)';

      // Tareas individuales (id_operador asignado)
      final tareasOp = await SupabaseManager.client
          .from('registro_tareas')
          .select('id_operador, estado, fecha_limite, fecha_completado, motivo_bloqueo')
          .filter('id_operador', 'in', '(${ids.join(",")})')
          .or(estadoFiltro)
          .timeout(const Duration(seconds: 10));

      // Tareas compartidas de máquina (id_operador IS NULL)
      List<dynamic> tareasMaq = [];
      if (machineIds.isNotEmpty) {
        tareasMaq = await SupabaseManager.client
            .from('registro_tareas')
            .select('id_maquina, estado, fecha_limite, fecha_completado, motivo_bloqueo')
            .filter('id_maquina', 'in', '(${machineIds.join(",")})')
            .filter('id_operador', 'is', 'null')
            .or(estadoFiltro)
            .timeout(const Duration(seconds: 10));
      }

      void clasificar(Map<String, int> counts, dynamic t) {
        final estado = (t['estado'] ?? '').toString().toLowerCase();
        final motivo = t['motivo_bloqueo']?.toString() ?? '';
        if (estado == 'completado') {
          counts['completadas'] = counts['completadas']! + 1;
        } else if (motivo.isNotEmpty) {
          counts['aplazadas'] = counts['aplazadas']! + 1;
        } else if (estado == 'atrasado') {
          counts['atrasadas'] = counts['atrasadas']! + 1;
        } else {
          bool esAtrasada = false;
          try {
            final fl = DateTime.parse(t['fecha_limite'].toString()).toLocal();
            esAtrasada = DateTime(fl.year, fl.month, fl.day).isBefore(hoyInicio);
          } catch (_) {}
          if (esAtrasada) {
            counts['atrasadas'] = counts['atrasadas']! + 1;
          } else {
            counts['pendientes'] = counts['pendientes']! + 1;
          }
        }
      }

      for (final t in tareasOp) {
        final idOp = t['id_operador']?.toString() ?? '';
        if (nuevo.containsKey(idOp)) clasificar(nuevo[idOp]!, t);
      }

      // Tareas compartidas: se cuentan para cada operador de esa máquina
      for (final t in tareasMaq) {
        final idMaq = t['id_maquina']?.toString() ?? '';
        for (final opId in (machineMap[idMaq] ?? [])) {
          if (nuevo.containsKey(opId)) clasificar(nuevo[opId]!, t);
        }
      }

      if (mounted) setState(() { _resumen = nuevo; _cargandoResumen = false; });
    } catch (e) {
      debugPrint('Error cargando resumen supervisor: $e');
      if (mounted) setState(() => _cargandoResumen = false);
    }
  }

  Future<void> _cargarDatosChart() async {
    final ops = _operadoresFiltrados;
    if (ops.isEmpty) return;
    setState(() => _cargandoChart = true);

    try {
      final ids = ops.map((o) => o['id_operador'].toString()).toList();
      final hoy = TimeManager.now();
      final hace7 = DateTime(hoy.year, hoy.month, hoy.day)
          .subtract(const Duration(days: 6))
          .toUtc()
          .toIso8601String();

      final tareas = await SupabaseManager.client
          .from('registro_tareas')
          .select('estado, fecha_limite')
          .filter('id_operador', 'in', '(${ids.join(",")})')
          .gte('fecha_limite', hace7)
          .timeout(const Duration(seconds: 10));

      // Agrupar por día de fecha_limite
      final Map<String, List<dynamic>> porDia = {};
      for (final t in tareas) {
        final fechaStr = t['fecha_limite']?.toString();
        if (fechaStr == null) continue;
        try {
          final fl = DateTime.parse(fechaStr).toLocal();
          final clave =
              '${fl.year}-${fl.month.toString().padLeft(2, '0')}-${fl.day.toString().padLeft(2, '0')}';
          porDia.putIfAbsent(clave, () => []).add(t);
        } catch (_) {}
      }

      // Construir lista de 7 días
      final List<_DatosDia> datos = [];
      for (int i = 6; i >= 0; i--) {
        final dia =
            DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: i));
        final clave =
            '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
        final listaDia = porDia[clave] ?? [];
        final total = listaDia.length;
        final completadas = listaDia
            .where((t) =>
                (t['estado'] ?? '').toString().toLowerCase() == 'completado')
            .length;
        datos.add(_DatosDia(dia, total, completadas));
      }

      if (mounted) {
        setState(() { _datosChart = datos; _cargandoChart = false; });
      }
    } catch (e) {
      debugPrint('Error cargando chart: $e');
      if (mounted) setState(() => _cargandoChart = false);
    }
  }

  List<dynamic> get _operadoresFiltrados => maquinaSeleccionada == null
      ? operadores
      : operadores
          .where((o) => o['id_maquina'] == maquinaSeleccionada)
          .toList();

  List<dynamic> get _operadoresMostrados {
    var lista = List<dynamic>.from(_operadoresFiltrados);

    if (_filtroAlerta != null && !_cargandoResumen) {
      lista = lista.where((o) {
        final counts = _resumen[o['id_operador'].toString()];
        if (_filtroAlerta == 'atrasadas') return (counts?['atrasadas'] ?? 0) > 0;
        if (_filtroAlerta == 'aplazadas') return (counts?['aplazadas'] ?? 0) > 0;
        return true;
      }).toList();
    }

    if (!_cargandoResumen && _resumen.isNotEmpty) {
      lista.sort((a, b) {
        final ca = _resumen[a['id_operador'].toString()];
        final cb = _resumen[b['id_operador'].toString()];

        int prioridad(Map<String, int>? c) {
          if (c == null) return 3;
          if ((c['atrasadas'] ?? 0) > 0) return 0;
          if ((c['aplazadas'] ?? 0) > 0) return 1;
          if ((c['pendientes'] ?? 0) > 0) return 2;
          return 3;
        }

        final diff = prioridad(ca).compareTo(prioridad(cb));
        if (diff != 0) return diff;
        return (a['nombreoperador'] ?? '').toString()
            .compareTo((b['nombreoperador'] ?? '').toString());
      });
    }

    return lista;
  }

  Widget _buildFiltroChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: _filtroAlerta == null,
            selectedColor: _accentGreen.withValues(alpha: 0.15),
            checkmarkColor: _accentGreen,
            onSelected: (_) => setState(() => _filtroAlerta = null),
          ),
          ChoiceChip(
            label: const Text('Con atrasadas'),
            selected: _filtroAlerta == 'atrasadas',
            selectedColor: Colors.red.shade50,
            checkmarkColor: Colors.red.shade600,
            labelStyle: TextStyle(
              color: _filtroAlerta == 'atrasadas' ? Colors.red.shade600 : null,
              fontWeight: _filtroAlerta == 'atrasadas' ? FontWeight.w600 : null,
            ),
            onSelected: (_) => setState(() =>
                _filtroAlerta = _filtroAlerta == 'atrasadas' ? null : 'atrasadas'),
          ),
          ChoiceChip(
            label: const Text('Con aplazadas'),
            selected: _filtroAlerta == 'aplazadas',
            selectedColor: Colors.orange.shade50,
            checkmarkColor: Colors.orange.shade800,
            labelStyle: TextStyle(
              color: _filtroAlerta == 'aplazadas' ? Colors.orange.shade800 : null,
              fontWeight: _filtroAlerta == 'aplazadas' ? FontWeight.w600 : null,
            ),
            onSelected: (_) => setState(() =>
                _filtroAlerta = _filtroAlerta == 'aplazadas' ? null : 'aplazadas'),
          ),
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

  void _irATareas(dynamic op) {
    final idMaquina = op['id_maquina']?.toString() ?? '';
    Navigator.push(
      context,
      AppRoutes.slide(TareasScreen(
        idOperador: op['id_operador'].toString(),
        idMaquinaLocal: idMaquina,
      )),
    ).then((_) {
      _cargarResumen();
      _cargarDatosChart();
    });
  }

  Widget _buildSupervisorCard() {
    return Container(
      decoration: BoxDecoration(
        color: _accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _accentGreen,
            backgroundImage: (widget.fotoSupervisor != null &&
                    widget.fotoSupervisor!.isNotEmpty)
                ? CachedNetworkImageProvider(widget.fotoSupervisor!)
                : null,
            onBackgroundImageError: (_, __) {},
            child: (widget.fotoSupervisor == null ||
                    widget.fotoSupervisor!.isEmpty)
                ? const Icon(Icons.person, color: Colors.white, size: 32)
                : null,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nombreSupervisor,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: _accentGreen, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Rol: Supervisor',
                        style: TextStyle(
                          fontSize: 13,
                          color: _accentGreen,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaquinaDropdown() {
    return InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon:
            const Icon(Icons.precision_manufacturing, color: _accentGreen),
        contentPadding: EdgeInsets.zero,
      ),
      child: DropdownButton<String?>(
        value: maquinaSeleccionada,
        isExpanded: true,
        underline: const SizedBox(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        hint: const Text('Todas las máquinas',
            style: TextStyle(color: Colors.black45)),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('— Todas las máquinas —',
                style: TextStyle(color: Colors.black54)),
          ),
          ...maquinas.map<DropdownMenuItem<String?>>((m) => DropdownMenuItem(
                value: m['id_maquina'],
                child: Text('${m['nombre']} (${m['linea']})'),
              )),
        ],
        onChanged: (value) {
          setState(() => maquinaSeleccionada = value);
          _cargarResumen();
          _cargarDatosChart();
        },
      ),
    );
  }

  Widget _buildChart() {
    final tieneData = _datosChart.any((d) => d.total > 0);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: !tieneData && !_cargandoChart
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bar_chart,
                          color: _accentGreen, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Cumplimiento últimos 7 días',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      if (_cargandoChart)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accentGreen,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 130,
                    child: _cargandoChart && _datosChart.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: _accentGreen))
                        : BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: 100,
                              minY: 0,
                              barGroups: _datosChart
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final pct = e.value.porcentaje;
                                final color = e.value.total == 0
                                    ? Colors.grey.shade200
                                    : pct >= 80
                                        ? _accentGreen
                                        : pct >= 50
                                            ? Colors.orange.shade400
                                            : Colors.red.shade400;
                                return BarChartGroupData(
                                  x: e.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: e.value.total == 0 ? 4 : pct,
                                      color: color,
                                      width: 22,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(5)),
                                    ),
                                  ],
                                );
                              }).toList(),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 26,
                                    getTitlesWidget: (value, _) {
                                      final i = value.toInt();
                                      if (i < 0 ||
                                          i >= _datosChart.length) {
                                        return const SizedBox();
                                      }
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _nombreDia(_datosChart[i]
                                              .fecha
                                              .weekday),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    interval: 50,
                                    getTitlesWidget: (value, _) => Text(
                                      '${value.toInt()}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: 50,
                                getDrawingHorizontalLine: (_) => FlLine(
                                  color: Colors.grey.shade200,
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, _, rod, __) {
                                    final d = _datosChart[group.x];
                                    if (d.total == 0) return null;
                                    return BarTooltipItem(
                                      '${rod.toY.toStringAsFixed(0)}%\n${d.completadas}/${d.total}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  // Leyenda
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendaDot(_accentGreen, '≥80%'),
                      const SizedBox(width: 12),
                      _legendaDot(Colors.orange.shade400, '50–79%'),
                      const SizedBox(width: 12),
                      _legendaDot(Colors.red.shade400, '<50%'),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
    );
  }

  Widget _legendaDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  String _nombreDia(int weekday) {
    const dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return dias[weekday - 1];
  }

  Widget _buildOperadorCard(dynamic op) {
    final idOp = op['id_operador'].toString();
    final nombre = op['nombreoperador']?.toString() ?? 'Operador';
    final foto = op['foto_operador']?.toString() ?? '';
    final counts = _resumen[idOp];
    final atrasadas = counts?['atrasadas'] ?? 0;
    final aplazadas = counts?['aplazadas'] ?? 0;
    final pendientes = counts?['pendientes'] ?? 0;
    final completadas = counts?['completadas'] ?? 0;
    final total = atrasadas + aplazadas + pendientes + completadas;
    final tieneAlerta = atrasadas > 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tieneAlerta ? Colors.red.shade200 : Colors.grey.shade200,
          width: tieneAlerta ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _irATareas(op),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _accentGreen.withValues(alpha: 0.12),
                  child: ClipOval(
                    child: foto.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: foto,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.person,
                                color: _accentGreen,
                                size: 30),
                          )
                        : const Icon(Icons.person,
                            color: _accentGreen, size: 30),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_cargandoResumen)
                        SizedBox(
                          height: 6,
                          width: 80,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.grey.shade200,
                            color: _accentGreen,
                          ),
                        )
                      else if (total == 0)
                        Text(
                          'Sin tareas hoy',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (atrasadas > 0)
                              _chip(
                                '$atrasadas atrasada${atrasadas > 1 ? 's' : ''}',
                                Colors.red.shade600,
                                Colors.red.shade50,
                              ),
                            if (aplazadas > 0)
                              _chip(
                                '$aplazadas aplazada${aplazadas > 1 ? 's' : ''}',
                                Colors.orange.shade800,
                                Colors.orange.shade50,
                              ),
                            if (pendientes > 0)
                              _chip(
                                '$pendientes pendiente${pendientes > 1 ? 's' : ''}',
                                Colors.grey.shade700,
                                Colors.grey.shade100,
                              ),
                            if (completadas > 0)
                              _chip(
                                '$completadas hecha${completadas > 1 ? 's' : ''}',
                                Colors.green.shade700,
                                Colors.green.shade50,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
      ),
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
        title: const Text('Supervisor',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            AppRoutes.fade(
                BienvenidaScreen(idMaquinaLocal: widget.idMaquinaLocal)),
            (route) => false,
          ),
        ),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          size: 64, color: Colors.black26),
                      const SizedBox(height: 16),
                      const Text(
                        'Error al cargar los datos',
                        style: TextStyle(
                            fontSize: 18, color: Colors.black54),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          setState(() => _errorCarga = false);
                          _cargarDatos();
                        },
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSupervisorCard(),
                      _buildMaquinaDropdown(),
                      const SizedBox(height: 16),
                      _buildChart(),
                      Row(
                        children: [
                          const Text(
                            'Operadores',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildFiltroChips(),
                      Expanded(
                        child: _operadoresMostrados.isEmpty
                            ? Center(
                                child: Text(
                                  _filtroAlerta != null
                                      ? 'Ningún operador con tareas ${_filtroAlerta == 'atrasadas' ? 'atrasadas' : 'aplazadas'}'
                                      : 'No hay operadores para esta máquina',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade500),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _operadoresMostrados.length,
                                itemBuilder: (_, i) =>
                                    _buildOperadorCard(
                                        _operadoresMostrados[i]),
                              ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
