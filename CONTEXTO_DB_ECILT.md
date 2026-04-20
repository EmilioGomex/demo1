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
*   `id_maquina` (UUID, Primary Key)
*   `nombre` (Text)
*   `semaforo_maquina` (Text): Estado de salud del equipo (`Verde`, `Amarillo`, `Rojo`). Se calcula mediante Triggers.

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

### Triggers y Semáforos
*   Existe un trigger asociado a los cambios en `registro_tareas` que, al actualizarse el `estado` de una tarea (ej. pasar a `Atrasado`), dispara un cálculo que actualiza automáticamente la columna `semaforo_maquina` en la tabla `maquinas`.

---

## 3. Automatización (pg_cron)

El sistema utiliza la extensión `pg_cron` de Supabase para la automatización, ejecutando scripts periódicos críticos:
*   **Evaluación de Semáforos:** Funciones programadas (ej. Job IDs 7, 8, 9) que ejecutan `select evaluar_todos_semaforos()` en los turnos Mañana, Tarde y Noche para garantizar que el estado de salud de las máquinas sea correcto.
*   **Marcado de Atrasos:** Función que se ejecuta a medianoche para cambiar las tareas pendientes vencidas a estado `Atrasado`.
*   **Generación de Registros:** `generar_registros_diarios` se dispara automáticamente en diferentes momentos del día (Job IDs 13, 14, 15) pasando como parámetro el turno correspondiente (`Mañana`, `Tarde`, `Noche`).

---

## 4. Edge Functions (Integración a Terceros)

### `parsable-proxy`
Función serverless en Deno/TypeScript alojada en `supabase/functions/parsable-proxy/`.
*   Sirve de intermediario seguro entre la App móvil en Flutter y la API de **Parsable**.
*   **Endpoints conocidos:** 
    1.  `createModular`: Crea un Job en Parsable con atributos predefinidos, equipo, plantilla y usuarios.
    2.  `sendExecDataWithResult`: Completa automáticamente pasos dentro del Job de Parsable enviando datos capturados desde eCILT (por ejemplo, el nombre del operador que lo ejecuta).
