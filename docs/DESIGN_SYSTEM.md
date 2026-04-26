# SISTEMA DE DISEÑO - Dashboard eCILT (Emerald Apex)

Este documento define las reglas visuales y técnicas para todos los visuales HTML en Power BI dentro del proyecto eCILT.

## 1. Fundamentos Visuales
- **Tipografía:** `Segoe UI, sans-serif` (Peso 400 para lectura, 600 para títulos, 700 para etiquetas/tags. Evitar 800 para mantener ligereza).
- **Colores de Estado (Semáforo):**
  - **Meta/OK:** `#00A651` (Verde Heineken)
  - **Alerta:** `#F9A825` (Amarillo)
  - **Riesgo:** `#D32F2F` (Rojo)
  - **Máquinas/Info:** `#0078D4` (Azul)
- **Fondos:** `#FFFFFF` (Blanco puro) para tarjetas, `#F9FAFB` para filas de tabla y elementos secundarios.
- **Texto:** `#111827` (Principal), `#4B5563` (Secundario), `#9CA3AF` (Subtextos/Headers).

## 2. Componentes UI (Estilo CSS)
- **Tarjetas (Cards):**
  - Borde: `1px solid #E5E7EB`
  - Border-radius: `8px` (Para un look más industrial y limpio).
  - Padding: `8px` a `12px` (Compacto).
  - Indicador superior/Progreso: Línea de color de `2px` (Elegancia minimalista).
- **Interactividad (Hover):**
  - **PROHIBIDO:** Movimiento (`translate`), sombras pesadas o cursores de mano en elementos informativos.
  - **PERMITIDO:** Cambios sutiles de color de fondo (`#F3F4F6`) o de borde para dar feedback de posición.
- **Iconografía:**
  - Estilo: Minimalista. No usar SVGs externos o complejos.
  - Leyendas: Usar círculos sólidos (`.dot`) de `10px` con el color de estado correspondiente.

## 3. Especificaciones Técnicas (DAX/HTML)
- **Dimensiones Estándar:**
  - KPIs horizontales: `height: 110px`.
  - Visuales de detalle (Dona/Semáforo): `height: 210px`.
- **Tablas de Actividades:**
  - Header: Fijo (Sticky) y estilizado en gris claro (`#9CA3AF`, 8px, uppercase).
  - Filas: Fondo sólido `#F9FAFB` con margen entre filas (`4px`).
  - Indicador de estado: Borde izquierdo de `3px solid` con el color de estado. Sin bordes exteriores.
  - Fuentes: `10px` para títulos (600 weight), `8px` para subtextos.
  - Estados: Etiquetas pill con fondo transparente (`0.08` opacidad) y borde sutil (`0.15` opacidad).
- **Animaciones:**
  - Barras de progreso: `growBar 0.8s ease-out`.
  - Gráficos (Canvas/SVG): Fade-in sutil de `0.6s`.
  - Barras verticales: `growUp 0.8s ease-out`.

---
*Última actualización: 2026-04-26 - Sincronizado con KPIs, Dona, Semáforo, Barras por Área, Timeline y Tabla de Actividades vFinal.*
