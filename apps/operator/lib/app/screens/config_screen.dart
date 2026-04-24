import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_routes.dart';
import 'bienvenida_screen.dart';
import '../../supabase_manager.dart';
import 'dart:convert';
import 'package:shimmer/shimmer.dart';

class ConfigScreen extends StatefulWidget {
  /// true = primera instalación, muestra formulario sin pedir PIN.
  final bool primerInicio;

  const ConfigScreen({super.key, this.primerInicio = false});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with SingleTickerProviderStateMixin {
  static const _accentGreen = Color(0xFF007A3D);
  static const _bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFB), Color(0xFFE8F0F2)],
  );

  final _nuevoPinController = TextEditingController();
  final _searchController = TextEditingController();

  bool _pinVerificado = false;
  bool _pinError = false;
  bool _guardando = false;
  String _pinActual = '1234';
  String _pinIngresado = '';
  
  List<Map<String, dynamic>> _listaMaquinas = [];
  bool _cargandoMaquinas = false;
  List<String> _maquinasSeleccionadas = [];
  String _filtroBusqueda = '';

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _pinVerificado = widget.primerInicio;
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    
    _cargarConfig();
    _cargarMaquinas();
  }

  @override
  void dispose() {
    _nuevoPinController.dispose();
    _searchController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _cargarMaquinas({bool forceRemote = false}) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!forceRemote) {
      final cached = prefs.getString('cache_maquinas');
      if (cached != null) {
        try {
          setState(() {
            _listaMaquinas = List<Map<String, dynamic>>.from(jsonDecode(cached));
          });
        } catch (e) {
          debugPrint('Error caché: $e');
        }
      }
    }

    if (_listaMaquinas.isEmpty || forceRemote) {
      setState(() => _cargandoMaquinas = true);
      try {
        final data = await SupabaseManager.client
            .from('maquinas')
            .select('id_maquina, nombre, linea')
            .eq('implementado', true)
            .order('nombre', ascending: true);
        
        if (!mounted) return;
        
        final listData = List<Map<String, dynamic>>.from(data);
        await prefs.setString('cache_maquinas', jsonEncode(listData));

        setState(() {
          _listaMaquinas = listData;
          _cargandoMaquinas = false;
          _maquinasSeleccionadas.removeWhere(
            (id) => !_listaMaquinas.any((m) => m['id_maquina'] == id)
          );
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _cargandoMaquinas = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $e')),
        );
      }
    }
  }

  Future<void> _cargarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinActual = prefs.getString('admin_pin') ?? '1234';
      final guardada = prefs.getString('id_maquina_local') ?? '';
      _maquinasSeleccionadas = guardada.split(',').where((e) => e.isNotEmpty).toList();
    });
  }

  void _onKeyPress(String value) {
    if (_pinIngresado.length < 6) {
      setState(() {
        _pinIngresado += value;
        _pinError = false;
      });
      if (_pinIngresado == _pinActual) {
        _verificarPin();
      } else if (_pinIngresado.length == _pinActual.length && _pinIngresado != _pinActual) {
        setState(() => _pinError = true);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _pinIngresado = '');
        });
      }
    }
  }

  void _onBackspace() {
    if (_pinIngresado.isNotEmpty) {
      setState(() => _pinIngresado = _pinIngresado.substring(0, _pinIngresado.length - 1));
    }
  }

  void _verificarPin() {
    setState(() {
      _pinVerificado = true;
      _pinError = false;
    });
    _fadeController.forward(from: 0.0);
  }

  Future<void> _guardar() async {
    if (_maquinasSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona al menos una máquina')),
      );
      return;
    }
    
    setState(() => _guardando = true);
    final idMaquina = _maquinasSeleccionadas.join(',');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('id_maquina_local', idMaquina);

    final nuevoPin = _nuevoPinController.text.trim();
    if (nuevoPin.length >= 4) {
      await prefs.setString('admin_pin', nuevoPin);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppRoutes.fade(BienvenidaScreen(idMaquinaLocal: idMaquina)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: _pinVerificado ? _buildSettingsLayout() : _buildPinLayout(),
          ),
        ),
      ),
    );
  }

  // --- UI: PIN LAYOUT ---

  Widget _buildPinLayout() {
    return Column(
      children: [
        const Spacer(),
        const Icon(Icons.lock_person_rounded, size: 80, color: _accentGreen),
        const SizedBox(height: 24),
        const Text(
          'Acceso restringido',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ingresa el PIN de administración',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 48),
        // Dots representativos del PIN
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            bool filled = index < _pinIngresado.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pinError ? Colors.red : (filled ? _accentGreen : Colors.grey.shade300),
                boxShadow: filled ? [BoxShadow(color: _accentGreen.withValues(alpha: 0.3), blurRadius: 8)] : [],
              ),
            );
          }),
        ),
        if (_pinError)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('PIN incorrecto', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        const Spacer(),
        _buildNumPad(),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildNumPad() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        childAspectRatio: 1.3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((val) => _numButton(val)),
          const SizedBox.shrink(),
          _numButton('0'),
          IconButton(
            onPressed: _onBackspace,
            icon: const Icon(Icons.backspace_rounded, size: 32, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _numButton(String val) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: () => _onKeyPress(val),
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Text(
            val,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  // --- UI: SETTINGS LAYOUT ---

  Widget _buildSettingsLayout() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 120,
          floating: false,
          pinned: true,
          backgroundColor: _accentGreen,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(widget.primerInicio ? 'Configuración Inicial' : 'Configuración App', 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            centerTitle: true,
            background: Container(color: _accentGreen),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => _cargarMaquinas(forceRemote: true),
            )
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(Icons.precision_manufacturing, 'Máquinas asignadas a esta tablet'),
                const SizedBox(height: 16),
                _buildMachineSelector(),
                const SizedBox(height: 32),
                _buildSectionHeader(Icons.security, 'Seguridad'),
                const SizedBox(height: 16),
                _buildPinChangeField(),
                const SizedBox(height: 48),
                _buildSaveButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: _accentGreen, size: 24),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildMachineSelector() {
    final filtradas = _listaMaquinas.where((m) => 
      m['nombre'].toString().toLowerCase().contains(_filtroBusqueda.toLowerCase()) ||
      m['id_maquina'].toString().toLowerCase().contains(_filtroBusqueda.toLowerCase())
    ).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar máquina...',
                prefixIcon: const Icon(Icons.search, color: _accentGreen),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _filtroBusqueda = v),
            ),
          ),
          const Divider(height: 1),
          if (_cargandoMaquinas)
            _buildShimmerList()
          else if (filtradas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('No se encontraron máquinas', style: TextStyle(color: Colors.black45)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtradas.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
              itemBuilder: (context, index) {
                final m = filtradas[index];
                final id = m['id_maquina'].toString();
                final isSelected = _maquinasSeleccionadas.contains(id);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: _accentGreen,
                  secondary: CircleAvatar(
                    backgroundColor: isSelected ? _accentGreen.withValues(alpha: 0.1) : Colors.grey.shade100,
                    child: Icon(Icons.settings_input_component, color: isSelected ? _accentGreen : Colors.grey),
                  ),
                  title: Text('${m['nombre']} (${m['linea']})', style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('ID: $id', style: const TextStyle(fontSize: 12)),
                  onChanged: (bool? val) {
                    setState(() {
                      if (val == true) {
                        _maquinasSeleccionadas.add(id);
                      } else {
                        _maquinasSeleccionadas.remove(id);
                      }
                    });
                  },
                );
              },
            ),
          if (_listaMaquinas.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _maquinasSeleccionadas = _listaMaquinas.map((m) => m['id_maquina'].toString()).toList()),
                    child: const Text('Seleccionar todas'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _maquinasSeleccionadas = []),
                    child: const Text('Limpiar selección', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Column(
        children: List.generate(3, (i) => ListTile(
          leading: const CircleAvatar(),
          title: Container(height: 15, color: Colors.white, margin: const EdgeInsets.only(right: 40)),
          subtitle: Container(height: 10, color: Colors.white, margin: const EdgeInsets.only(right: 120, top: 4)),
        )),
      ),
    );
  }

  Widget _buildPinChangeField() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cambiar PIN de administrador', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Si lo dejas vacío, se mantendrá el PIN actual.', style: TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 16),
          TextField(
            controller: _nuevoPinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: InputDecoration(
              hintText: 'Nuevo PIN (mín. 4 dígitos)',
              prefixIcon: const Icon(Icons.password_rounded, color: _accentGreen),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _guardando ? null : _guardar,
        icon: _guardando 
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.check_circle_outline, size: 28),
        label: Text(_guardando ? 'Guardando...' : 'Finalizar Configuración', 
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
      ),
    );
  }
}
