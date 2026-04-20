# Contexto del Backend Supabase - Proyecto eCILT

Este documento contiene un resumen estructurado del esquema de la base de datos, la lógica de negocio en PostgreSQL y las integraciones del backend del sistema eCILT. Actualizado tras la fase de optimización de rendimiento y resiliencia (2026-04-20).

## 1. Tablas Principales (Esquema Relacional)

> [!IMPORTANT]
> **Arquitectura de IDs:** El sistema utiliza un esquema de doble ID. 
> - `id` (UUID): Llave primaria interna de Supabase.
> - `id_tarea`, `id_operador`, `id_maquina` (TEXT): Son las **llaves de negocio** usadas para todas las relaciones entre tablas (Foreign Keys). Todas las consultas de la App y Scripts deben usar estos campos de texto.

### `tareas`
*   `id` (UUID, PK)
*   `id_tarea` (Text, Unique): ID de negocio (ej: `MAQ-123-456`).
*   `nombre_tarea` (Text): Nombre descriptivo.
*   `frecuencia` (Text): `Diario`, `Semanal`, `Quincenal`, `Mensual`, `Trimestral`, `Semestral`, `Tres años`.
*   `tipo` (Text): `Limpieza`, `Inspección`, `Lubricación`, `Ajuste`.
*   `id_maquina` (Text, FK -> `maquinas.id_maquina`).

### `registro_tareas`
*   `id` (UUID, PK)
*   `id_tarea` (Text, FK -> `tareas.id_tarea`)
*   `id_operador` (Text, FK -> `operadores.id_operador`, Nullable).
*   `id_maquina` (Text, FK -> `maquinas.id_maquina`).
*   `fecha_periodo` (Date): Identificador del ciclo.
*   `fecha_limite` (Timestampz): Deadline.
*   `estado` (Text): `Pendiente`, `Completado`, `Atrasado`.

### `operadores`
*   `id` (UUID, PK)
*   `id_operador` (Text, Unique): El ID del carné RFID (ej: "609").
*   `nombreoperador` (Text)
*   `cedula` (Text, Unique)
*   `linea` (Text): `Latas`, `Botellas`, `Utilidades`, etc.

### `maquinas`
*   `id` (UUID, PK)
*   `id_maquina` (Text, Unique): Código corto (ej: `9991`).
*   `nombre` (Text)
*   `implementado` (Boolean): Activa/Inactiva.

---

## 2. Optimización de Rendimiento (Sesión 2026-04-20)

Para maximizar el uso del plan gratuito de Supabase y mejorar la velocidad, se implementaron las siguientes estrategias:

### 2.1. Consolidación de Consultas (RPC)
Se creó la función `get_dashboard_data` para que la App Flutter obtenga toda la información del panel de tareas en **un solo viaje de red**.
*   **Parámetros:** `p_id_operador_texto` (text), `p_id_maquinas` (text[]), `p_inicio_hoy`, `p_fin_hoy`.
*   **Retorno:** Un JSON con `operador`, `maquinas` (nombres) y `tareas` (lista completa).
*   **Seguridad:** Incluye manejo de errores si el ID del operador no es un UUID válido.

### 2.2. Proyección de Columnas
En `bienvenida_screen.dart`, las consultas ya no usan `.select()`. Ahora especifican campos: `.select('id_operador, nombreoperador, foto_operador')`. Esto reduce drásticamente el peso de la respuesta (Egress).

### 2.3. Caché Local (Shared Preferences)
En `config_screen.dart`, el catálogo de máquinas se almacena localmente. La App solo consulta la base de datos si la caché está vacía o si el usuario presiona "Refrescar".

---

## 3. Lógica de Negocio y Automatización

### `public.hoy_ec()`
Retorna `now() AT TIME ZONE 'America/Guayaquil'`. Fundamental para evitar errores de desfase UTC.

### `pg_cron` (Jobs Automáticos)
- **Generación de Tareas:** Se ejecuta a las 06:00, 14:00 y 22:00 (Ecuador).
- **Marcado de Atrasos:** A las 00:00 cambia `Pendiente` -> `Atrasado` si la fecha límite pasó.
- **Semaforización:** Recalcula el estado de salud de las máquinas en cada cambio de turno.

---

## 4. Módulo `rpi_app` (Resiliencia Industrial)

Los scripts de la Raspberry Pi fueron rediseñados para entornos de red inestables:

### `supabase_realtime_to_mqtt.py` (Semáforo)
- **No Bloqueante:** Usa `asyncio` y el loop nativo de `paho-mqtt`.
- **Persistencia Local:** Guarda el último estado del semáforo en `estado_semaforo.json`. Si el internet falla al arrancar, lee el archivo local para encender la luz correcta de inmediato.
- **Auto-Recuperación:** Se reinicia internamente cada 10 minutos para limpiar conexiones "zombies".

### `rfid_to_supabase.py` (Lector RFID)
- **Worker Thread:** El envío a Supabase ocurre en un hilo separado. La lectura de tarjetas nunca se detiene.
- **Cola de Reintento (Buffer):** Si no hay internet, las lecturas se guardan en una cola interna. El script reintenta enviarlas cada 5 segundos hasta que tengan éxito. **Ninguna marca de asistencia se pierde.**
- **Debounce:** Bloqueo de 2 segundos para la misma tarjeta para evitar registros duplicados accidentales.

---

## 5. Despliegue y Mantenimiento

- **Netlify:** Despliegue de la App Flutter como SPA (`_redirects` obligatorio).
- **Admin Panel:** Uso de inserciones en lote (Batch Inserts) de 200 en 200 para importaciones masivas de Excel.
- **TimeManager:** Singleton en Flutter para viajes en el tiempo (Simulación) durante el testing.
