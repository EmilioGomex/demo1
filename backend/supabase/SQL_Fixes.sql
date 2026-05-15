-- 0. LIMPIEZA DE REGISTROS DE HOY (27/04/2026)
DELETE FROM public.registro_tareas 
WHERE fecha_periodo = '2026-04-27' 
  AND fue_autogenerado = true;

-- 1. ACTUALIZAR RESTRICCIONES DE UNICIDAD
-- Eliminamos todas las restricciones antiguas que podrían entrar en conflicto
ALTER TABLE public.registro_tareas DROP CONSTRAINT IF EXISTS registro_tareas_unique_por_turno;
ALTER TABLE public.registro_tareas DROP CONSTRAINT IF EXISTS registro_tareas_unique_por_turno_operador;
ALTER TABLE public.registro_tareas DROP CONSTRAINT IF EXISTS registro_tareas_unique_asignada;

-- Creamos la restricción definitiva que INCLUYE el turno
-- Esto permite que un operador tenga tareas en diferentes turnos el mismo día
ALTER TABLE public.registro_tareas 
ADD CONSTRAINT registro_tareas_unique_por_turno_operador 
UNIQUE (id_tarea, fecha_periodo, turno, id_operador);

-- 2. ACTUALIZAR FUNCIÓN DE GENERACIÓN CON LÓGICA DE FRECUENCIAS
CREATE OR REPLACE FUNCTION public.generar_registros_diarios(p_turno text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Sincronizamos con la hora local de Ecuador (UTC-5)
    v_fecha date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guayaquil')::date;
    v_dow int := extract(isodow from v_fecha); -- 1=Lunes, 7=Domingo
    v_day int := extract(day from v_fecha);
    v_month int := extract(month from v_fecha);
BEGIN
    INSERT INTO public.registro_tareas (
        id_tarea,
        id_operador,
        fecha_periodo,
        id_maquina,
        turno,
        fecha_limite,
        estado,
        fue_autogenerado
    )
    SELECT 
        t.id_tarea,
        ts.id_operador,
        v_fecha,
        t.id_maquina,
        p_turno,
        -- Límite: Diarias terminan hoy, el resto tiene 7 días de plazo
        CASE 
            WHEN t.frecuencia = 'Diario' THEN (v_fecha + time '23:59:59')
            ELSE (v_fecha + interval '7 days' + time '23:59:59')
        END,
        'Pendiente',
        true
    FROM public.tareas t
    JOIN public.turnos_semana ts ON t.id_maquina = ts.id_maquina
    WHERE ts.turno = p_turno -- Filtramos por el turno que se está procesando
      AND (
          -- 1. Tareas DIARIAS: Solo para los operadores que están de turno HOY
          (t.frecuencia = 'Diario' AND ts.fecha = v_fecha)
          
          OR
          
          -- 2. Tareas SEMANALES+: Se generan hoy LUNES para TODOS los operadores
          -- que tienen turno en esta máquina en algún momento de la semana.
          (t.frecuencia != 'Diario' AND v_dow = 1 
           AND ts.fecha BETWEEN v_fecha AND (v_fecha + interval '6 days')
           AND (
               t.frecuencia = 'Semanal'
               OR (t.frecuencia = 'Quincenal' AND (v_day <= 7 OR v_day BETWEEN 15 AND 21))
               OR (t.frecuencia = 'Mensual' AND v_day <= 7)
               OR (t.frecuencia = 'Trimestral' AND v_day <= 7 AND v_month IN (1, 4, 7, 10))
               OR (t.frecuencia = 'Semestral' AND v_day <= 7 AND v_month IN (1, 7))
               OR (t.frecuencia IN ('Anual', 'Tres años') AND v_day <= 7 AND v_month = 1)
           )
          )
      )
    ON CONFLICT (id_tarea, fecha_periodo, turno, id_operador) DO NOTHING;
END;
$function$;
