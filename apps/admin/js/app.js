import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

// --- CONFIGURACIÓN ---
const SUPABASE_URL = 'https://czxyfzxjwzaykwoxyjah.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU';
const VIEWS = ['Histórico de CILTs', 'Gestión de Tareas y Pasos', 'Gestión de Operadores', 'Carga de Horarios'];
const LINEAS = ['Latas', 'Botellas', 'Utilidades', 'Cocimiento', 'Filtracion', 'Fermentacion', 'Logistica', 'Ingenieria'];
const FRECUENCIAS_VALIDAS = ['Diario', 'Semanal', 'Quincenal', 'Mensual', 'Trimestral', 'Semestral', 'Tres años'];

const PAGE_SIZE = 24;      // Paginación Principal
const GTS_PAGE_SIZE = 50;  // Paginación para Tareas/Pasos

let supabase, currentView, currentTable, editingId, deleteId;
let currentPage = 1, totalCount = 0;
let filterOptionsLoaded = false; // OPT: lazy-load filtros Histórico

// Estado del Navegador GTS
let gtsState = { level: 'lines', line: null, machine: null, task: null, machineName: '', taskName: '' };
let gtsPage = 1; // Pagina interna del GTS

// DOM SHORTCUTS
const el = (id) => document.getElementById(id);
const toggleClass = (id, cls, condition) => {
    const target = el(id);
    if (target) {
        condition ? target.classList.add(cls) : target.classList.remove(cls);
    }
};
window.toggleClass = toggleClass;

// --- SIDEBAR TOGGLE ---
window.toggleSidebar = () => {
    document.querySelector('.sidebar').classList.toggle('collapsed');
};
el('sidebar-toggle').addEventListener('click', toggleSidebar);

// Escapa valores para usarlos como atributos HTML (evita que comillas rompan el markup)
const esc = s => String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

// Navegación GTS desde data-attributes (evita el bug de comillas en onclick)
window.navGTSCard = (cardEl) => {
    const level = cardEl.dataset.level;
    const id    = cardEl.dataset.id;
    const name  = cardEl.dataset.name;
    navGTS(level, id, null, name);
};

// --- BIBLIOTECA DE ICONOS SVG ---
const ICON = {
    edit:  `<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/></svg>`,
    trash: `<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>`,
    plant: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/></svg>`,
    gear:  `<svg class="w-8 h-8 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>`,
    task:  `<svg class="w-8 h-8 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/></svg>`,
    user:  `<svg class="w-3.5 h-3.5 inline-block flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>`,
    line:  `<svg class="w-3.5 h-3.5 inline-block flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5"/></svg>`,
    cycle: `<svg class="w-3 h-3 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/></svg>`,
    arrow: `<svg class="w-3.5 h-3.5 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"/></svg>`,
    image: `<svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>`,
    check: `<svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"/></svg>`,
    xmark: `<svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>`,
    info:  `<svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`,
    // Iconos por Área
    latas: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>`,
    botellas: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2l1 1v12a2 2 0 01-2 2H10a2 2 0 01-2-2V7l1-1zM11 12h2m-2 4h2"/></svg>`,
    utilidades: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/></svg>`,
    cocimiento: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.99 7.99 0 0120 13a7.98 7.98 0 01-2.343 5.657z"/></svg>`,
    filtracion: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"/></svg>`,
    fermentacion: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/></svg>`,
    logistica: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/></svg>`,
    ingenieria: `<svg class="w-10 h-10 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>`,
    // Iconos de Máquinas
    filler: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.691.387a6 6 0 01-3.86.517l-2.387-.477a2 2 0 00-1.022.547l-1.168.96a2 2 0 00-.472 2.768l1.618 2.428a2 2 0 002.768.472l1.168-.96a2 2 0 011.022-.547l2.387-.477a6 6 0 013.86-.517l.691-.387a6 6 0 003.86-.517l2.387.477a2 2 0 011.022.547l1.168.96a2 2 0 00.472-2.768l-1.618-2.428a2 2 0 00-2.768-.472l-1.168.96z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 3v9m0 0l-3-3m3 3l3-3"/></svg>`,
    pasteurizer: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 21a9 9 0 100-18 9 9 0 000 18z"/></svg>`,
    packer: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>`,
    palletizer: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/></svg>`,
    labeller: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 7h10v10H7zM7 11h10M9 7v10M15 7v10"/></svg>`,
    washer: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 10h18M7 15h1m4 0h1m4 0h1m-7 4h1m4 0h1M9 7h1m4 0h1M12 3v2"/></svg>`,
    inspector: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg>`,
};

function getMachineIcon(name) {
    const n = name.toLowerCase();
    if (n.includes('llenadora') || n.includes('modulfill')) return ICON.filler;
    if (n.includes('pasteurizador') || n.includes('pz') || n.includes('bt4')) return ICON.pasteurizer;
    if (n.includes('etiquetadora') || n.includes('bt5')) return ICON.labeller;
    if (n.includes('paletizadora') || n.includes('modulpal') || n.includes('pressant')) return ICON.palletizer;
    if (n.includes('variopac') || n.includes('varioline') || n.includes('encajonadora') || n.includes('desencajonadora')) return ICON.packer;
    if (n.includes('lavadora')) return ICON.washer;
    if (n.includes('inspector')) return ICON.inspector;
    return ICON.gear;
}

function getLineInfo(line) {
    const map = {
        'Latas': { icon: ICON.latas, colorCls: 'text-blue-300', bgCls: 'bg-blue-500/10', borderCls: 'border-blue-500/30' },
        'Botellas': { icon: ICON.botellas, colorCls: 'text-indigo-300', bgCls: 'bg-indigo-500/10', borderCls: 'border-indigo-500/30' },
        'Utilidades': { icon: ICON.utilidades, colorCls: 'text-amber-300', bgCls: 'bg-amber-500/10', borderCls: 'border-amber-500/30' },
        'Cocimiento': { icon: ICON.cocimiento, colorCls: 'text-red-300', bgCls: 'bg-red-500/10', borderCls: 'border-red-500/30' },
        'Filtracion': { icon: ICON.filtracion, colorCls: 'text-cyan-300', bgCls: 'bg-cyan-500/10', borderCls: 'border-cyan-500/30' },
        'Fermentacion': { icon: ICON.fermentacion, colorCls: 'text-emerald-300', bgCls: 'bg-emerald-500/10', borderCls: 'border-emerald-500/30' },
        'Logistica': { icon: ICON.logistica, colorCls: 'text-slate-300', bgCls: 'bg-slate-500/10', borderCls: 'border-slate-500/30' },
        'Ingenieria': { icon: ICON.ingenieria, colorCls: 'text-purple-300', bgCls: 'bg-purple-500/10', borderCls: 'border-purple-500/30' },
    };
    return map[line] || { icon: ICON.plant, colorCls: 'text-gray-300', bgCls: 'bg-gray-500/10', borderCls: 'border-gray-500/30' };
}

// --- TOAST NOTIFICATIONS (reemplaza alert()) ---
function showToast(message, type = 'success', duration = 3500) {
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        document.body.appendChild(container);
    }
    const iconMap = { success: ICON.check, error: ICON.xmark, info: ICON.info };
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `${iconMap[type] || ICON.info}<span class="flex-grow">${message}</span><button onclick="this.parentElement.remove()" class="ml-3 opacity-50 hover:opacity-100 leading-none text-base">✕</button>`;
    container.appendChild(toast);
    setTimeout(() => {
        toast.style.transition = 'opacity 0.3s, transform 0.3s';
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(0.5rem)';
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// --- RELOJ CORPORATIVO ---
function updateClock() {
    const now = _getHoyEc();
    const clockEl = document.getElementById('hk-clock');
    const dateEl  = document.getElementById('hk-date');
    if (clockEl) clockEl.textContent = now.toLocaleTimeString('es-EC', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone: 'America/Guayaquil' });
    if (dateEl)  dateEl.textContent  = now.toLocaleDateString('es-EC', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'America/Guayaquil' });
}
updateClock();
setInterval(updateClock, 1000);

// --- INDICADOR DE CONEXIÓN A SUPABASE ---
async function checkConnection() {
    const dot = el('hk-connection');
    if (!dot) return;
    try {
        const { error } = await supabase.from('operadores').select('id', { count: 'exact', head: true });
        if (error) throw error;
        dot.className = 'w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse transition-colors';
        dot.title = 'Conectado a Supabase • ' + new Date().toLocaleTimeString('es-EC', { timeZone: 'America/Guayaquil' });
    } catch (e) {
        dot.className = 'w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse transition-colors';
        dot.title = 'Sin conexión a Supabase';
    }
}
checkConnection();
setInterval(checkConnection, 30000);

// --- INICIO ---
(async () => {
    supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
    window.supabase = supabase;

    // Renderizar Sidebar
    el('sidebar-nav').innerHTML = VIEWS.map(v => `
        <div class="nav-item" data-view="${v}" onclick="changeView('${v}')">
            ${v.includes('Histórico') ? ICON.task : v.includes('Tareas') ? ICON.gear : v.includes('Operadores') ? ICON.user : ICON.cycle}
            <span>${v}</span>
        </div>
    `).join('');

    el('filter-area').innerHTML = '<option value="">Todas</option>' + LINEAS.map(l => `<option value="${l}">${l}</option>`).join('');

    // Eventos Globales
    el('add-row-btn').onclick = () => openEditor();
    el('filter-apply-btn').onclick = () => { currentPage = 1; applyFilters(); };
    el('filter-clear-btn').onclick = clearFilters;
    el('modal-close').onclick = () => toggleClass('modal-editor', 'hidden', true);
    el('modal-save').onclick = () => window.saveData();
    el('del-cancel').onclick = () => toggleClass('modal-delete', 'hidden', true);
    el('del-confirm').onclick = () => window.deleteData();
    
    // Búsqueda en tiempo real universal
    el('global-search').oninput = (e) => {
        const term = e.target.value.toLowerCase().trim();
        // Buscar en grids normales, en contenedores GTS (niveles líneas/máquinas/tareas) y en Pasos (relative flex group)
        document.querySelectorAll('#card-grid .data-card, #gts-grid-inner .gts-card-fixed, #gts-grid-inner .relative.flex.group').forEach(item => {
            const text = item.textContent.toLowerCase();
            item.style.display = text.includes(term) ? '' : 'none';
        });
    };

    // LISTENER DE EXCEL
    el('excel-upload').addEventListener('change', (e) => window.handleExcelUpload(e));

    // Paginación Principal
    el('btn-prev').onclick = () => { if(currentPage > 1) { currentPage--; applyFilters(); }};
    el('btn-next').onclick = () => { if(currentPage * PAGE_SIZE < totalCount) { currentPage++; applyFilters(); }};

    // Eventos GTS (Navegador)
    el('gts-back').onclick = () => window.gtsGoBack();
    el('btn-create-gts').onclick = () => openEditorGTS();
    el('gts-prev').onclick = () => { if(gtsPage > 1) { gtsPage--; renderGTS(gtsState.level, null, true); } };
    el('gts-next').onclick = () => { gtsPage++; renderGTS(gtsState.level, null, true); }; 

    // Carga inicial
    changeView('Histórico de CILTs');
})();

// --- CONTROL DE VISTAS ---
async function changeView(viewName) {
    currentView = viewName;
    
    // Actualizar Sidebar UI
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.toggle('active', item.dataset.view === viewName);
    });
    el('view-title').textContent = viewName;

    // Auto-cerrar sidebar al navegar (pedido del usuario)
    document.querySelector('.sidebar').classList.add('collapsed');

    toggleClass('operators-header', 'hidden', true);
    toggleClass('filters-container', 'hidden', true);
    toggleClass('card-view', 'hidden', true);
    toggleClass('gts-view', 'hidden', true);
    toggleClass('horarios-view', 'hidden', true);
    toggleClass('add-row-btn', 'hidden', true);
    toggleClass('pagination-controls', 'hidden', true);
    toggleClass('dashboard-metrics', 'hidden', false); // Mostrar métricas por defecto

    if (currentView === 'Histórico de CILTs') {
        currentTable = 'registro_tareas';
        toggleClass('filters-container', 'hidden', false);
        toggleClass('card-view', 'hidden', false);
        toggleClass('pagination-controls', 'hidden', false);
        toggleClass('dashboard-metrics', 'hidden', false);
        setMetricLabels('Total Registros', 'Completados', 'Pendientes', 'Atrasados');
        loadFilterOptionsLazy();
        await applyFilters();
        animateView('card-view');
    } 
    else if (currentView === 'Gestión de Operadores') {
        currentTable = 'operadores';
        toggleClass('operators-header', 'hidden', false);
        toggleClass('card-view', 'hidden', false);
        toggleClass('add-row-btn', 'hidden', false);
        toggleClass('pagination-controls', 'hidden', false);
        toggleClass('dashboard-metrics', 'hidden', false);
        setMetricLabels('Total Operadores', 'Activos Hoy', 'Supervisores', 'Sin Turno');
        await fetchData();
        animateView('card-view');
    }
    else if (currentView === 'Carga de Horarios') {
        toggleClass('horarios-view', 'hidden', false);
        toggleClass('dashboard-metrics', 'hidden', true); 
        initHorariosView();
        animateView('horarios-view');
    }
    else { // GTS
        toggleClass('gts-view', 'hidden', false);
        toggleClass('dashboard-metrics', 'hidden', false);
        setMetricLabels('Líneas Activas', 'Máquinas', 'Tareas Totales', 'Sin Pasos');
        gtsState = { level: 'lines', line: null, machine: null, task: null, machineName: '', taskName: '' };
        await updateDashboardMetrics();
        renderGTS('lines');
        animateView('gts-view');
    }
}

// Aplica animación de transición a una vista
function animateView(viewId) {
    const view = el(viewId);
    if (!view) return;
    view.classList.remove('view-enter');
    void view.offsetWidth; // force reflow
    view.classList.add('view-enter');
}

// Actualiza las etiquetas de las métricas según la vista
function setMetricLabels(l1, l2, l3, l4) {
    if (el('m-label-1')) el('m-label-1').textContent = l1;
    if (el('m-label-2')) el('m-label-2').textContent = l2;
    if (el('m-label-3')) el('m-label-3').textContent = l3;
    if (el('m-label-4')) el('m-label-4').textContent = l4;
    
    // Resetear valores para evitar "stale state"
    ['m-total', 'm-done', 'm-pending', 'm-late'].forEach(id => {
        if (el(id)) el(id).textContent = '...';
    });
}

async function updateDashboardMetrics() {
    const viewAtStart = currentView;
    try {
        if (currentView === 'Histórico de CILTs') {
            const { data, error } = await supabase.from('registro_tareas').select('estado');
            if (currentView !== viewAtStart) return; // Evitar carrera
            if (error || !data) throw error || new Error('No data');
            
            const stats = { total: data.length, done: 0, pending: 0, late: 0 };
            data.forEach(r => {
                if (r.estado === 'Completado') stats.done++;
                else if (r.estado === 'Atrasado') stats.late++;
                else stats.pending++;
            });
            
            if (el('m-total')) el('m-total').textContent = stats.total;
            if (el('m-done')) el('m-done').textContent = stats.done;
            if (el('m-pending')) el('m-pending').textContent = stats.pending;
            if (el('m-late')) el('m-late').textContent = stats.late;
        } else if (currentView === 'Gestión de Operadores') {
            const { data: ops, error: errOps } = await supabase.from('operadores').select('id, id_operador, tipo');
            if (currentView !== viewAtStart) return;
            if (errOps || !ops) throw errOps || new Error('No data');
            
            const supervisors = ops.filter(o => (o.tipo || '').toLowerCase().includes('supervisor')).length;
            
            const today = new Date().toISOString().slice(0, 10);
            const { count: activosHoy } = await supabase.from('turnos_semana')
                .select('*', { count: 'exact', head: true })
                .eq('fecha', today);
            
            const { data: turnosHoy } = await supabase.from('turnos_semana')
                .select('id_operador')
                .eq('fecha', today);
            
            if (currentView !== viewAtStart) return;

            const idsConTurno = new Set((turnosHoy || []).map(t => t.id_operador));
            const sinTurno = ops.filter(o => !idsConTurno.has(o.id_operador)).length;

            if (el('m-total')) el('m-total').textContent = ops.length;
            if (el('m-done')) el('m-done').textContent = activosHoy || 0;
            if (el('m-pending')) el('m-pending').textContent = supervisors;
            if (el('m-late')) el('m-late').textContent = sinTurno;
        } else if (currentView === 'Gestión de Tareas y Pasos') {
            const { count: maquinas } = await supabase.from('maquinas').select('*', { count: 'exact', head: true });
            const { count: tareas } = await supabase.from('tareas').select('*', { count: 'exact', head: true });
            const { data: allTareas } = await supabase.from('tareas').select('id_tarea');
            const { data: allPasos } = await supabase.from('pasos_tarea').select('id_tarea');
            const idsConPasos = new Set((allPasos || []).map(p => p.id_tarea));
            const sinPasos = (allTareas || []).filter(t => !idsConPasos.has(t.id_tarea)).length;
            
            if (currentView !== viewAtStart) return;

            if (el('m-total')) el('m-total').textContent = (typeof LINEAS !== 'undefined' ? LINEAS.length : 0);
            if (el('m-done')) el('m-done').textContent = maquinas || 0;
            if (el('m-pending')) el('m-pending').textContent = tareas || 0;
            if (el('m-late')) el('m-late').textContent = sinPasos || 0;
        }
    } catch (err) {
        console.error("Error updating metrics:", err);
        if (currentView === viewAtStart) {
            ['m-total', 'm-done', 'm-pending', 'm-late'].forEach(id => {
                if (el(id)) el(id).textContent = '-';
            });
        }
    }
}

function renderSkeletons() {
    el('card-grid').innerHTML = Array(8).fill(0).map(() => `
        <div class="data-card p-4 flex flex-col gap-3">
            <div class="flex justify-between items-start">
                <div class="w-16 h-5 skeleton rounded-full"></div>
                <div class="w-20 h-4 skeleton rounded"></div>
            </div>
            <div class="w-3/4 h-6 skeleton rounded"></div>
            <div class="flex gap-2">
                <div class="w-12 h-4 skeleton rounded"></div>
                <div class="w-16 h-4 skeleton rounded"></div>
            </div>
            <div class="mt-auto pt-2 border-t border-gray-800 space-y-2">
                <div class="w-full h-4 skeleton rounded"></div>
                <div class="w-1/2 h-4 skeleton rounded"></div>
            </div>
        </div>
    `).join('');
}

// --- SISTEMA GTS (NAVEGADOR MEJORADO) ---
async function renderGTS(level, param = null, isPagination = false, extraName = '') {
    if (!isPagination) gtsPage = 1; // Resetear página al cambiar de nivel
    gtsState.level = level;

    if(level === 'machines' && param) { gtsState.line = param; }
    if(level === 'tasks' && param) { gtsState.machine = param; if(extraName) gtsState.machineName = extraName; }
    if(level === 'steps' && param) { gtsState.task = param; if(extraName) gtsState.taskName = extraName; }

    const container = el('gts-grid-inner');
    const breadcrumbs = el('gts-breadcrumbs');
    const addBtn = el('btn-create-gts');
    const excelContainer = el('gts-excel-container');
    
    toggleClass('app-loading', 'hidden', false);
    toggleClass('gts-pagination', 'hidden', true);
    el('gts-container').scrollTop = 0;
    if(excelContainer) excelContainer.innerHTML = '';
    const searchWrapper = el('gts-search-wrapper');
    const searchInput   = el('gts-search');
    if (!isPagination && searchInput) searchInput.value = '';
    if (searchWrapper) toggleClass('gts-search-wrapper', 'hidden', level === 'lines');

    let bcHtml = '<button type="button" data-level="lines" onclick="navGTSCard(this)" class="px-2 py-0.5 rounded hover:bg-gray-800 transition-colors">Áreas</button>';
    if (level !== 'lines') bcHtml += ` <span class="text-gray-600">/</span> <button type="button" data-level="machines" data-id="${esc(gtsState.line)}" onclick="navGTSCard(this)" class="px-2 py-0.5 rounded hover:bg-gray-800 transition-colors ${level==='machines'?'text-emerald-400 font-bold bg-emerald-500/10':''}">${esc(gtsState.line)}</button>`;
    if (level === 'tasks' || level === 'steps') bcHtml += ` <span class="text-gray-600">/</span> <button type="button" data-level="tasks" data-id="${esc(gtsState.machine)}" data-name="${esc(gtsState.machineName)}" onclick="navGTSCard(this)" class="px-2 py-0.5 rounded hover:bg-gray-800 transition-colors ${level==='tasks'?'text-emerald-400 font-bold bg-emerald-500/10':''}">${esc(gtsState.machineName || gtsState.machine)}</button>`;
    if (level === 'steps') bcHtml += ` <span class="text-gray-600">/</span> <span class="px-2 py-0.5 rounded text-emerald-400 font-bold bg-emerald-500/10 border border-emerald-500/20">${esc(gtsState.taskName || 'Tarea')}</span>`;
    breadcrumbs.innerHTML = bcHtml;

    toggleClass('gts-back', 'hidden', level === 'lines');
    toggleClass('btn-create-gts', 'hidden', level === 'lines');

    const from = (gtsPage - 1) * GTS_PAGE_SIZE;
    const to = from + GTS_PAGE_SIZE - 1;
    let data = [], error = null, count = 0;

    if (level === 'lines') {
        container.innerHTML = LINEAS.map(l => {
            const info = getLineInfo(l);
            return `
            <div class="gts-card-fixed group border-l-4 ${info.borderCls}" onclick="navGTS('machines', '${l}')" style="background: linear-gradient(145deg, var(--hk-surface), rgba(20,20,20,0.4))">
                <div class="gts-header ${info.colorCls}">
                    <span class="text-xs font-bold tracking-widest uppercase opacity-70">Área de Producción</span>
                    <svg class="w-4 h-4 opacity-40 group-hover:opacity-100 group-hover:translate-x-1 transition-all" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path></svg>
                </div>
                <div class="gts-body justify-center items-center text-center">
                    <div class="mb-4 transform group-hover:scale-110 transition-transform duration-300 ${info.colorCls}">${info.icon}</div>
                    <div class="text-lg font-bold text-white tracking-wide group-hover:text-emerald-400 transition-colors">${l}</div>
                    <div class="mt-3 flex items-center justify-center gap-3">
                        <span class="text-xs font-mono px-2 py-0.5 rounded-full ${info.bgCls} ${info.colorCls} border ${info.borderCls}" data-count-maq="${esc(l)}">···</span>
                        <span class="text-[10px] uppercase font-bold tracking-tighter ${info.colorCls}/40 flex items-center gap-1 group-hover:text-emerald-500 transition-colors">Explorar ${ICON.arrow}</span>
                    </div>
                </div>
            </div>
        `;}).join('');
    }
    else if (level === 'machines') {
        addBtn.textContent = 'Nueva Máquina';
        currentTable = 'maquinas';
        const res = await supabase.from('maquinas').select('*', { count: 'exact' }).eq('linea', gtsState.line).range(from, to);
        data = res.data; count = res.count; error = res.error;
        handleGTSPagination(count);
        const lineInfo = getLineInfo(gtsState.line);
        container.innerHTML = (!data || !data.length) ? emptyState('No hay máquinas registradas en esta línea.') : data.map(m => {
            const mIcon = getMachineIcon(m.nombre);
            return `
            <div class="gts-card-fixed group border-l-4 ${lineInfo.borderCls}"
                 data-level="tasks" data-id="${esc(m.id_maquina)}" data-name="${esc(m.nombre)}"
                 onclick="navGTSCard(this)" style="background: linear-gradient(145deg, var(--hk-surface), rgba(20,20,20,0.4))">
                <div class="absolute right-[-10%] top-[-10%] opacity-[0.03] group-hover:opacity-[0.08] group-hover:scale-125 transition-all duration-700 pointer-events-none ${lineInfo.colorCls}">
                    ${mIcon.replace('w-8 h-8', 'w-32 h-32')}
                </div>
                <div class="gts-header ${lineInfo.colorCls}">
                    <div class="flex items-center gap-2">
                        <span class="px-2 py-0.5 rounded text-[10px] font-mono tracking-tighter border border-current opacity-60 bg-current/5">${m.id_maquina}</span>
                        <span class="text-[9px] uppercase tracking-widest opacity-40 font-bold">Machine Asset</span>
                    </div>
                    <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button class="btn-action btn-action-edit" onclick="event.stopPropagation(); editItem('${m.id}')" title="Editar">${ICON.edit}</button>
                        <button class="btn-action btn-action-del" onclick="event.stopPropagation(); askDelete('${m.id}')" title="Eliminar">${ICON.trash}</button>
                    </div>
                </div>
                <div class="gts-body relative z-10">
                    <div class="flex items-start gap-4 mb-4">
                        <div class="p-3 rounded-xl ${lineInfo.bgCls} ${lineInfo.colorCls} border ${lineInfo.borderCls} shadow-inner transform group-hover:rotate-12 transition-transform duration-500">
                            ${mIcon}
                        </div>
                        <div class="flex-grow min-w-0">
                            <div class="text-xs uppercase tracking-tighter opacity-40 mb-1 font-bold">Nombre del Equipo</div>
                            <div class="text-lg font-black text-white leading-tight group-hover:text-emerald-400 transition-colors truncate">${m.nombre}</div>
                        </div>
                    </div>
                    <div class="mt-auto pt-3 border-t border-white/5 flex items-center justify-between">
                        <div class="flex flex-col">
                            <span class="text-[9px] uppercase tracking-widest opacity-40 font-bold">Estado</span>
                            <span class="text-[10px] text-emerald-400 flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span> Operativo</span>
                        </div>
                        <div class="flex items-center gap-3">
                            <div class="flex flex-col items-end">
                                <span class="text-[9px] uppercase tracking-widest opacity-40 font-bold">Procedimientos</span>
                                <span class="text-xs font-mono font-bold ${lineInfo.colorCls}" data-count-tasks="${esc(m.id_maquina)}">···</span>
                            </div>
                            <div class="w-8 h-8 rounded-full flex items-center justify-center ${lineInfo.bgCls} ${lineInfo.colorCls} border ${lineInfo.borderCls} group-hover:translate-x-1 transition-transform">
                                ${ICON.arrow}
                            </div>
                        </div>
                    </div>
                </div>
                <div class="absolute inset-0 opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity duration-500" 
                     style="box-shadow: inset 0 0 40px ${lineInfo.bgCls.replace('bg-','').replace('/10','')}"></div>
            </div>
        `;}).join('');
    }
    else if (level === 'tasks') {
        addBtn.textContent = 'Nueva Tarea';
        currentTable = 'tareas';
        if(excelContainer) {
            excelContainer.innerHTML = `
                <button onclick="downloadTemplate()" class="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded text-sm shadow-lg flex items-center transition-colors">
                    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path></svg>
                    Plantilla
                </button>
                <button onclick="document.getElementById('excel-upload').click()" class="px-3 py-1.5 bg-green-600 hover:bg-green-500 text-white rounded text-sm shadow-lg flex items-center transition-colors">
                    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path></svg>
                    Cargar Excel
                </button>
            `;
        }
        const res = await supabase.from('tareas').select('*', { count: 'exact' }).eq('id_maquina', gtsState.machine).order('nombre_tarea').range(from, to);
        data = res.data; count = res.count; error = res.error;
        handleGTSPagination(count);
        const lineInfo = getLineInfo(gtsState.line);
        container.innerHTML = (!data || !data.length) ? emptyState('No hay tareas creadas para esta máquina.') : data.map(t => `
            <div class="gts-card-fixed group border-l-4 ${lineInfo.borderCls}"
                 data-level="steps" data-id="${esc(t.id_tarea)}" data-name="${esc(t.nombre_tarea)}"
                 onclick="navGTSCard(this)" style="background: linear-gradient(145deg, var(--hk-surface), rgba(20,20,20,0.4))">
                <div class="gts-header ${lineInfo.colorCls}">
                    <span class="text-[10px] uppercase border ${lineInfo.borderCls} px-2 py-0.5 rounded-full font-bold tracking-wider ${lineInfo.bgCls}">${t.tipo || 'General'}</span>
                    <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button class="btn-action btn-action-edit" onclick="event.stopPropagation(); editItem('${t.id}')" title="Editar">${ICON.edit}</button>
                        <button class="btn-action btn-action-del" onclick="event.stopPropagation(); askDelete('${t.id}')" title="Eliminar">${ICON.trash}</button>
                    </div>
                </div>
                <div class="gts-body">
                    <div class="${lineInfo.colorCls}/20 mb-2">${ICON.task}</div>
                    <div class="font-bold text-white text-sm leading-snug group-hover:text-emerald-400 transition-colors">${t.nombre_tarea}</div>
                    <div class="mt-auto flex justify-between items-end border-t pt-3" style="border-color:rgba(255,255,255,0.05)">
                        <div class="text-[10px] uppercase font-bold tracking-tighter ${lineInfo.colorCls}/60 flex items-center gap-1">${ICON.cycle} ${t.frecuencia}</div>
                        <div class="flex items-center gap-2">
                            <span class="text-xs font-mono px-2 py-0.5 rounded-full ${lineInfo.bgCls} ${lineInfo.colorCls} border ${lineInfo.borderCls}" data-count-steps="${esc(t.id_tarea)}">···</span>
                            <span class="text-[10px] uppercase font-bold tracking-tighter ${lineInfo.colorCls}/40 flex items-center gap-1 group-hover:text-emerald-500 transition-colors">Pasos ${ICON.arrow}</span>
                        </div>
                    </div>
                </div>
            </div>
        `).join('');
    }
    else if (level === 'steps') {
        addBtn.textContent = 'Nuevo Paso';
        currentTable = 'pasos_tarea';
        const res = await supabase.from('pasos_tarea').select('*', { count: 'exact' }).eq('id_tarea', gtsState.task).order('numeropaso').range(from, to);
        data = res.data; count = res.count; error = res.error;
        handleGTSPagination(count);
        container.className = "flex flex-col gap-0 p-6 max-w-5xl mx-auto w-full relative";
        container.innerHTML = (!data || !data.length) ? '<div class="text-center py-20 text-gray-500 bg-gray-900/20 rounded-2xl border border-dashed border-gray-800">No hay pasos definidos para esta tarea.</div>' : data.map((s, idx) => {
            const isLast = idx === data.length - 1;
            return `
            <div class="relative flex gap-6 group">
                ${!isLast ? `<div class="absolute left-6 top-12 bottom-[-1rem] w-0.5 bg-gradient-to-b from-emerald-500/30 to-transparent z-0"></div>` : ''}
                <div class="relative z-10 flex-shrink-0 w-12 h-12 rounded-2xl bg-gray-900 border-2 border-emerald-500/50 flex items-center justify-center text-emerald-400 font-black text-lg shadow-[0_0_15px_rgba(16,185,129,0.1)] group-hover:scale-110 group-hover:border-emerald-400 transition-all duration-300">
                    ${s.numeropaso}
                </div>
                <div class="step-card flex-grow mb-8 !p-0 overflow-hidden border-l-0" style="background: linear-gradient(145deg, var(--hk-surface), rgba(20,20,20,0.4))">
                    <div class="flex h-full min-h-[140px]">
                        <div class="w-48 flex-shrink-0 relative overflow-hidden bg-black/40 border-r border-white/5">
                            ${s.imagenurl 
                                ? `<img src="${s.imagenurl}" class="w-full h-full object-cover group-hover:scale-110 transition-transform duration-700 cursor-zoom-in" onclick="window.open('${s.imagenurl}')">
                                   <div class="absolute inset-0 bg-emerald-500/10 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"></div>`
                                : `<div class="w-full h-full flex flex-col items-center justify-center text-gray-700 gap-1 bg-gray-900/50">${ICON.image}<span class="text-[9px] font-black tracking-widest opacity-40 uppercase">Sin Imagen</span></div>`}
                        </div>
                        <div class="flex-grow p-5 flex flex-col min-w-0">
                            <div class="flex items-center justify-between mb-2">
                                <div class="flex items-center gap-2">
                                    <span class="text-[10px] font-black uppercase tracking-[0.2em] text-emerald-500/60">Instrucción Técnica</span>
                                    <div class="w-1 h-1 rounded-full bg-emerald-500/30"></div>
                                    <span class="text-[10px] font-mono text-gray-500">ID: ${s.id.slice(0,8)}</span>
                                </div>
                                <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-all transform translate-x-2 group-hover:translate-x-0">
                                    <div class="flex gap-1 bg-gray-900/80 p-1 rounded-lg border border-gray-700 shadow-xl backdrop-blur-md">
                                        <button class="btn-action btn-action-edit" onclick="event.stopPropagation(); moveStep('${s.id}', -1)" title="Subir">${ICON.arrow.replace('13 7l5 5m0 0l-5 5m5-5H6', '5 15l7-7 7 7')}</button>
                                        <button class="btn-action btn-action-edit" onclick="event.stopPropagation(); moveStep('${s.id}', 1)" title="Bajar">${ICON.arrow.replace('13 7l5 5m0 0l-5 5m5-5H6', '19 9l-7 7-7-7')}</button>
                                        <button class="btn-action btn-action-edit" onclick="event.stopPropagation(); editItem('${s.id}')" title="Editar">${ICON.edit}</button>
                                        <button class="btn-action btn-action-del" onclick="event.stopPropagation(); askDelete('${s.id}')" title="Eliminar">${ICON.trash}</button>
                                    </div>
                                </div>
                            </div>
                            <div class="text-gray-100 text-sm leading-relaxed font-medium">
                                ${esc(s.descripcion)}
                            </div>
                            <div class="mt-auto pt-3 flex items-center gap-4 text-[10px] font-bold tracking-widest text-gray-600 uppercase">
                                <span class="flex items-center gap-1">${ICON.check} Revisión requerida</span>
                                <span class="flex items-center gap-1">${ICON.info} Referencia Visual</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;}).join('');
        toggleClass('app-loading', 'hidden', true);
        return;
    }

    container.className = "gts-grid";
    if (error) { console.error(error); showToast('Error al cargar datos: ' + error.message, 'error'); }

    if (level === 'lines') {
        const { data: mc } = await supabase.from('maquinas').select('linea');
        const lineCount = {};
        (mc || []).forEach(m => lineCount[m.linea] = (lineCount[m.linea] || 0) + 1);
        document.querySelectorAll('[data-count-maq]').forEach(el => {
            const n = lineCount[el.dataset.countMaq] || 0;
            el.textContent = `${n} máq.`;
        });
    }
    if (level === 'machines' && data && data.length) {
        const ids = data.map(m => m.id_maquina);
        const { data: tc } = await supabase.from('tareas').select('id_maquina').in('id_maquina', ids);
        const taskCount = {};
        (tc || []).forEach(t => taskCount[t.id_maquina] = (taskCount[t.id_maquina] || 0) + 1);
        document.querySelectorAll('[data-count-tasks]').forEach(el => {
            const n = taskCount[el.dataset.countTasks] || 0;
            el.textContent = `${n} tareas`;
        });
    }
    if (level === 'tasks' && data && data.length) {
        const ids = data.map(t => t.id_tarea);
        const { data: sc } = await supabase.from('pasos_tarea').select('id_tarea').in('id_tarea', ids);
        const stepCount = {};
        (sc || []).forEach(s => stepCount[s.id_tarea] = (stepCount[s.id_tarea] || 0) + 1);
        document.querySelectorAll('[data-count-steps]').forEach(el => {
            const n = stepCount[el.dataset.countSteps] || 0;
            el.textContent = n > 0 ? `${n} pasos` : 'Sin pasos';
            if (n === 0) el.style.color = '#f87171';
        });
    }
    toggleClass('app-loading', 'hidden', true);
}

function emptyState(msg) {
    return `<div class="col-span-full flex flex-col items-center justify-center mt-16 gap-3 text-center">
        <svg class="w-12 h-12 opacity-20" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
        <p class="text-gray-600 text-sm">${msg}</p>
    </div>`;
}

function handleGTSPagination(count) {
    if (count > GTS_PAGE_SIZE) {
        toggleClass('gts-pagination', 'hidden', false);
        el('gts-page-info').textContent = `Pág ${gtsPage} de ${Math.ceil(count/GTS_PAGE_SIZE)}`;
        el('gts-prev').disabled = gtsPage === 1;
        el('gts-next').disabled = gtsPage >= Math.ceil(count/GTS_PAGE_SIZE);
    } else {
        toggleClass('gts-pagination', 'hidden', true);
    }
}

window.filterGTSCards = (q) => {
    const term = q.toLowerCase().trim();
    document.querySelectorAll('#gts-grid-inner .gts-card-fixed, #gts-grid-inner > div').forEach(card => {
        card.style.display = !term || card.textContent.toLowerCase().includes(term) ? '' : 'none';
    });
};

window.renderGTS = renderGTS;
window.navGTS = (level, p1, _dbId, name) => renderGTS(level, p1, false, name);

window.gtsGoBack = () => {
    if (gtsState.level === 'machines') renderGTS('lines');
    else if (gtsState.level === 'tasks') renderGTS('machines', gtsState.line);
    else if (gtsState.level === 'steps') renderGTS('tasks', gtsState.machine, false, gtsState.machineName);
};

window.downloadTemplate = () => {
    const link = document.createElement('a');
    link.href = 'https://czxyfzxjwzaykwoxyjah.supabase.co/storage/v1/object/public/pasosimagen/Carga-CILT.xlsm';
    link.download = 'Carga-CILT.xlsm'; link.target = '_blank';
    document.body.appendChild(link); link.click(); document.body.removeChild(link);
};

window.handleExcelUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    toggleClass('app-loading', 'hidden', false);
    const reader = new FileReader();
    reader.onload = async (evt) => {
        try {
            const data = new Uint8Array(evt.target.result);
            const workbook = XLSX.read(data, { type: 'array' });
            await processComplexExcel(workbook);
        } catch (error) { console.error(error); showToast("Error al procesar el archivo: " + error.message, 'error', 6000); }
        finally { toggleClass('app-loading', 'hidden', true); e.target.value = ''; }
    };
    reader.readAsArrayBuffer(file);
};

function sanitizeSheetName(name) { return name.replace(/[:\\/?*\[\]]/g, '').substring(0, 31).trim(); }

async function processComplexExcel(workbook) {
    if (!gtsState.machine) { showToast("Selecciona una máquina antes de cargar tareas.", 'error'); return; }
    let masterSheetName = workbook.SheetNames.find(n => n.toLowerCase().includes("tareas")) || workbook.SheetNames[0];
    const masterSheet = workbook.Sheets[masterSheetName];
    const masterData = XLSX.utils.sheet_to_json(masterSheet, { header: 1, range: 2 });
    let createdCount = 0; let errors = [];
    const tareasToInsert = [];
    const pasosToInsertAll = [];

    for (let i = 0; i < masterData.length; i++) {
        const row = masterData[i];
        const rawNombre = row[0] ? row[0].toString().trim() : null;
        if (!rawNombre) continue; 
        let rawTipo = row[2] ? row[2].toString().trim() : 'Inspección';
        let validTipo = 'Inspección';
        const formattedTipo = rawTipo.charAt(0).toUpperCase() + rawTipo.slice(1).toLowerCase();
        const TIPOS_VALIDOS = ['Limpieza', 'Lubricación', 'Inspección', 'Ajuste'];
        if (TIPOS_VALIDOS.includes(rawTipo)) validTipo = rawTipo;
        else if (TIPOS_VALIDOS.includes(formattedTipo)) validTipo = formattedTipo;
        else if (formattedTipo === 'Lubricacion') validTipo = 'Lubricación';
        else if (formattedTipo === 'Inspeccion') validTipo = 'Inspección';
        let rawFrec = row[3];
        let validFrec = 'Diario'; 
        if (rawFrec) {
            const cleanFrec = rawFrec.toString().trim();
            const formatted = cleanFrec.charAt(0).toUpperCase() + cleanFrec.slice(1).toLowerCase();
            if (FRECUENCIAS_VALIDAS.includes(cleanFrec)) validFrec = cleanFrec;
            else if (FRECUENCIAS_VALIDAS.includes(formatted)) validFrec = formatted;
            else if (cleanFrec.toLowerCase() === '3 años' || cleanFrec.toLowerCase() === 'tres anos') validFrec = 'Tres años';
        }
        const generatedIdTarea = `${gtsState.machine}-${Date.now()}-${Math.floor(Math.random()*1000)}-${i}`;
        tareasToInsert.push({
            id_maquina: gtsState.machine, id_tarea: generatedIdTarea,
            nombre_tarea: rawNombre, frecuencia: validFrec, tipo: validTipo, es_compartida: false
        });
        const possibleSheetName = sanitizeSheetName(rawNombre);
        const foundSheetName = workbook.SheetNames.find(n => n.trim().toLowerCase() === possibleSheetName.toLowerCase());
        if (foundSheetName) {
            const detailSheet = workbook.Sheets[foundSheetName];
            const detailData = XLSX.utils.sheet_to_json(detailSheet, { header: 1 });
            detailData.forEach(stepRow => {
                const numPaso = stepRow[0];
                const descPaso = stepRow[1];
                const rawImage = stepRow[2];
                const imageUrl = rawImage ? rawImage.toString().trim() : null;
                if (numPaso !== undefined && numPaso !== null && !isNaN(parseInt(numPaso)) && descPaso) {
                    pasosToInsertAll.push({
                        id_tarea: generatedIdTarea, numeropaso: parseInt(numPaso)||0,
                        descripcion: descPaso, imagenurl: imageUrl || null
                    });
                }
            });
        }
        createdCount++;
    }

    if (tareasToInsert.length > 0) {
        const BATCH_TAREAS = 50;
        for (let i = 0; i < tareasToInsert.length; i += BATCH_TAREAS) {
            const chunk = tareasToInsert.slice(i, i + BATCH_TAREAS);
            const { error: errTareas } = await supabase.from('tareas').insert(chunk);
            if (errTareas) {
                console.error("Error batch tareas:", errTareas);
                errors.push(`Lote Tareas ${Math.floor(i/BATCH_TAREAS) + 1}: ${errTareas.message}`);
            }
        }
    }

    if (pasosToInsertAll.length > 0) {
        const BATCH_PASOS = 500;
        for (let i = 0; i < pasosToInsertAll.length; i += BATCH_PASOS) {
            const chunk = pasosToInsertAll.slice(i, i + BATCH_PASOS);
            const { error: errPasos } = await supabase.from('pasos_tarea').insert(chunk);
            if (errPasos) {
                console.error("Error batch pasos:", errPasos);
                errors.push(`Lote Pasos ${Math.floor(i/BATCH_PASOS) + 1}: ${errPasos.message}`);
            }
        }
    }

    if (errors.length) {
        showToast(`Se encontraron errores al procesar el archivo.`, 'error', 10000);
        if (el('gts-grid-inner')) {
            el('gts-grid-inner').innerHTML = `
                <div class="col-span-full p-4 bg-red-900/20 border border-red-800 rounded-lg text-red-200 text-sm">
                    <div class="font-bold mb-2 flex items-center gap-2">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path></svg>
                        Detalle de errores en la carga:
                    </div>
                    <ul class="list-disc list-inside space-y-1">${errors.map(e => `<li>${e}</li>`).join('')}</ul>
                </div>`;
        }
    } else {
        showToast(`${createdCount} tareas creadas correctamente desde Excel.`, 'success');
    }
    renderGTS('tasks', gtsState.machine, false, gtsState.machineName);
}

// --- FILTROS Y DATOS GENERALES ---
window.toggleFilter = (id) => {
    const dropdown = el('dropdown-' + id);
    if (!dropdown) return;
    const isShown = dropdown.classList.contains('show');
    document.querySelectorAll('.filter-dropdown-content').forEach(d => d.classList.remove('show'));
    if (!isShown) dropdown.classList.add('show');
};

async function loadFilterOptionsLazy() {
    if (filterOptionsLoaded) return;
    await loadFilterOptions();
    filterOptionsLoaded = true;
}
async function loadFilterOptions() {
    try {
        const { data: ops } = await supabase.from('operadores').select('id_operador, nombreoperador').eq('tipo', 'operador').order('nombreoperador');
        renderCheckboxList('dropdown-ops', ops || [], 'id_operador', 'nombreoperador', 'label-ops');
        const { data: maqs } = await supabase.from('maquinas').select('id_maquina, nombre, tareas!inner(id_maquina)');
        const uniqueMaqs = [];
        const seen = new Set();
        (maqs || []).forEach(m => {
            if (!seen.has(m.id_maquina)) {
                seen.add(m.id_maquina);
                uniqueMaqs.push({ id_maquina: m.id_maquina, nombre: m.nombre });
            }
        });
        uniqueMaqs.sort((a,b) => a.nombre.localeCompare(b.nombre));
        renderCheckboxList('dropdown-maqs', uniqueMaqs, 'id_maquina', 'nombre', 'label-maqs');
    } catch (err) { console.error("Error filters", err); }
}

function renderCheckboxList(containerId, data, valKey, labelKey, labelDisplayId) {
    const container = el(containerId);
    if (!data.length) { container.innerHTML = '<div class="text-xs p-2">Sin datos</div>'; return; }
    container.innerHTML = data.map(item => `
        <label class="filter-option">
            <input type="checkbox" class="filter-checkbox" value="${item[valKey]}" onchange="updateLabel('${containerId}', '${labelDisplayId}')">
            <span class="filter-label">${item[labelKey]}</span>
        </label>`).join('');
}

window.updateLabel = (cId, lId) => {
    const n = el(cId).querySelectorAll('input:checked').length;
    el(lId).textContent = n > 0 ? `${n} Seleccionados` : 'Seleccionar...';
    el(lId).classList.toggle('text-white', n > 0);
};

function getCheckedValues(id) { return Array.from(el(id).querySelectorAll('input:checked')).map(cb => cb.value); }

function buildHistoricoQuery(filters = {}) {
    let tJoin = 'tareas(nombre_tarea, frecuencia, tipo, es_compartida)';
    let oJoin = 'operadores(nombreoperador, linea)';
    if (filters.tipo) tJoin = 'tareas!inner(nombre_tarea, frecuencia, tipo, es_compartida)';
    if (filters.area) oJoin = 'operadores!inner(nombreoperador, linea)';
    let q = supabase.from('registro_tareas').select(`*, ${tJoin}, ${oJoin}`);
    if (filters.start) q = q.gte('fecha_limite', filters.start + 'T00:00:00-05:00');
    if (filters.end)   q = q.lte('fecha_limite', filters.end + 'T23:59:59-05:00');
    if (filters.ops  && filters.ops.length)  q = q.in('id_operador', filters.ops);
    if (filters.maqs && filters.maqs.length) q = q.in('id_maquina',  filters.maqs);
    if (filters.area)  q = q.eq('operadores.linea', filters.area);
    if (filters.tipo)  q = q.eq('tareas.tipo',      filters.tipo);
    return q.order('fecha_limite', { ascending: false });
}

window.exportHistorico = async () => {
    const filters = {
        start: el('filter-date-start').value,
        end:   el('filter-date-end').value,
        area:  el('filter-area').value,
        tipo:  el('filter-tipo').value,
        ops:   getCheckedValues('dropdown-ops'),
        maqs:  getCheckedValues('dropdown-maqs'),
    };
    showToast('Preparando exportación...', 'info', 2000);
    toggleClass('app-loading', 'hidden', false);
    const { data, error } = await buildHistoricoQuery(filters);
    toggleClass('app-loading', 'hidden', true);
    if (error) { showToast('Error al exportar: ' + error.message, 'error'); return; }
    if (!data || !data.length) { showToast('No hay datos para exportar.', 'info'); return; }
    const rows = data.map(item => ({
        'Tarea':             item.tareas?.nombre_tarea   || '',
        'Tipo':              item.tareas?.tipo           || '',
        'Frecuencia':        item.tareas?.frecuencia     || '',
        'Operador':          item.operadores?.nombreoperador || '',
        'Línea':             item.operadores?.linea      || '',
        'Estado':            item.estado                 || '',
        'Fecha Límite':      item.fecha_limite     ? new Date(item.fecha_limite).toLocaleDateString('es-MX', { timeZone: 'America/Guayaquil' })     : '',
        'Fecha Completado':  item.fecha_completado ? new Date(item.fecha_completado).toLocaleDateString('es-MX', { timeZone: 'America/Guayaquil' }) : '',
        'Autogenerado':      item.fue_autogenerado ? 'Sí' : 'No',
    }));
    const ws = XLSX.utils.json_to_sheet(rows);
    ws['!cols'] = [30,15,15,30,15,12,15,15,12].map(w => ({ wch: w }));
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Histórico CILTs');
    XLSX.writeFile(wb, `CILT-Historico-${new Date().toLocaleDateString('en-CA', { timeZone: 'America/Guayaquil' })}.xlsx`);
    showToast(`${data.length} registros exportados a Excel.`, 'success');
};

async function applyFilters() {
    const filters = {
        start: el('filter-date-start').value,
        end: el('filter-date-end').value,
        area: el('filter-area').value,
        tipo: el('filter-tipo').value,
        ops: getCheckedValues('dropdown-ops'),
        maqs: getCheckedValues('dropdown-maqs')
    };
    fetchData(filters);
}

function clearFilters() {
    el('filter-date-start').value = '';
    el('filter-date-end').value = '';
    el('filter-area').value = '';
    el('filter-tipo').value = '';
    document.querySelectorAll('.filter-checkbox').forEach(c => c.checked = false);
    updateLabel('dropdown-ops', 'label-ops');
    updateLabel('dropdown-maqs', 'label-maqs');
    currentPage = 1;
    applyFilters();
}

async function fetchData(filters = {}) {
    renderSkeletons();
    await updateDashboardMetrics();
    const from = (currentPage - 1) * PAGE_SIZE;
    const to = from + PAGE_SIZE - 1;
    let query;
    if (currentTable === 'registro_tareas') {
        let tJoin = 'tareas(nombre_tarea, frecuencia, tipo, es_compartida)';
        let oJoin = 'operadores(nombreoperador, linea)';
        if (filters.tipo) tJoin = 'tareas!inner(nombre_tarea, frecuencia, tipo, es_compartida)';
        if (filters.area) oJoin = 'operadores!inner(nombreoperador, linea)';
        query = supabase.from('registro_tareas')
            .select(`id, estado, fecha_limite, id_maquina, ${tJoin}, ${oJoin}, maquinas(nombre)`, { count: 'exact' });
        if (filters.start) query = query.gte('fecha_limite', filters.start + 'T00:00:00-05:00');
        if (filters.end)   query = query.lte('fecha_limite', filters.end + 'T23:59:59-05:00');
        if (filters.ops  && filters.ops.length)  query = query.in('id_operador', filters.ops);
        if (filters.maqs && filters.maqs.length) query = query.in('id_maquina',  filters.maqs);
        if (filters.area)  query = query.eq('operadores.linea', filters.area);
        if (filters.tipo)  query = query.eq('tareas.tipo',      filters.tipo);
        query = query.order('fecha_limite', { ascending: false });
    } else {
        query = supabase.from(currentTable).select('*', { count: 'exact' }).order('nombreoperador');
    }
    const { data, count, error } = await query.range(from, to);
    toggleClass('app-loading', 'hidden', true);
    if (error) { showToast("Error al cargar datos: " + error.message, 'error'); return; }
    totalCount = count || 0;
    updatePaginationUI();
    if (!data || !data.length) { el('card-grid').innerHTML = emptyState('No se encontraron datos con los filtros aplicados.'); return; }
    renderCards(data);
}

function updatePaginationUI() {
    el('page-display').textContent = currentPage;
    const totalPages = Math.ceil(totalCount / PAGE_SIZE);
    el('pagination-info').textContent = `Total: ${totalCount} | Pág ${currentPage} de ${totalPages || 1}`;
    el('btn-prev').disabled = currentPage === 1;
    el('btn-next').disabled = currentPage >= totalPages || totalPages === 0;
}

function renderCards(data) {
    el('card-grid').innerHTML = data.map(item => {
        if (currentTable === 'operadores') {
            const img = item.foto_operador || `https://ui-avatars.com/api/?name=${item.nombreoperador}&background=random`;
            return `
            <div class="data-card relative group justify-center">
                <div class="op-grid">
                    <img src="${img}" class="op-img">
                    <div>
                        <div class="font-bold text-white leading-tight">${item.nombreoperador}</div>
                        <span class="op-role mt-1 inline-block">${item.tipo || 'Operador'}</span>
                    </div>
                </div>
                <div class="bg-gray-800 p-3 flex justify-between text-xs text-gray-400 border-t border-gray-700">
                    <div>LINEA: <span class="text-emerald-400">${item.linea || '-'}</span></div>
                    <div>ID: ${item.id_operador}</div>
                </div>
                <div class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                    <button class="btn-action btn-action-edit" onclick="editItem('${item.id}')" title="Editar">${ICON.edit}</button>
                    <button class="btn-action btn-action-del" onclick="askDelete('${item.id}')" title="Eliminar">${ICON.trash}</button>
                </div>
            </div>`;
        } else {
            const t = item.tareas || {};
            const o = item.operadores || {};
            const m = item.maquinas || {};
            const st = item.estado || 'Pendiente';
            const isShared = t.es_compartida === true;
            let cls = st === 'Completado' ? 'badge-done' : (st === 'Atrasado' ? 'badge-late' : 'badge-pending');
            return `
            <div class="data-card p-5 flex flex-col gap-4">
                <div class="flex justify-between items-start">
                    <div class="flex flex-col gap-2">
                        <span class="badge ${cls}">${st === 'Completado' ? ICON.check : (st === 'Atrasado' ? ICON.xmark : ICON.cycle)} ${st}</span>
                        ${isShared ? `<span class="badge" style="background:rgba(30,58,138,0.15); color:#93c5fd; border:1px solid rgba(30,64,175,0.3)">${ICON.user} Compartida</span>` : ''}
                    </div>
                    <div class="flex flex-col items-end gap-1">
                        <span class="text-[10px] font-black text-gray-600 uppercase tracking-widest">Fecha Límite</span>
                        <span class="text-xs font-mono text-gray-400 bg-gray-900/50 px-2 py-0.5 rounded border border-gray-800">${new Date(item.fecha_limite).toLocaleDateString('es-EC', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'America/Guayaquil' })}</span>
                    </div>
                </div>
                <div>
                    <div class="text-xs text-emerald-500/60 font-bold uppercase tracking-widest mb-1">${m.nombre || 'Sin Máquina'}</div>
                    <div class="font-bold text-white text-lg leading-tight tracking-tight group-hover:text-emerald-400 transition-colors">${t.nombre_tarea || 'Tarea Desconocida'}</div>
                </div>
                <div class="flex gap-2 flex-wrap">
                    <span class="text-[10px] font-bold bg-gray-800/50 text-gray-400 px-2 py-1 rounded border border-gray-700/50">${t.tipo || 'General'}</span>
                    <span class="text-[10px] font-bold bg-blue-900/10 text-blue-400 px-2 py-1 rounded border border-blue-900/30 flex items-center gap-1.5">${ICON.cycle} ${t.frecuencia || '-'}</span>
                </div>
                <div class="mt-auto pt-4 border-t flex flex-col gap-2" style="border-color:rgba(255,255,255,0.05)">
                    <div class="flex items-center gap-2.5">
                        <div class="w-6 h-6 rounded-full bg-gray-800 flex items-center justify-center text-gray-500">${ICON.user}</div>
                        <div class="flex flex-col min-w-0">
                            <span class="text-[9px] text-gray-600 font-black uppercase tracking-tighter">Responsable</span>
                            <span class="text-xs text-gray-300 font-semibold truncate">${o.nombreoperador || (isShared ? 'Equipo de Operadores' : '<span class="text-amber-500/70 italic">Sin asignar</span>')}</span>
                        </div>
                    </div>
                </div>
            </div>`;
        }
    }).join('');
}

// --- EDITOR GENERICO ---
window.openEditor = () => openEditorGTS();
window.openEditorGTS = async () => {
    editingId = null;
    el('modal-title').textContent = 'Crear Nuevo';
    el('dynamic-form').innerHTML = await buildForm();
    toggleClass('modal-editor', 'hidden', false);
};
window.editItem = async (id) => {
    editingId = id;
    toggleClass('app-loading', 'hidden', false);
    const { data } = await supabase.from(currentTable).select('*').eq('id', id).single();
    el('modal-title').textContent = 'Editar';
    el('dynamic-form').innerHTML = await buildForm(data);
    toggleClass('app-loading', 'hidden', true);
    toggleClass('modal-editor', 'hidden', false);
};
function refreshCurrentView() {
    if (currentView === 'Gestión de Tareas y Pasos') {
        const gtsParam = gtsState.level === 'tasks' ? gtsState.machine : gtsState.level === 'steps' ? gtsState.task : gtsState.line;
        renderGTS(gtsState.level, gtsParam, true);
    } else fetchData();
}
window.saveData = async () => {
    const formData = new FormData(el('dynamic-form'));
    const payload = Object.fromEntries(formData);
    if (currentTable === 'tareas') {
        if (payload.es_compartida === 'true') payload.es_compartida = true;
        else if (payload.es_compartida === 'false') payload.es_compartida = false;
        else if (payload.es_compartida === undefined) payload.es_compartida = false;
    }
    for (let key in payload) { if (payload[key] === '') payload[key] = null; }
    const { error } = editingId ? await supabase.from(currentTable).update(payload).eq('id', editingId) : await supabase.from(currentTable).insert([payload]);
    if (error) { showToast(error.message, 'error'); return; }
    toggleClass('modal-editor', 'hidden', true);
    showToast(editingId ? 'Registro actualizado correctamente.' : 'Registro creado correctamente.', 'success');
    refreshCurrentView();
};
window.askDelete = (id) => { deleteId = id; toggleClass('modal-delete', 'hidden', false); };
window.deleteData = async () => {
    const { error } = await supabase.from(currentTable).delete().eq('id', deleteId);
    toggleClass('modal-delete', 'hidden', true);
    if (error) { showToast('Error al eliminar: ' + error.message, 'error'); return; }
    showToast('Registro eliminado.', 'info');
    refreshCurrentView();
};

// --- FORM BUILDER ---
async function buildForm(data = {}) {
    let fields = [];
    if (currentTable === 'operadores') {
        fields = [
            { name: 'id_operador', label: 'ID RFID', type: 'text' },
            { name: 'nombreoperador', label: 'Nombre Completo', type: 'text' },
            { name: 'cedula', label: 'Cédula', type: 'text' },
            { name: 'linea', label: 'Línea', type: 'select', options: LINEAS },
            { name: 'tipo', label: 'Rol', type: 'select', options: ['operador', 'supervisor'] },
            { name: 'foto_operador', label: 'URL Foto', type: 'text' }
        ];
    } else if (currentTable === 'maquinas') {
        fields = [
            { name: 'id_maquina', label: 'ID Máquina', type: 'text', value: data.id_maquina || 'MAQ-' + Math.floor(Math.random()*9999) },
            { name: 'nombre', label: 'Nombre', type: 'text' },
            { name: 'linea', label: 'Línea', type: 'select', options: LINEAS }
        ];
    } else if (currentTable === 'tareas') {
        fields = [
            { name: 'id_maquina', type: 'hidden', value: gtsState.machine },
            { name: 'id_tarea', label: 'ID Tarea (Texto anico)', type: 'text', value: data.id_tarea || `${gtsState.machine}-${Date.now()}` },
            { name: 'nombre_tarea', label: 'Nombre Tarea', type: 'text' },
            { name: 'frecuencia', label: 'Frecuencia', type: 'select', options: FRECUENCIAS_VALIDAS },
            { name: 'tipo', label: 'Tipo', type: 'select', options: ['Limpieza','Lubricación','Inspección','Ajuste'] },
            { name: 'es_compartida', label: 'Es Compartida', type: 'select', options: ['false', 'true'], value: data.es_compartida ? 'true' : 'false' }
        ];
    } else if (currentTable === 'pasos_tarea') {
        fields = [
            { name: 'id_tarea', type: 'hidden', value: gtsState.task },
            { name: 'numeropaso', label: 'Número Paso', type: 'number' },
            { name: 'descripcion', label: 'Instrucción', type: 'textarea' },
            { name: 'imagenurl', label: 'Imagen', type: 'image_upload' }
        ];
    }
    return fields.map(f => {
        const val = data[f.name] !== undefined ? data[f.name] : (f.value || '');
        if (f.type === 'hidden') return `<input type="hidden" name="${f.name}" value="${val}">`;
        if (f.type === 'select') return `<div><label class="block text-sm text-gray-400 mb-1">${f.label}</label><select name="${f.name}" class="form-select">${f.options.map(o => `<option value="${o}" ${val===o?'selected':''}>${o}</option>`).join('')}</select></div>`;
        if (f.type === 'textarea') return `<div><label class="block text-sm text-gray-400 mb-1">${f.label}</label><textarea name="${f.name}" class="form-input h-24">${val}</textarea></div>`;
        if (f.type === 'image_upload') {
            return `<div>
                        <label class="block text-sm text-gray-400 mb-1">${f.label}</label>
                        <div class="flex gap-2">
                            <input type="text" name="${f.name}" id="input-${f.name}" value="${val}" class="form-input flex-grow" placeholder="URL o sube archivo">
                            <button type="button" onclick="document.getElementById('file-${f.name}').click()" class="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 rounded text-sm transition-colors border border-gray-600 text-white flex-shrink-0">Subir</button>
                        </div>
                        <input type="file" id="file-${f.name}" class="hidden" accept="image/*" onchange="uploadImageToSupabase(this, 'input-${f.name}')">
                    </div>`;
        }
        return `<div><label class="block text-sm text-gray-400 mb-1">${f.label}</label><input type="${f.type}" name="${f.name}" value="${val}" class="form-input"></div>`;
    }).join('');
}

// HORARIOS LOGIC
const MAQUINAS_LATAS_MAP = {
    'modulfill':  [{ id: '9994',     nombre: 'Modulfill' }, { id: '10003',    nombre: 'Pasteurizador Latas', fallback: true }],
    'varioline':  [{ id: '9992',     nombre: 'Varioline' }, { id: '9991',     nombre: 'Variopac',            fallback: true }],
    'variopac':   [{ id: '9991',     nombre: 'Variopac' }],
    'pressant':   [{ id: 'MAQ-5357', nombre: 'Pressant' }, { id: 'MAQ-9758', nombre: 'Modulpal', fallback: true }],
    'modulpal':   [{ id: 'MAQ-9758', nombre: 'Modulpal' }, { id: 'MAQ-5357', nombre: 'Pressant', fallback: true }],
    'pz':         [{ id: '10003',    nombre: 'Pasteurizador Latas' }],
};

const MAQUINAS_BOTELLAS_MAP = {
    'llenadora':       [{ id: '9998',  nombre: 'Llenadora' }, { id: '10000', nombre: 'Inspector Botellas Vacias' }],
    'etiquetadora':    [{ id: '9999',  nombre: 'Etiquetadora' }, { id: '9993',  nombre: 'Pasteurizador Botellas', fallback: true }],
    'lavadora':        [{ id: '10001', nombre: 'Lavadora' }],
    'pasteurizador':   [{ id: '9993',  nombre: 'Pasteurizador Botellas' }],
    'encajonadora':    [{ id: '9997',  nombre: 'Encajonadora' }],
    'desencajonadora': [{ id: '10004', nombre: 'Desencajonadora' }],
    'despaletizadora': [{ id: '9996',  nombre: 'Despaletizadora' }],
    'paletizadora':    [{ id: '9995',  nombre: 'Paletizadora' }],
    'pz':              [{ id: '9993',  nombre: 'Pasteurizador Botellas' }],
    'depa/pale':       [{ id: '9996',  nombre: 'Despaletizadora' }, { id: '9995',  nombre: 'Paletizadora' }],
    'enca/desenca':    [{ id: '9997',  nombre: 'Encajonadora' }, { id: '10004', nombre: 'Desencajonadora' }, { id: '10002', nombre: 'Lavadora de Cajas' }],
    'bt4':             [{ id: '9993',  nombre: 'Pasteurizador Botellas' }],
    'bt5':             [{ id: '9999',  nombre: 'Etiquetadora' }],
};

function esMarcadorNoLaboral(valor) {
    if (!valor) return false;
    const s = String(valor).trim().toLowerCase();
    return ['descanso','vacaciones','vacacion','libre','permiso','incapacidad','licencia','reposo','feriado','no labora','no trabaja','no data'].some(token => s.includes(token));
}

function normalizarTextoComparacion(v) { return String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim(); }
function tokensNombre(v) { return normalizarTextoComparacion(v).split(' ').map(t => t.trim()).filter(t => t.length >= 3); }

function resolverOperadorPorNombre(nombreExcel) {
    const nombreNorm = normalizarTextoComparacion(nombreExcel); if (!nombreNorm) return null;
    const tokensExcel = tokensNombre(nombreNorm); if (!tokensExcel.length) return null;
    const candidatos = operadoresCatalogo.map(op => {
        const nOpNorm = normalizarTextoComparacion(op.nombreoperador);
        const tOp = tokensNombre(nOpNorm);
        const score = tOp.filter(t => tokensExcel.includes(t)).length;
        return { op, score, nOpNorm, tOp };
    }).filter(i => i.score > 0).sort((a,b) => b.score - a.score || b.nOpNorm.length - a.nOpNorm.length);
    if (!candidatos.length) return null;
    const mejor = candidatos[0]; const empate = candidatos.filter(c => c.score === mejor.score);
    if (mejor.nOpNorm === nombreNorm) return mejor.op;
    if (tokensExcel.length >= 2 && mejor.score >= 2 && empate.length === 1) return mejor.op;
    if (tokensExcel.length === 1 && mejor.score === 1 && empate.length === 1 && mejor.tOp.length === 1) return mejor.op;
    return null;
}

function resolverOperadorCasoEspecial(nombreExcel) {
    const n = normalizarTextoComparacion(nombreExcel); if (!n) return null;
    if (n.includes('lindsay') && n.includes('lecaro')) return operadoresCatalogo.find(o => normalizarTextoComparacion(o.nombreoperador) === 'lindsay lecaro') || null;
    if (n.includes('edison') && n.includes('asencio')) return operadoresCatalogo.find(o => normalizarTextoComparacion(o.nombreoperador) === 'edison asencio') || null;
    return null;
}

function resolverMaquinas(equipoStr, linea) {
    if (!equipoStr) return [];
    const key = equipoStr.trim().toLowerCase(); if (esMarcadorNoLaboral(key)) return [];
    const mapa = linea === 'Latas' ? MAQUINAS_LATAS_MAP : MAQUINAS_BOTELLAS_MAP;
    if (mapa[key]) return mapa[key];
    const match = maquinasCatalogo.filter(m => !m.linea || m.linea === linea || linea === '').find(m => m.nombre && (m.nombre.toLowerCase() === key || m.nombre.toLowerCase().includes(key) || key.includes(m.nombre.toLowerCase())));
    return match ? [{ id: match.id_maquina, nombre: match.nombre }] : [];
}

let maquinasCatalogo = [], operadoresCatalogo = [], horarioPreviewData = [];

async function initHorariosView() {
    if (!maquinasCatalogo.length) { const { data } = await supabase.from('maquinas').select('id_maquina, nombre, linea'); maquinasCatalogo = data || []; }
    if (!operadoresCatalogo.length) { const { data } = await supabase.from('operadores').select('id_operador, cedula, nombreoperador, linea'); operadoresCatalogo = data || []; }
    el('manual-operador').innerHTML = '<option value="">Seleccionar operador...</option>' + operadoresCatalogo.map(o => `<option value="${o.id_operador}">${o.nombreoperador}</option>`).join('');
    el('manual-maquina').innerHTML = '<option value="">Seleccionar máquina...</option>' + maquinasCatalogo.map(m => `<option value="${m.id_maquina}">${m.nombre} (${m.linea})</option>`).join('');
    el('manual-fecha').value = getLunesProximo();
    initSemanaSelector(); cargarTurnosRecientes();
}

function _getHoyEc() { return new Date(new Date().toLocaleString("en-US", { timeZone: "America/Guayaquil" })); }
function getLunesProximo() { const hoy = _getHoyEc(), dia = hoy.getDay(), diff = dia === 0 ? 1 : dia === 1 ? 0 : (8 - dia); const lunes = new Date(hoy); lunes.setDate(hoy.getDate() + diff); return _fechaLocal(lunes); }
function getLunesSiguiente() { const hoy = _getHoyEc(), dia = hoy.getDay(); let diff = (dia === 0) ? 1 : (dia <= 4) ? 8 - dia : 8 - dia; const lunes = new Date(hoy); lunes.setDate(hoy.getDate() + diff); return _fechaLocal(lunes); }
function _fechaLocal(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

function initSemanaSelector() {
    const mesSel = el('semana-mes-sel'); if (!mesSel) return;
    const hoy = _getHoyEc(), year = hoy.getFullYear(), cM = hoy.getMonth() + 1;
    const meses = []; for (let i = -1; i <= 3; i++) {
        const d = new Date(year, (cM - 1) + i, 1); const val = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
        const label = d.toLocaleString('es-EC', { month: 'long', year: 'numeric' }); meses.push(`<option value="${val}">${label.charAt(0).toUpperCase() + label.slice(1)}</option>`);
    }
    mesSel.innerHTML = meses.join(''); mesSel.value = year + '-' + String(cM).padStart(2, '0'); actualizarSemanasDelMes(true);
}

function actualizarSemanasDelMes(seleccionarActual = false) {
    const mesSel = el('semana-mes-sel'), numSel = el('semana-num-sel'); if (!mesSel || !numSel) return;
    const [year, month] = mesSel.value.split('-').map(Number);
    const lastDay = new Date(year, month, 0); let d = new Date(year, month - 1, 1); while (d.getDay() !== 1) { d.setDate(d.getDate() - 1); }
    const lunesActual = getLunesProximo(), options = []; let weekNum = 1, valToSelect = null;
    for (let i = 0; i < 6; i++) {
        const mondayStr = _fechaLocal(d); if (d > lastDay && i > 0) break;
        const sunday = new Date(d); sunday.setDate(d.getDate() + 6);
        options.push(`<option value="${mondayStr}">Semana ${weekNum} (${d.getDate()} ${d.toLocaleString('es-EC',{month:'short'})} - ${sunday.getDate()} ${sunday.toLocaleString('es-EC',{month:'short'})})</option>`);
        if (seleccionarActual && mondayStr === lunesActual) valToSelect = mondayStr;
        d.setDate(d.getDate() + 7); weekNum++;
    }
    numSel.innerHTML = options.join(''); if (valToSelect) numSel.value = valToSelect; cargarVistaSemana();
}

window.switchHorarioTab = (tab) => {
    ['excel','manual','semana','config'].forEach(t => {
        el(`tab-${t}`).classList.toggle('hidden', t !== tab); const btn = el(`tab-${t}-btn`);
        if (t === tab) { btn.style.background = 'rgba(0,137,61,0.1)'; btn.style.color = 'var(--hk-green-light)'; btn.style.borderColor = 'var(--hk-border) var(--hk-border) transparent var(--hk-border)'; }
        else { btn.style.background = 'transparent'; btn.style.color = '#9ca3af'; btn.style.borderColor = 'transparent'; }
    });
    if (tab === 'semana') cargarVistaSemana(); if (tab === 'config') renderConfigTab();
}

function renderConfigTab() {
    const markers = ['descanso','vacaciones','vacacion','libre','permiso','incapacidad','licencia','reposo','feriado','no labora','no trabaja','no data'];
    const tagsDiv = el('config-no-laboral-tags'); if (tagsDiv) tagsDiv.innerHTML = markers.map(m => `<span class="px-2.5 py-1 rounded-lg text-[10px] font-mono font-semibold" style="background:rgba(239,68,68,0.08); color:#f87171; border:1px solid rgba(239,68,68,0.15)">${m}</span>`).join('');
    const renderMap = (map, containerId, color) => {
        const container = el(containerId); if (!container) return;
        container.innerHTML = Object.entries(map).map(([key, machines]) => {
            const machineHtml = machines.map(m => `<div class="flex items-center gap-1.5"><span class="text-[10px] font-mono px-1.5 py-0.5 rounded" style="background:rgba(255,255,255,0.04); border:1px solid var(--hk-border); color:#9ca3af">${m.id}</span><span class="text-xs text-gray-300">${m.nombre}</span>${m.fallback ? `<span class="text-[9px] ml-1 px-1 py-0.5 rounded" style="background:rgba(245,158,11,0.1); color:#fbbf24; border:1px solid rgba(245,158,11,0.2)">fallback</span>` : ''}</div>`).join('');
            return `<div class="flex items-start gap-3 p-2 rounded-lg" style="background:var(--hk-surface-2)"><div class="flex-shrink-0 min-w-[100px]"><span class="text-xs font-bold text-white px-2 py-1 rounded" style="background:${color}">${key}</span></div><span class="text-gray-600 mt-0.5">→</span><div class="flex flex-col gap-1">${machineHtml}</div></div>`;
        }).join('');
    };
    renderMap(MAQUINAS_LATAS_MAP, 'config-map-latas', 'rgba(234,179,8,0.2)'); renderMap(MAQUINAS_BOTELLAS_MAP, 'config-map-botellas', 'rgba(99,102,241,0.2)');
}

window.handleHorarioDrop = (e) => { e.preventDefault(); el('excel-dropzone').style.borderColor = 'var(--hk-border)'; const file = e.dataTransfer.files[0]; if (file) processHorarioExcel(file); }
window.processHorarioExcel = async (file) => {
    if (!file) return; showToast('Procesando Excel...', 'info', 2000); toggleClass('app-loading', 'hidden', false);
    try {
        const buffer = await file.arrayBuffer(), wb = XLSX.read(buffer, { type: 'array', cellDates: true, raw: true });
        const config = [{ keywords: ['lata'], linea: 'Latas' }, { keywords: ['botella'], linea: 'Botellas' }], registros = [], warnings = []; let encontrada = false;
        for (const { keywords, linea } of config) {
            const hojaReal = wb.SheetNames.find(n => keywords.some(kw => n.toLowerCase().includes(kw))); if (!hojaReal) continue;
            encontrada = true; parsearHoja(XLSX.utils.sheet_to_json(wb.Sheets[hojaReal], { header: 1, defval: null, raw: true }), linea, registros, warnings);
        }
        if (!encontrada) { showToast('No se encontró ninguna hoja de horario.', 'error'); return; }
        const explicitKeys = new Set(registros.filter(r => !r.is_fallback && r.id_maquina).map(r => `${r.fecha}|${r.turno}|${r.id_maquina}`));
        horarioPreviewData = registros.filter(r => !r.is_fallback || !explicitKeys.has(`${r.fecha}|${r.turno}|${r.id_maquina}`)); mostrarPreview(horarioPreviewData, warnings);
    } catch (err) { showToast('Error: ' + err.message, 'error'); } finally { toggleClass('app-loading', 'hidden', true); }
}

function parsearHoja(filas, linea, registros, warnings) {
    let fIdx = -1, fechas = []; for (let r = 0; r < Math.min(10, filas.length); r++) {
        const candidatos = []; if (filas[r]) for (let c = 0; c < filas[r].length; c++) if (filas[r][c] instanceof Date) candidatos.push({ col: c, fecha: filas[r][c] });
        if (candidatos.length > 3) { fIdx = r; fechas = candidatos; break; }
    }
    if (fIdx < 0) return; const lunesStr = getLunesSiguiente(), [ly, lm, ld] = lunesStr.split('-').map(Number), lD = new Date(ly, lm - 1, ld), dD = new Date(ly, lm - 1, ld + 6);
    const fS = fechas.filter(({ fecha }) => { const d = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate()); return d >= lD && d <= dD; });
    if (!fS.length) fS.push(...fechas.slice(0, 7)); if (fS.length) { el('semana-rango').textContent = `${fS[0].fecha.toLocaleDateString('es-EC')} → ${fS[fS.length-1].fecha.toLocaleDateString('es-EC')}`; el('semana-aviso').textContent = `(${fS.length} días, ${linea})`; el('semana-detectada').classList.remove('hidden'); }
    let colC = -1, hIdx = -1; for (let r = Math.max(0, fIdx-3); r < Math.min(filas.length, fIdx+3); r++) if (filas[r]) for (let c = 0; c < filas[r].length; c++) if (String(filas[r][c] || '').toLowerCase().includes('cedula')) { colC = c; hIdx = r; break; }
    if (colC < 0) return; const colO = linea === 'Latas' ? { horario: -1, codigo: 1, maquina: 0 } : { horario: -2, codigo: -2, maquina: 0 };
    for (let r = hIdx + 1; r < filas.length; r++) {
        if (!filas[r]) continue; const ced = String(filas[r][colC] || '').trim().replace(/\.0$/, ''), nE = String(filas[r][colC+2] || '').trim().toUpperCase();
        if (!ced && !nE) continue; if (ced && (ced.length < 5 || isNaN(ced))) continue;
        let op = resolverOperadorCasoEspecial(nE); if (!op && ced) { const pC = operadoresCatalogo.filter(o => o.cedula === ced); op = pC.length === 1 ? pC[0] : (pC.length > 1 ? resolverOperadorPorNombre(nE) : operadoresCatalogo.find(o => o.id_operador === ced)); }
        if (!op && nE) op = resolverOperadorPorNombre(nE);
        for (const { col: fC, fecha } of fS) {
            const hR = filas[r][fC+colO.horario], cR = filas[r][fC+colO.codigo], mR = filas[r][fC+colO.maquina];
            if (esMarcadorNoLaboral(hR) || esMarcadorNoLaboral(cR) || esMarcadorNoLaboral(mR)) continue;
            const turno = horarioATurno(hR) || horarioATurno(cR); if (!turno) continue;
            const mRues = resolverMaquinas(mR ? String(mR).trim() : '', linea), fStr = _fechaLocal(fecha);
            if (!mRues.length) { if (op) registros.push({ id_operador: op.id_operador, cedula_excel: ced, nombre_operador: op.nombreoperador, id_maquina: null, nombre_maquina: (mR?String(mR).trim():'?'), fecha: fStr, turno, linea, ok: false, warn_op: false, warn_maq: true }); }
            else for (const maq of mRues) registros.push({ id_operador: (op?op.id_operador:ced), cedula_excel: ced, nombre_operador: (op?op.nombreoperador:ced), id_maquina: maq.id, nombre_maquina: maq.nombre, fecha: fStr, turno, linea, ok: !!op, warn_op: !op, warn_maq: false, is_fallback: !!maq.fallback });
        }
    }
}

function horarioATurno(v) {
    if (!v) return null; const s = String(v).trim();
    if (s.includes('07:30') || s.includes('06:00')) return 'Mañana';
    if (s.includes('15:30') || s.includes('14:00') || s.includes('16:00')) return 'Tarde';
    if (s.includes('19:30') || s.includes('23:30') || s.includes('22:00')) return 'Noche';
    if (isNaN(parseFloat(s))) return null; const c = parseFloat(s);
    if ([1, 4, 14].includes(c)) return 'Mañana'; if ([5, 15].includes(c)) return 'Tarde'; if ([7, 9].includes(c)) return 'Noche';
    return null;
}

function mostrarPreview(registros, warnings) {
    if (!registros.length) return; el('preview-count').textContent = `${registros.length} registros`;
    el('preview-tbody').innerHTML = registros.map(r => `<tr style="border-top:1px solid var(--hk-border)"><td class="px-3 py-1.5 text-gray-300">${r.nombre_operador}</td><td class="px-3 py-1.5 font-mono" style="color:${r.warn_op ? '#f87171' : '#9ca3af'}">${r.cedula_excel}</td><td class="px-3 py-1.5"><span class="px-1.5 py-0.5 rounded text-xs font-bold" style="background:${r.linea==='Latas'?'rgba(234,179,8,0.15)':'rgba(99,102,241,0.15)'}; color:${r.linea==='Latas'?'#fde047':'#a5b4fc'}">${r.linea}</span></td><td class="px-3 py-1.5" style="color:${r.warn_maq ? '#f87171' : '#d1d5db'}">${r.nombre_maquina}${r.id_maquina ? '' : ' ⚠️'}</td><td class="px-3 py-1.5 font-mono text-gray-400">${r.fecha}</td><td class="px-3 py-1.5"><span class="px-2 py-0.5 rounded text-xs font-semibold" style="background:${r.turno==='Mañana'?'rgba(234,179,8,0.2)':r.turno==='Tarde'?'rgba(249,115,22,0.2)':'rgba(99,102,241,0.2)'}; color:${r.turno==='Mañana'?'#fde047':r.turno==='Tarde'?'#fb923c':'#a5b4fc'}">${r.turno}</span></td><td class="px-3 py-1.5">${r.ok ? '<span style="color:#4ade80">✅ OK</span>' : '<span style="color:#f87171">⚠️ Revisar</span>'}</td></tr>`).join('');
    const wDiv = el('preview-warnings'), allW = [...warnings], sinOp = registros.filter(r => r.warn_op).length, sinMaq = registros.filter(r => r.warn_maq).length;
    if (sinOp > 0) allW.push(`⚠️ ${sinOp} registros con operador no encontrado (se omitirán)`); if (sinMaq > 0) allW.push(`⚠️ ${sinMaq} registros con máquina no encontrada (se omitirán)`);
    if (allW.length) { wDiv.innerHTML = allW.map(w => `<div class="text-xs px-3 py-1.5 rounded" style="background:rgba(245,158,11,0.1); border:1px solid rgba(245,158,11,0.3); color:#fcd34d">${w}</div>`).join(''); wDiv.classList.remove('hidden'); }
    else wDiv.classList.add('hidden'); el('horario-preview').classList.remove('hidden');
}

window.clearHorarioPreview = () => { horarioPreviewData = []; el('horario-preview').classList.add('hidden'); el('semana-detectada').classList.add('hidden'); el('horario-excel-input').value = ''; }
window.importarHorario = async () => {
    const validos = horarioPreviewData.filter(r => r.ok); if (!validos.length) return;
    const btn = el('btn-importar-horario'); btn.disabled = true; btn.textContent = 'Importando...'; toggleClass('app-loading', 'hidden', false);
    try {
        const fechas = [...new Set(validos.map(r => r.fecha))]; await supabase.from('turnos_semana').delete().in('fecha', fechas);
        const seen = new Set(), payload = validos.reduce((acc, r) => { const key = `${r.id_operador}|${r.id_maquina}|${r.fecha}|${r.turno}`; if (!seen.has(key)) { seen.add(key); acc.push({ id_operador: r.id_operador, id_maquina: r.id_maquina, fecha: r.fecha, turno: r.turno }); } return acc; }, []);
        const BATCH = 200; for (let i = 0; i < payload.length; i += BATCH) await supabase.from('turnos_semana').insert(payload.slice(i, i + BATCH));
        showToast(`${validos.length} turnos importados correctamente.`, 'success'); clearHorarioPreview(); switchHorarioTab('semana'); cargarVistaSemana();
    } catch (err) { showToast('Error: ' + err.message, 'error'); } finally { btn.disabled = false; btn.textContent = 'Importar a Supabase'; toggleClass('app-loading', 'hidden', true); }
}

window.guardarTurnoManual = async () => {
    const idO = el('manual-operador').value, idM = el('manual-maquina').value, fec = el('manual-fecha').value, tur = el('manual-turno').value;
    if (!idO || !idM || !fec || !tur) return;
    const { error } = await supabase.from('turnos_semana').upsert([{ id_operador: idO, id_maquina: idM, fecha: fec, turno: tur }], { onConflict: 'id_operador,fecha,turno,id_maquina' });
    if (error) showToast('Error: ' + error.message, 'error'); else { showToast('Guardado.', 'success'); cargarTurnosRecientes(); }
}

async function cargarTurnosRecientes() {
    const { data } = await supabase.from('turnos_semana').select('id, id_operador, id_maquina, fecha, turno, created_at, operadores(nombreoperador), maquinas(nombre)').order('created_at', { ascending: false }).limit(10);
    const div = el('manual-recientes'); if (!data || !data.length) { div.innerHTML = '<p class="p-4 text-gray-500 text-xs">Sin turnos.</p>'; return; }
    div.innerHTML = `<table class="w-full text-xs"><thead style="background:var(--hk-surface)"><tr><th class="px-3 py-2 text-left text-gray-400">Operador</th><th class="px-3 py-2 text-left text-gray-400">Máquina</th><th class="px-3 py-2 text-left text-gray-400">Fecha</th><th class="px-3 py-2 text-left text-gray-400">Turno</th><th class="px-3 py-2"></th></tr></thead><tbody style="background:var(--hk-surface-2)">${data.map(t => `<tr style="border-top:1px solid var(--hk-border)"><td class="px-3 py-1.5 text-gray-300">${t.operadores?.nombreoperador || t.id_operador}</td><td class="px-3 py-1.5 text-gray-300">${t.maquinas?.nombre || t.id_maquina}</td><td class="px-3 py-1.5 text-gray-400">${t.fecha}</td><td class="px-3 py-1.5 text-gray-400">${t.turno}</td><td class="px-3 py-1.5"><button onclick="borrarTurno('${t.id}')" class="text-red-400 hover:text-red-300 text-xs">✕</button></td></tr>`).join('')}</tbody></table>`;
}

window.borrarTurno = async (id) => { const { error } = await supabase.from('turnos_semana').delete().eq('id', id); if (error) showToast('Error: ' + error.message, 'error'); else { showToast('Eliminado.', 'info'); cargarTurnosRecientes(); } }

async function cargarVistaSemana() {
    const numSel = el('semana-num-sel'); const fI = numSel ? numSel.value : getLunesProximo();
    const [_vy, _vm, _vd] = fI.split('-').map(Number); const fF = _fechaLocal(new Date(_vy, _vm - 1, _vd + 6));
    toggleClass('app-loading', 'hidden', false);
    const { data } = await supabase.from('turnos_semana').select('id_operador, id_maquina, fecha, turno, operadores(nombreoperador), maquinas(nombre, linea)').gte('fecha', fI).lte('fecha', fF).order('fecha').order('id_maquina');
    toggleClass('app-loading', 'hidden', true);
    const div = el('semana-grid'); if (!data || !data.length) { div.innerHTML = '<p class="text-gray-500 text-sm p-4">No hay turnos.</p>'; return; }
    const dias = []; for (let i = 0; i <= 6; i++) { const dO = new Date(_vy, _vm - 1, _vd + i); dias.push({ str: _fechaLocal(dO), label: dO.toLocaleDateString('es-EC', { weekday: 'short', day: 'numeric', month: 'short' }) }); }
    const turnos = ['Mañana', 'Tarde', 'Noche'], tC = { Mañana: '#854d0e', Tarde: '#7c2d12', Noche: '#312e81' }, tTC = { Mañana: '#fde047', Tarde: '#fb923c', Noche: '#a5b4fc' };
    const porLinea = {}, nMaq = {}; maquinasCatalogo.forEach(m => { const l = m.linea || 'Otras'; if (!porLinea[l]) porLinea[l] = {}; if (!porLinea[l][m.id_maquina]) porLinea[l][m.id_maquina] = {}; nMaq[m.id_maquina] = m.nombre; });
    for (const t of data) { const l = t.maquinas?.linea || 'Otras', mI = t.id_maquina; if (!porLinea[l]) porLinea[l] = {}; if (!porLinea[l][mI]) porLinea[l][mI] = {}; nMaq[mI] = t.maquinas?.nombre || mI; const key = `${t.fecha}_${t.turno}`; if (!porLinea[l][mI][key]) porLinea[l][mI][key] = []; porLinea[l][mI][key].push(t.operadores?.nombreoperador || `ID: ${t.id_operador}`); }
    const lColors = { Latas: { bg: 'rgba(234,179,8,0.12)', border: 'rgba(234,179,8,0.4)', text: '#fde047' }, Botellas: { bg: 'rgba(99,102,241,0.12)', border: 'rgba(99,102,241,0.4)', text: '#a5b4fc' } };
    const rTabla = (lin, porM) => {
        const lc = lColors[lin] || { bg: 'rgba(255,255,255,0.05)', border: 'var(--hk-border)', text: '#e5e7eb' };
        return `<div class="mb-6"><div class="line-header-badge" style="background:${lc.bg}; border:1px solid ${lc.border}; color:${lc.text}">Línea de ${lin}</div><div class="sched-container"><table class="sched-table"><thead><tr><th class="sticky-col" style="text-align:left">Máquina</th><th class="sticky-col-2">Turno</th>${dias.map(d => `<th>${d.label}</th>`).join('')}</tr></thead><tbody>${Object.entries(porM).map(([mI, slots]) => turnos.map((tur, ti) => `<tr class="sched-row">${ti === 0 ? `<td class="sticky-col text-white" style="vertical-align:middle; font-weight:600; font-size:0.6rem" rowspan="3">${nMaq[mI]}</td>` : ''}<td class="sticky-col-2"><span class="turno-label" style="background:${tC[tur]}30; color:${tTC[tur]}">${tur}</span></td>${dias.map(d => { const k = `${d.str}_${tur}`, ops = slots[k] || []; return `<td style="text-align:center">${ops.length ? ops.map(op => `<div class="op-badge">${op}</div>`).join('') : '<span class="cell-empty">—</span>'}</td>`; }).join('')}</tr>`).join('')).join('')}</tbody></table></div></div>`;
    };
    div.innerHTML = ['Latas', 'Botellas', ...Object.keys(porLinea).filter(l => l !== 'Latas' && l !== 'Botellas')].filter(l => porLinea[l]).map(l => rTabla(l, porLinea[l])).join('');
}

window.borrarSemana = async () => {
    const numSel = el('semana-num-sel'); const fI = numSel ? numSel.value : getLunesProximo();
    const [_by, _bm, _bd] = fI.split('-').map(Number); const fF = _fechaLocal(new Date(_by, _bm - 1, _bd + 6));
    if (!confirm(`¿Borrar turnos del ${fI} al ${fF}?`)) return;
    const { error } = await supabase.from('turnos_semana').delete().gte('fecha', fI).lte('fecha', fF);
    if (error) showToast('Error: ' + error.message, 'error'); else { showToast('Semana eliminada.', 'info'); cargarVistaSemana(); }
}

window.uploadImageToSupabase = async (fileInput, targetInputId) => {
    const file = fileInput.files[0]; if (!file) return;
    toggleClass('app-loading', 'hidden', false); showToast('Subiendo...', 'info', 2000);
    const fileName = `${Date.now()}-${Math.floor(Math.random()*1000)}.${file.name.split('.').pop()}`, filePath = `pasos/${fileName}`;
    try {
        const { error } = await supabase.storage.from('pasosimagen').upload(filePath, file); if (error) throw error;
        const { data: { publicUrl } } = supabase.storage.from('pasosimagen').getPublicUrl(filePath);
        document.getElementById(targetInputId).value = publicUrl; showToast('Subida.', 'success');
    } catch (err) { showToast('Error: ' + err.message, 'error'); } finally { toggleClass('app-loading', 'hidden', true); }
};

window.moveStep = async (id, direction) => {
    toggleClass('app-loading', 'hidden', false);
    try {
        const { data: steps } = await supabase.from('pasos_tarea').select('id, numeropaso').eq('id_tarea', gtsState.task).order('numeropaso');
        const idx = steps.findIndex(s => s.id === id); if (idx < 0 || idx + direction < 0 || idx + direction >= steps.length) { toggleClass('app-loading', 'hidden', true); return; }
        const element = steps.splice(idx, 1)[0]; steps.splice(idx + direction, 0, element);
        await Promise.all(steps.map((s, i) => supabase.from('pasos_tarea').update({ numeropaso: i + 1 + 1000 }).eq('id', s.id)));
        await Promise.all(steps.map((s, i) => supabase.from('pasos_tarea').update({ numeropaso: i + 1 }).eq('id', s.id)));
        renderGTS('steps', gtsState.task, true, gtsState.taskName);
    } catch (err) { showToast('Error al reordenar', 'error'); } finally { toggleClass('app-loading', 'hidden', true); }
};

window.changeView = changeView;
window.actualizarSemanasDelMes = actualizarSemanasDelMes;
window.fetchData = fetchData;
window.openEditor = openEditor;
window.renderGTS = renderGTS;
