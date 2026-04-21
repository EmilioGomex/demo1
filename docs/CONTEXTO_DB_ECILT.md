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

## 3. Lógica de Negocio y Automatización (Actualizado 2026-04-21)

### `public.hoy_ec()` / `public.ahora_ec()`
Funciones para normalizar el tiempo a `America/Guayaquil` (UTC-5). Todo el sistema (App, DB, Cron) debe usar estas funciones para comparaciones de fecha.

### `pg_cron` (Jobs Automáticos)
- **Generación de Tareas:** 07:00, 15:00 y 23:00 (Mañana, Tarde, Noche).
- **Marcado de Atrasos:** 05:00 AM (Medianoche Ecuador) ejecuta `marcar_tareas_atrasadas()`.
- **Seguro de Semáforos:** 07:10, 15:10 y 23:10 ejecuta `evaluar_todos_semaforos()`.

---

## 4. Motor de Generación de Tareas
Refactorizado para soportar frecuencias complejas y evitar duplicados.

### 4.1. Frecuencias Soportadas
- **Diario:** Se genera en cada turno. Deadline: fin del turno.
- **Semanal:** Solo los Lunes (Mañana). Deadline: +6 días (Domingo).
- **Mensual:** Primer Lunes del mes. Deadline: +6 días.
- **Quincenal:** Segundo Lunes del mes. Deadline: +6 días.
- **Superiores (Trimestral/Semestral/Anual):** Primer Lunes del periodo correspondiente.

### 4.2. Asignación de Operadores
- **Tareas No-Compartidas:** La función consulta la tabla `turnos_semana` (Excel de horarios) y asigna la tarea directamente al `id_operador` programado para ese turno/máquina.
- **Tareas Compartidas:** Se generan solo en el turno de la Mañana con `id_operador = NULL`. Cualquiera puede hacerlas.

### 4.3. Restricciones de Integridad
- **Constraint:** `registro_tareas_unique_por_turno` -> `UNIQUE (id_tarea, fecha_periodo, turno)`.
- Resuelve el error de "duplicate key" permitiendo la misma tarea en diferentes turnos.

---

## 5. Sistema de Semáforos (Real-Time + Failsafe)
El semáforo ya no tiene "amnesia" (mira más allá del día de hoy).

### 5.1. Lógica de Colores (Jerarquía)
1.  🔴 **Rojo:** Existe AL MENOS una tarea en estado `Atrasado` o `Pendiente` con `fecha_limite` vencida (no importa el día).
2.  🟡 **Amarillo:** No hay atrasos, pero existen tareas `Pendientes` (del turno actual o semanales vigentes).
3.  🟢 **Verde:** Máquina al día.

### 5.2. Sincronización
- **Tiempo Real:** Gatillado por `trg_actualizar_semaforo_realtime` en la tabla `registro_tareas`.
- **Backup (Cron):** Los jobs de `evaluar_todos_semaforos()` actúan como barredora automática.

---

## 6. Módulo `rpi_app` (Resiliencia Industrial)

Los scripts de la Raspberry Pi fueron rediseñados para entornos de red inestables:

### `supabase_realtime_to_mqtt.py` (Semáforo)
- **No Bloqueante:** Usa `asyncio` y el loop nativo de `paho-mqtt`.
- **Persistencia Local:** Guarda el último estado del semáforo en `estado_semaforo.json`.

### `rfid_to_supabase.py` (Lector RFID)
- **Worker Thread:** El envío a Supabase ocurre en un hilo separado.
- **Cola de Reintento (Buffer):** Si no hay internet, las lecturas se guardan en una cola interna.

---

## 7. Despliegue y Mantenimiento

- **Netlify:** Despliegue de la App Flutter como SPA (`_redirects` obligatorio).
- **Admin Panel:** Uso de inserciones en lote (Batch Inserts) de 200 en 200.
- **TimeManager:** Singleton en Flutter para viajes en el tiempo (Simulación) durante el testing.
