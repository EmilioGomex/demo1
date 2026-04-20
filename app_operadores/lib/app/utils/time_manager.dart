class TimeManager {
  // ----------------------------------------------------------------------
  // CONFIGURACIÓN DE FECHA SIMULADA
  // ----------------------------------------------------------------------
  // Para volver a la hora real del dispositivo, deja `_simulatedTime` en null.
  // Para simular una hora específica en TODA la app, descomenta la línea
  // y pon la fecha deseada. Ejemplo: DateTime(2026, 4, 20, 7, 45)
  // ----------------------------------------------------------------------
  
  static final DateTime? _simulatedTime = DateTime(2026, 4, 20, 7, 45); // DateTime(2026, 4, 20, 7, 45);

  /// Retorna la hora actual o la hora simulada si está configurada.
  static DateTime now() {
    if (_simulatedTime != null) {
      return _simulatedTime!;
    }
    return DateTime.now();
  }
}
