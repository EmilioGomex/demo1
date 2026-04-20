import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_routes.dart';
import 'bienvenida_screen.dart';
import '../../supabase_manager.dart';

class ConfigScreen extends StatefulWidget {
  /// true = primera instalación, muestra formulario sin pedir PIN.
  final bool primerInicio;

  const ConfigScreen({super.key, this.primerInicio = false});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  static const _accentGreen = Color(0xFF007A3D);

  final _pinController = TextEditingController();
  final _maquinaController = TextEditingController();
  final _nuevoPinController = TextEditingController();

  bool _pinVerificado = false;
  bool _pinError = false;
  bool _guardando = false;
  String _pinActual = '1234';
  
  List<Map<String, dynamic>> _listaMaquinas = [];
  bool _cargandoMaquinas = false;
  List<String> _maquinasSeleccionadas = [];

  @override
  void initState() {
    super.initState();
    _pinVerificado = widget.primerInicio;
    _cargarConfig();
    _cargarMaquinas();
  }

  Future<void> _cargarMaquinas() async {
    setState(() => _cargandoMaquinas = true);
    try {
      final data = await SupabaseManager.client
          .from('maquinas')
          .select('id_maquina, nombre')
          .order('nombre', ascending: true);
      
      if (!mounted) return;
      setState(() {
        _listaMaquinas = List<Map<String, dynamic>>.from(data);
        _cargandoMaquinas = false;
        
        // Remove selected that no longer exist
        _maquinasSeleccionadas.removeWhere(
          (id) => !_listaMaquinas.any((m) => m['id_maquina'] == id)
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoMaquinas = false);
      debugPrint('Error cargando máquinas: $e');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _maquinaController.dispose();
    _nuevoPinController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinActual = prefs.getString('admin_pin') ?? '1234';
      final guardada = prefs.getString('id_maquina_local') ?? '';
      _maquinaController.text = guardada;
      _maquinasSeleccionadas = guardada.split(',').where((e) => e.isNotEmpty).toList();
    });
  }

  void _verificarPin() {
    if (_pinController.text == _pinActual) {
      setState(() {
        _pinVerificado = true;
        _pinError = false;
        _pinController.clear();
      });
    } else {
      setState(() => _pinError = true);
    }
  }

  Future<void> _guardar() async {
    if (_maquinasSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona al menos una máquina')),
      );
      return;
    }
    final idMaquina = _maquinasSeleccionadas.join(',');

    setState(() => _guardando = true);

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
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: _accentGreen,
        title: const Text('Configuración',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: !widget.primerInicio,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(28),
            child: _pinVerificado ? _buildConfigForm() : _buildPinForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildPinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, color: _accentGreen, size: 40),
        const SizedBox(height: 16),
        const Text(
          'Acceso de administrador',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ingresa el PIN para acceder a la configuración.',
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'PIN',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            errorText: _pinError ? 'PIN incorrecto' : null,
            prefixIcon: const Icon(Icons.pin, color: _accentGreen),
            counterText: '',
          ),
          onChanged: (_) => setState(() => _pinError = false),
          onSubmitted: (_) => _verificarPin(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            onPressed: _verificarPin,
            child: const Text('Entrar'),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.settings, color: _accentGreen, size: 32),
            const SizedBox(width: 12),
            Text(
              widget.primerInicio
                  ? 'Configuración inicial'
                  : 'Configuración',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (widget.primerInicio) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Primera instalación — configura el ID de la máquina asignada a esta tablet.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        const Text('Máquinas asignadas',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        if (_cargandoMaquinas)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: _accentGreen, strokeWidth: 2),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _listaMaquinas.map((maquina) {
                final id = maquina['id_maquina'].toString();
                final isSelected = _maquinasSeleccionadas.contains(id);
                return FilterChip(
                  label: Text(maquina['nombre']?.toString() ?? id),
                  selected: isSelected,
                  selectedColor: _accentGreen.withValues(alpha: 0.15),
                  checkmarkColor: _accentGreen,
                  labelStyle: TextStyle(
                    color: isSelected ? _accentGreen : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _maquinasSeleccionadas.add(id);
                      } else {
                        _maquinasSeleccionadas.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 24),
        const Text('Cambiar PIN de administrador',
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Deja vacío para mantener el PIN actual.',
            style: TextStyle(fontSize: 12, color: Colors.black45)),
        const SizedBox(height: 8),
        TextField(
          controller: _nuevoPinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: InputDecoration(
            hintText: 'Nuevo PIN (mín. 4 dígitos)',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            prefixIcon:
                const Icon(Icons.lock_outline, color: _accentGreen),
            counterText: '',
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar y continuar',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _guardando ? null : _guardar,
          ),
        ),
      ],
    );
  }
}
