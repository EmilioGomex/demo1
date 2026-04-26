# eCILT — Contexto del Proyecto y Base de Datos (Actualizado)

> Sistema de gestión de tareas CILT (Cleaning, Inspection, Lubrication, Tightening) para planta Heineken.

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
