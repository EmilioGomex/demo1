# Contexto del Backend Supabase - Proyecto eCILT

Este documento contiene un resumen estructurado del esquema de la base de datos, la lógica de negocio en PostgreSQL y las integraciones del backend del sistema eCILT. Está diseñado para ser provisto como contexto a cualquier asistente de inteligencia artificial.

## 1. Tablas Principales (Esquema Relacional)

### `tareas`
Almacena el catálogo o "plantilla" de las tareas de mantenimiento (CILT).
*   `id_tarea` (UUID, Primary Key)
*   `nombre_tarea` (Text): Nombre descriptivo de la tarea.
*   `frecuencia` (Text): Frecuencia de ejecución (`Diario`, `Semanal`, `Quincenal`, `Mensual`, `Semestral`).
*   `tipo` (Text): Categoría CILT (`Limpieza`, `Inspección`, `Lubricación`, `Ajuste`).
*   `es_compartida` (Boolean): Indica si múltiples operadores pueden interactuar con ella.

### `registro_tareas`
Almacena las instancias vivas a ejecutar de cada tarea. Es la tabla con mayor transaccionalidad.
*   `id` (UUID, Primary Key)
*   `id_tarea` (UUID, Foreign Key -> `tareas.id_tarea`)
*   `id_operador` (UUID, Foreign Key -> `operadores.id_operador`, Nullable): Operador asignado.
*   `id_maquina` (UUID, Foreign Key -> `maquinas.id_maquina`): Máquina a la que pertenece la tarea.
*   `fecha_periodo` (Date): Fecha base que identifica a qué periodo corresponde la tarea (ej. 1 de abril para una mensual).
*   `fecha_limite` (Timestampz/Date): Fecha y hora límite para su ejecución.
*   `estado` (Text): Estado de la instancia (`Pendiente`, `Completado`, `Atrasado`).
*   `fecha_completado` (Timestampz): Cuándo se completó.
*   `parsable_job_id` (Text, Nullable): ID del Job generado en la integración con Parsable.
*   `motivo_bloqueo` (Text): Razón si la tarea ha sido aplazada.
*   `veces_aplazada` (Integer): Contador de cuántas veces se aplazó.

### `operadores`
Usuarios del sistema.
*   `id_operador` (UUID, Primary Key)
*   `nombreoperador` (Text)
*   `linea` (Text): Línea de producción a la que pertenece.
*   `foto_operador` (Text): URL de su fotografía.

### `maquinas`
Equipos de la planta.
*   `id` (UUID, Primary Key)
*   `id_maquina` (Text, Unique): Código corto de la máquina (ej. `9991`, `MAQ-5357`).
*   `nombre` (Text)
*   `linea` (Text): `Latas`, `Botellas`, `Utilidades`, etc.
*   `area` (Text, GENERATED): Calculado automáticamente a partir de `linea`.
*   `implementado` (Boolean): Indica si la máquina está activa en el sistema.

### `semaforo_maquina`
Registro histórico del estado de salud de cada máquina **por turno y período**. Hay una fila por combinación única `(id_maquina, turno, fecha_periodo)`.
*   `id` (UUID, Primary Key)
*   `id_maquina` (Text, FK → `maquinas.id_maquina`)
*   `estado` (Text): `Verde`, `Amarillo` o `Rojo`.
*   `fecha_actualizacion` (Timestamptz): Última actualización del registro.
*   `turno` (Text): `Mañana`, `Tarde` o `Noche`.
*   `fecha_periodo` (Date): Fecha del período (default: `hoy_ec()`).
*   `total_tareas`, `completadas`, `pendientes`, `atrasadas` (Integer): Contadores del estado de tareas.

> ⚠️ **IMPORTANTE para la RPi:** Para leer el estado actual del semáforo desde `supabase_realtime_to_mqtt.py`, se debe filtrar por `id_maquina`, el `turno` activo en Ecuador y la `fecha_periodo` de hoy. El uso de `.single()` falla porque hay múltiples filas por máquina.

### `turnos_semana`
Tabla de configuración de turnos semanales, utilizada por la App en Flutter para filtrar qué operadores deben aparecer en el carrusel de inicio de sesión según el día de la semana y la hora (Mañana, Tarde, Noche).

---

## 2. Funciones SQL y Lógica de Negocio (PostgreSQL)

### `public.hoy_ec()`
Función utilitaria esencial que retorna la fecha actual forzada a la zona horaria de Ecuador (`America/Guayaquil`). Se utiliza en todas las validaciones de negocio para evitar desajustes horarios con el servidor en UTC.

### `public.generar_registros_diarios(p_turno text)`
Esta es la función principal o "motor" que se encarga de instanciar los registros en `registro_tareas`. 
*   **Lógica de Frecuencias:** Utiliza `hoy_ec()` para validar si corresponde generar la tarea. 
    *   `Diario`: Se genera todos los días.
    *   `Semanal`: Se genera únicamente los Lunes (`date_trunc('week', v_fecha_hoy)`).
    *   `Quincenal`: Se genera los días 1 y 15 del mes.
    *   `Mensual`: Se genera únicamente el día 1 del mes (`date_trunc('month', v_fecha_hoy)`).
    *   `Semestral`: Se genera únicamente el 1 de enero y el 1 de julio.
*   **Prevención de Duplicados:** Usa sentencias `NOT EXISTS` comparando el `id_tarea` y la `v_fecha_periodo` para asegurarse de no insertar la misma tarea dos veces para el mismo ciclo.

### Triggers y Función de Semáforo
*   Existe la función `evaluar_todos_semaforos()` que recalcula el `estado` en la tabla `semaforo_maquina` para todas las máquinas. Se ejecuta vía `pg_cron` (Jobs 7, 8, 9) en los tres turnos del día.
*   El estado se determina según el porcentaje de tareas pendientes/atrasadas para el turno y fecha actuales.

---

## 3. Automatización (pg_cron)

El sistema utiliza la extensión `pg_cron` de Supabase para la automatización, ejecutando scripts periódicos críticos:
*   **Generación de Registros:** `generar_registros_diarios` se dispara automáticamente en los siguientes horarios de Ecuador (Job IDs 13, 14, 15):
    *   **Mañana:** 06:00 AM
    *   **Tarde:** 02:00 PM (14:00)
    *   **Noche:** 10:00 PM (22:00)
*   **Marcado de Atrasos:** Función que se ejecuta a medianoche (00:00 AM) para cambiar las tareas pendientes vencidas a estado `Atrasado`.
*   **Evaluación de Semáforos:** Funciones programadas (ej. Job IDs 7, 8, 9) que ejecutan `select evaluar_todos_semaforos()` en los tres turnos para garantizar que el estado de salud de las máquinas sea correcto.

---

## 4. Edge Functions (Integración a Terceros)

### `parsable-proxy`
Función serverless en Deno/TypeScript alojada en `supabase/functions/parsable-proxy/`.
*   Sirve de intermediario seguro entre la App móvil en Flutter y la API de **Parsable**.
*   **Endpoints conocidos:** 
    1.  `createModular`: Crea un Job en Parsable con atributos predefinidos, equipo, plantilla y usuarios.
    2.  `sendExecDataWithResult`: Completa automáticamente pasos dentro del Job de Parsable enviando datos capturados desde eCILT (por ejemplo, el nombre del operador que lo ejecuta).

---

## 5. Arquitectura del Tiempo (Ecuador UTC-5)

El sistema eCILT es estrictamente dependiente del tiempo para validar turnos, vencimientos y cálculos. Se ha consolidado una directriz global para usar exclusivamente la hora de Ecuador (`America/Guayaquil` / `UTC-5`) en todas las capas del sistema:

*   **Capa Base de Datos (Supabase):** Se utiliza `public.hoy_ec()` en cálculos para forzar el huso horario sin importar la configuración del servidor, permitiendo conversiones absolutas desde Timestamptz.
*   **Capa Panel Admin (JS/HTML):** Para no sufrir desfases por los husos horarios del administrador que entra al sitio, toda la visualización de fechas fuerza el parámetro `{ timeZone: 'America/Guayaquil' }`. Adicionalmente, las peticiones hacia los endpoints PostgREST anexan el offset temporal de Ecuador explícitamente al filtrar los Timestamptz (ej. `T23:59:59-05:00`).
*   **Capa App Flutter (`TimeManager`):** En `app_operadores`, todos los módulos leen la hora a través del objeto singleton `TimeManager.now()`.
    *   Este archivo utilitario (`lib/app/utils/time_manager.dart`) obtiene la hora local del dispositivo (que por geografía de las tablets será `UTC-5`).
    *   Permite a los desarrolladores insertar **simulaciones temporales** reasignando la variable `_simulatedTime`. Esto propaga al instante viajes en el tiempo (pasado/futuro) a toda la lógica de presentación de "Vence Hoy/Mañana", turnos y estados visuales para debuggear toda la aplicación sin tocar el código fuente interno.

---

## 5.1. Despliegue Web (Netlify)

El módulo `app_operadores` se despliega como una aplicación web estática en Netlify.

*   **Build:** `flutter build web --release`.
*   **Persistencia de Configuración:** La selección de máquinas se almacena en el **LocalStorage** del navegador (vía `shared_preferences`). Esto permite que la configuración persista entre reinicios de la tablet.
*   **Manejo de Rutas (SPA):** Se requiere un archivo `_redirects` con el contenido `/* /index.html 200` para evitar errores 404 al refrescar páginas.
*   **PWA:** La aplicación está configurada como PWA, permitiendo ser instalada en la pantalla de inicio de tablets iOS/Android para una experiencia de pantalla completa.

---

## 6. Módulo `rpi_app` — reComputer (ECILT-VARIOPACK)

### Hardware
- **Dispositivo:** Seeed reComputer R100x corriendo Raspbian (Raspberry Pi OS)
- **Hostname:** `reComputer-R100x`
- **Usuario principal:** `recomputer`

### Arquitectura de la reComputer

```
Lector RFID (tty1)
    └── rfid_to_supabase.py  ──────────────────→  Supabase (tabla: lecturas_rfid)
                                                         ↓
Supabase Realtime  ←───── supabase_realtime_to_mqtt.py
                                    ↓
                            MQTT Broker (Mosquitto :1883)
                                    ↓
                            Node-RED (flows.json)
                                    ↓
                    Semáforo RS-485 (Modbus RTU /dev/ttyAMA3)
                    Relé (Modbus RTU /dev/ttyAMA2)

ngrok_start.sh  →  Túnel HTTP (puerto 1880 Node-RED)  →  Power Automate (URL notificada)
monitor_internet.py  →  Ping 8.8.8.8 cada 10s  →  reboot si 6 fallos consecutivos
```

### Scripts (`rpi_app/scripts/`)

| Script | Descripción |
|--------|-------------|
| `rfid_to_supabase.py` | Lee tarjetas RFID desde `stdin` (modo `--mode input`), inserta registros en `lecturas_rfid` vía Supabase REST con reintentos. Soporta también modo serial y publicación MQTT opcional. |
| `supabase_realtime_to_mqtt.py` | Se suscribe a cambios en `semaforo_maquina` (máquina `9991`) vía Supabase Realtime. Publica el estado (`Verde/Amarillo/Rojo`) al topic MQTT `maquina/9991/estado`. Guarda estado local en `estado_semaforo.json` como respaldo. Reconexión automática cada 10 min. |
| `monitor_internet.py` | Watchdog de conectividad. Hace ping a `8.8.8.8` cada 10 segundos. Si hay 6 fallos consecutivos (1 minuto sin internet) ejecuta `reboot`. |
| `ngrok_start.sh` | Levanta ngrok apuntando al puerto 1880 (Node-RED). Detecta la URL pública y la envía vía POST a un endpoint de Power Automate. Monitorea cada 5s si la URL cambia y la actualiza automáticamente. |

### Servicios systemd (`rpi_app/services/`)

| Servicio | Script | Detalles |
|----------|--------|---------|
| `rfid.service` | `rfid_to_supabase.py` | `User=recomputer`, `StandardInput=tty`, `TTYPath=/dev/tty1`, carga variables desde `.env`, `RestartSec=3` |
| `supabase_mqtt.service` | `supabase_realtime_to_mqtt.py` | `User=recomputer`, `After=network-online.target`, `RestartSec=5` |
| `ngrok.service` | `ngrok_start.sh` | `User=recomputer`, `Type=simple`, `Restart=on-failure`, `RestartSec=5` |
| `monitor_internet.service` | `monitor_internet.py` | `User=root` (necesita permisos para reboot), `After=network-online.target` |

### Node-RED (`rpi_app/nodered/flows.json`)

Tabs configurados:
- **Relé** — Lectura/escritura de 8 relés vía Modbus (`/dev/ttyAMA2`)
- **Semáforo Fijo** — Control directo del semáforo (registro Modbus `194`)
- **Semáforo Parpadeo** — Modo parpadeo del semáforo
- **Lector RFID** — Escucha topic `rfid/access`, inserta en Supabase vía HTTP request
- **MQTT Semáforo** — Escucha `maquina/9991/estado`, convierte estado a valor Modbus y escribe en semáforo + sonido (registro `3`)
- **Semáforo Modbus sonido** — Control de pista de audio vía Modbus
- **RPI to Automate** — Endpoints HTTP `/data` y `/send` para integración con Power Automate

Clientes Modbus configurados:
- `PRUEBA`: `/dev/ttyAMA2` (relé), RTU 9600 bps
- `Semaforo-rs485`: `/dev/ttyAMA3` (semáforo), RTU 9600 bps

### Variables de entorno (`.env`)
Cargado automáticamente por `rfid.service` desde `/home/recomputer/.env`. Incluye:
- `SUPABASE_URL` / `SUPABASE_KEY` — Credenciales Supabase
- `MQTT_BROKER`, `MQTT_PORT`, `MQTT_TOPIC`
- `SERIAL_DEVICE` (default: `/dev/ttyUSB0`)
- Configuración de reintentos HTTP

---

## 7. Bugs Corregidos — Integración Semáforo RPi (2026-04-19)

Durante la sesión del 19 de abril de 2026 se identificaron y corrigieron los siguientes problemas en la cadena Supabase → MQTT → Node-RED → Semáforo físico:

### Bug 1: Consulta con `.single()` fallaba (tabla `semaforo_maquina`)
- **Causa:** `supabase_realtime_to_mqtt.py` consultaba `.single()` sin filtrar por turno ni fecha. La tabla tiene **múltiples filas por máquina** (una por `turno` × `fecha_periodo`), por lo que `.single()` lanzaba excepción.
- **Fix:** La consulta ahora filtra por `id_maquina`, `turno` y `fecha_periodo` del día actual. Usa `.limit(1)`.

### Bug 2: Script no sabía qué turno consultar
- **Causa:** No existía lógica para determinar el turno activo (Mañana/Tarde/Noche).
- **Fix:** Se agregó `get_turno_actual()` que calcula el turno según hora Ecuador (`UTC-5`): Mañana=06-14h, Tarde=14-22h, Noche=22-06h.

### Bug 3: Payload MQTT era un dict Python stringificado (inválido)
- **Causa:** El script publicaba `str({'maquina': '9991', 'estado': 'Verde'})` — comillas simples, no es JSON válido.
- **Fix:** Ahora publica `json.dumps({"maquina": "9991", "estado": "Verde"})` — JSON válido.

### Bug 4: Nodo MQTT de Node-RED con `auto-detect` rompía `function 3`
- **Causa:** El nodo `mqtt in` del tab "MQTT Semáforo" tenía `"datatype": "auto-detect"`. Al recibir JSON válido, Node-RED lo parseaba a objeto JS antes de llegar a `function 3`, que intentaba `.replace()` sobre un objeto → `TypeError`.
- **Fix:** Cambiado a `"datatype": "utf8"` en el nodo `433a5d4825c835d3` del `flows.json`. El payload llega como string y el flujo `function 3 → json node → function 2` funciona correctamente.

### Flujo correcto final
```
supabase_realtime_to_mqtt.py
  → publica: {"maquina": "9991", "estado": "Verde"}
      ↓
Node-RED mqtt in (utf8) → string
      ↓
function 3: replace(' → ") → no-op (ya es JSON válido)
      ↓
json node: parsea a objeto JS
      ↓
function 2: estado Verde → Modbus 19
      ↓
Semáforo RS-485 registro 194 = 19 🟢
```

### Nota sobre logs del servicio
El servicio corre Python sin `PYTHONUNBUFFERED=1`, por lo que `print()` no aparecen en `journalctl`. Para ver output completo, ejecutar manualmente:
```bash
python3 /home/recomputer/supabase_realtime_to_mqtt.py
```

---

## 8. Limpieza de Base de Datos — Sesión 2026-04-19

### Schema confirmado de `tareas` y `pasos_tarea`

- `tareas` tiene `id_maquina` (Text) como FK directa a `maquinas.id_maquina`.
- `pasos_tarea` tiene FK a `tareas.id_tarea` con `ON DELETE CASCADE` → borrar una tarea elimina sus pasos automáticamente.

### SQL de limpieza ejecutado

Se eliminaron tareas y pasos de **todas las máquinas excepto `9991` y `9183`**:

```sql
BEGIN;
-- 1. Eliminar instancias de ejecución
DELETE FROM registro_tareas WHERE id_maquina NOT IN ('9991', '9183');
-- 2. Eliminar tareas (CASCADE elimina pasos_tarea automáticamente)
DELETE FROM tareas WHERE id_maquina NOT IN ('9991', '9183');
COMMIT;
```

> ⚠️ `pasos_tarea` NO necesita DELETE manual gracias al `ON DELETE CASCADE`.

---

## 9. Bugs Corregidos — admin_web GTS (2026-04-19)

Módulo: `Gestión de Tareas y Pasos` en `admin_web/index.html`.

### Bug 1: `refreshCurrentView` nunca refrescaba el GTS
- **Causa:** `currentView.includes('GTS')` pero el valor real es `'Gestión de Tareas y Pasos'`.
- **Fix:** `currentView === 'Gestión de Tareas y Pasos'`.

### Bug 2: `moveStep` violaba `UNIQUE(id_tarea, numeropaso)`
- **Causa:** `Promise.all` actualizaba todos los `numeropaso` en paralelo → colisión momentánea en DB.
- **Fix:** Doble batch: primero asigna offset `+1000`, luego asigna los números finales.

### Bug 3 + OPT: `fetchData` con query duplicada y `select('*')` innecesario
- Se eliminó la llamada a `buildHistoricoQuery` que era descartada inmediatamente.
- `select('*')` reemplazado por campos específicos: `id, estado, fecha_limite, id_maquina`.

### Optimización: Lazy-load filtros del Histórico
- Los 2 queries a `operadores` y `maquinas` para los filtros ahora se ejecutan solo cuando el usuario navega a "Histórico de CILTs" por primera vez (flag `filterOptionsLoaded`).

---

## 10. Bug Corregido — Flutter `tareas_screen.dart` (2026-04-19)

### `frecuencia` no definida en `_procesarYNavigar`
- **Síntoma:** Error de compilación en línea 396: `The getter 'frecuencia' isn't defined for the type '_TareasScreenState'`.
- **Causa:** `frecuencia` era local de `_buildTareaCard` pero se usaba en `_procesarYNavigar` sin estar definida en ese scope.
- **Fix:** Añadido `final frecuencia = tarea?['frecuencia'] ?? 'Otro';` dentro de `_procesarYNavigar`.
