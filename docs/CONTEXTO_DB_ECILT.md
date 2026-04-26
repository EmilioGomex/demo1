# eCILT — Contexto del Proyecto y Base de Datos (Actualizado)

> Sistema de gestión de tareas CILT (Cleaning, Inspection, Lubrication, Tightening) para planta Heineken.

## Sistema de Diseño (Emerald Apex)
Todos los desarrollos visuales deben seguir el estándar definido en [DESIGN_SYSTEM.md](file:///c:/eCILT/demo1/docs/DESIGN_SYSTEM.md).
- **Tipografía:** `Segoe UI` (Estándar para todo el dashboard).
- **Estética:** Minimalista Industrial (Emerald Apex), sincronizada en KPIs, Dona, Semáforo, Barras por Área, Timeline y Tablas.
- **UX:** Sin efectos de movimiento en hover (solo cambios de color sutiles).

## Arquitectura

| Componente | Stack | Ruta |
|---|---|---|
| Admin Web | HTML/CSS/JS + Supabase JS SDK | `apps/admin/` |
| App Operador | Flutter + Supabase SDK | `apps/operator/` |
| Backend | Supabase (PostgreSQL + Edge Functions) | `backend/supabase/` |
| Scripts | Python (procesamiento CILT) / DAX (Power BI) | `scripts/` |
| Docs & data | CSV snapshots de tablas | `docs/` |

---

## Esquema de Base de Datos (Supabase/PostgreSQL)

### `operadores`
| Columna | Tipo | Nota |
|---|---|---|
| id | uuid PK | |
| id_operador | text UK | Código único |
| nombreoperador | text | |
| linea | text | Latas, Botellas, Utilidades, Cocimiento, Filtracion, Fermentacion, Logistica, Ingenieria |
| foto_operador | text | URL (nullable) |
| tipo | text | operador / supervisor |
| activo | bool | default true |
| cedula | text UK | Documento de identidad |

### `maquinas`
| Columna | Tipo | Nota |
|---|---|---|
| id | uuid PK | |
| id_maquina | text UK | Identificador único |
| nombre | text | |
| linea | text | |
| area | text (GEN) | Brewing, Packaging, Utilidades, Logistica, Ingenieria (basado en linea) |
| implementado | bool | |

### `tareas`
| Columna | Tipo | Nota |
|---|---|---|
| id | uuid PK | |
| id_tarea | text UK | |
| nombre_tarea | text | |
| frecuencia | text | Diario, Semanal, Quincenal, Mensual, Trimestral, Semestral, Tres años |
| tipo | text | Limpieza, Inspección, Lubricación, Ajuste |
| id_maquina | text FK | -> maquinas.id_maquina |
| es_compartida | bool | |

### `pasos_tarea` (NUEVA)
| Columna | Tipo | Nota |
|---|---|---|
| id | uuid PK | |
| id_tarea | text FK | -> tareas.id_tarea |
| numeropaso | int | |
| descripcion | text | |
| imagenurl | text | |

### `registro_tareas`
| Columna | Tipo | Nota |
|---|---|---|
| id | uuid PK | |
| id_tarea | text FK | -> tareas.id_tarea |
| id_operador | text FK | -> operadores.id_operador (nullable) |
| fecha_periodo | date | |
| fecha_completado | timestamptz | (nullable) |
| fecha_limite | timestamptz | |
| estado | text | Pendiente, Completado, Atrasado |
| fue_autogenerado | bool | |
| id_maquina | text FK | -> maquinas.id_maquina |
| parsable_job_id | text | |
| motivo_bloqueo | text | |
| foto_evidencia | text | |
| veces_aplazada | int | |
| turno | text | Mañana, Tarde, Noche |

---

## Reglas de Negocio Clave

- **Semáforo**: Trigger `trg_actualizar_semaforo_realtime` recalcula `semaforo_maquina` al INSERT/UPDATE/DELETE.
- **Áreas**: 
  - `Packaging`: Latas, Botellas
  - `Brewing`: Cocimiento, Fermentacion, Filtracion
  - `Utilidades`, `Logistica`, `Ingenieria`: Mismo nombre.
- **Turnos**: Mañana, Tarde, Noche.
- **Integración Parsable**: 
  - La sincronización se realiza mediante la Edge Function `parsable-proxy` (proxy transparente hacia la API de Parsable).
  - **Formato del Job**: `CILT - [Línea] - [Nombre de Máquina] - [Tipo de Tarea] - [Nombre de Tarea]`.
  - Acciones sincronizadas: "Completar Tarea" (`completeWithOpts`) y "Marcar Pendiente/Desmarcar" (`uncomplete`). 
  - *Nota*: Los bloqueos ("No puedo realizarla", ej. *Frecuencia incorrecta*) solo actualizan el registro local en Supabase y aplazan la fecha, no envían evento a Parsable actualmente.

---

## Patrones de Visualización en Power BI (DAX)

### Estándar Visual (vFinal 2026-04-26)
- **Tipografía**: Siempre `Segoe UI, sans-serif`.
- **Iconografía**: **No usar iconos SVG** complejos. Representar estados con círculos sólidos (`.dot`) o barras de color.
- **Colores de Estado**:
  - **Meta/OK**: `#00A651` (Verde Heineken)
  - **Alerta**: `#F9A825` (Amarillo)
  - **Riesgo**: `#D32F2F` (Rojo)
- **Visuales Complejos**:
  - **HTML Cards + Detalle**: Integra tarjetas de máquinas con una tabla de actividades dinámica. Filtra por estado (Atrasado, Pendiente, Completado) y máquina.
  - **Límites de Datos**: Para asegurar el rendimiento con grandes volúmenes, la tabla de "Atrasadas" carga hasta **2,000 filas** (TOPN).
- **Abandono de Negritas Pesadas**: Se prohíbe el uso de `font-weight: 800`. El estándar es `600` (títulos) y `700` (etiquetas).
- **Nombres de Visualización (Overrides)**: 
  - `Inspector de botellas vacias` -> Se visualiza como **IBV** para optimizar espacio.
- **Interactividad**: Solo usar cambios de fondo sutiles (`#F3F4F6`).
- **Operadores**: Si el `id_operador` es nulo, mostrar **"Compartido"**. Los nombres deben estar **centrados** en su columna.

### Lógica de Desempeño
- **Origen de Datos**: Se utiliza la tabla `Registro Tareas` para cálculos en tiempo real. Esto permite que el visual reaccione dinámicamente a cualquier filtro de fecha, línea o área aplicado en el reporte.
- **Cálculo de Cumplimiento**: 
  - **Total**: `COUNTROWS('Registro Tareas')`
  - **Completadas**: `CALCULATE(COUNTROWS('Registro Tareas'), 'Registro Tareas'[estado] = "Completado")`
  - **Porcentaje**: `DIVIDE(Completadas, Total, 0)`
- **Filtrado de Relevancia**: Se consideran solo máquinas con `maquinas[implementado] = TRUE` y con carga de trabajo (`Total > 0`).
- **Priorización (TOP 3)**: Se utiliza `TOPN(3, ..., [Porcentaje], ASC)` para identificar las 3 máquinas con el desempeño más bajo.


