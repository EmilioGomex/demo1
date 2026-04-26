import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

// --- CONFIGURACIÓN ---
const SUPABASE_URL = 'https://czxyfzxjwzaykwoxyjah.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU';
const VIEWS = ['Histórico de CILTs', 'Gestión de Tareas y Pasos', 'Gestión de Operadores', 'Carga de Horarios'];
const LINEAS = ['Latas', 'Botellas', 'Utilidades', 'Cocimiento', 'Filtracion', 'Fermentacion', 'Logistica', 'Ingenieria'];
const PAGE_SIZE = 24;

let supabase, currentView, currentTable, editingId, deleteId;
let currentPage = 1, totalCount = 0;

// DOM SHORTCUTS
const el = (id) => document.getElementById(id);
const toggleClass = (id, cls, condition) => {
    const target = el(id);
    if (target) {
        condition ? target.classList.add(cls) : target.classList.remove(cls);
    }
};

const ICON = {
    user: `<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>`,
    check: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"/></svg>`,
    xmark: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>`,
    cycle: `<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>`
};

async function fetchData(filters = {}) {
    toggleClass('app-loading', 'loading-hidden', false);
    
    const from = (currentPage - 1) * PAGE_SIZE;
    const to = from + PAGE_SIZE - 1;

    let query = supabase.from('registro_tareas')
        .select(`id, estado, fecha_limite, turno, foto_evidencia, tareas(id_tarea, nombre_tarea, frecuencia, tipo), operadores(nombreoperador), maquinas(nombre)`, { count: 'exact' });

    if (filters.start) query = query.gte('fecha_limite', filters.start);
    if (filters.end) query = query.lte('fecha_limite', filters.end);
    if (filters.area) query = query.eq('operadores.linea', filters.area);
    if (filters.tipo) query = query.eq('tareas.tipo', filters.tipo);

    const { data, count, error } = await query.range(from, to).order('fecha_limite', { ascending: false });
    
    toggleClass('app-loading', 'loading-hidden', true);
    if (error) { console.error(error); return; }

    totalCount = count || 0;
    renderCards(data);
}

function renderCards(data) {
    const grid = el('card-grid');
    if (!data || !data.length) {
        grid.innerHTML = '<div class="col-span-full p-20 text-center text-gray-500">No hay registros</div>';
        return;
    }

    grid.innerHTML = data.map(item => {
        const t = item.tareas || {};
        const o = item.operadores || {};
        const m = item.maquinas || {};
        const st = item.estado || 'Pendiente';
        const cls = st === 'Completado' ? 'badge-done' : (st === 'Atrasado' ? 'badge-late' : 'badge-pending');
        
        return `
        <div class="data-card p-5 flex flex-col gap-4 cursor-pointer hover:border-emerald-500/50 transition-all" onclick="showCILTDetail('${item.id}')">
            <div class="flex justify-between items-start">
                <span class="badge ${cls}">
                    ${st === 'Completado' ? ICON.check : (st === 'Atrasado' ? ICON.xmark : ICON.cycle)}
                    ${st}
                </span>
                <span class="text-xs font-mono text-gray-400 bg-gray-900/50 px-2 py-0.5 rounded border border-gray-800">
                    ${new Date(item.fecha_limite).toLocaleDateString('es-EC')}
                </span>
            </div>

            <div>
                <div class="text-[10px] text-emerald-500/60 font-bold uppercase tracking-widest mb-1">${m.nombre || 'Sin máquina'}</div>
                <div class="font-bold text-white text-lg leading-tight">${t.nombre_tarea || 'Sin nombre'}</div>
            </div>

            <div class="flex gap-2">
                <span class="text-[10px] font-bold bg-gray-800/50 text-gray-400 px-2 py-1 rounded border border-gray-700/50">${item.turno || '-'}</span>
                <span class="text-[10px] font-bold bg-blue-900/10 text-blue-400 px-2 py-1 rounded border border-blue-900/30">${t.frecuencia || '-'}</span>
            </div>

            <div class="mt-auto pt-4 border-t border-white/5 flex items-center gap-2.5">
                <div class="w-6 h-6 rounded-full bg-gray-800 flex items-center justify-center text-gray-500">${ICON.user}</div>
                <span class="text-xs text-gray-300 truncate">${o.nombreoperador || 'Sin asignar'}</span>
            </div>
        </div>`;
    }).join('');
}

async function showCILTDetail(id) {
    toggleClass('app-loading', 'loading-hidden', false);
    try {
        const { data, error } = await supabase.from('registro_tareas')
            .select('*, tareas(*), operadores(*), maquinas(*)')
            .eq('id', id)
            .single();
        
        if (error) throw error;

        const t = data.tareas || {};
        const o = data.operadores || {};
        const m = data.maquinas || {};

        const { data: steps } = await supabase.from('pasos_tarea')
            .select('*')
            .eq('id_tarea', t.id_tarea)
            .order('numeropaso', { ascending: true });

        el('modal-detail-title').textContent = t.nombre_tarea || 'Detalle';
        el('detail-machine').textContent = `${m.nombre || '-'} (${m.area || '-'})`;
        el('detail-type').textContent = t.tipo || '-';
        el('detail-freq').textContent = t.frecuencia || '-';
        el('detail-operator').textContent = o.nombreoperador || '-';
        el('detail-shift').textContent = data.turno || '-';
        el('detail-limit').textContent = new Date(data.fecha_limite).toLocaleString();

        const stepsContainer = el('detail-steps-container');
        if (steps && steps.length) {
            stepsContainer.innerHTML = steps.map(s => `
                <div class="flex gap-4 p-3 rounded-xl bg-white/5 border border-white/5">
                    <div class="w-6 h-6 rounded-lg bg-emerald-500/20 flex items-center justify-center text-[10px] font-black text-emerald-500">${s.numeropaso}</div>
                    <div class="text-[11px] text-gray-300">${s.descripcion}</div>
                </div>
            `).join('');
            el('detail-steps-section').classList.remove('hidden');
        } else {
            el('detail-steps-section').classList.add('hidden');
        }

        toggleClass('modal-detail', 'hidden', false);
    } catch (err) {
        alert(err.message);
    } finally {
        toggleClass('app-loading', 'loading-hidden', true);
    }
}

// Export for global access
window.showCILTDetail = showCILTDetail;
window.fetchData = fetchData;
