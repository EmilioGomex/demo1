import 'dart:async';
import 'package:flutter/material.dart';

/// Detecta inactividad táctil y llama [onTimeout] tras [timeout] sin toques.
/// Coloca este widget envolviendo el Scaffold de pantallas autenticadas.
class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  final VoidCallback onTimeout;

  const InactivityWrapper({
    super.key,
    required this.child,
    required this.onTimeout,
    this.timeout = const Duration(minutes: 5),
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (!mounted) return;
      // Solo actúa si esta ruta es la activa (no si hay otra pantalla encima)
      if (ModalRoute.of(context)?.isCurrent == true) {
        widget.onTimeout();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
