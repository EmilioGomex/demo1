import zipfile, xml.etree.ElementTree as ET, re
from collections import defaultdict
from datetime import datetime, timedelta

path = r'c:\eCILT\demo1\ADMINCILT\GRENVTPM003 Horarios envasado 000.xlsx'
ns = {'a': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def col_to_num(col):
    n = 0
    for ch in col:
        if ch.isalpha():
            n = n * 26 + ord(ch.upper()) - 64
    return n

def excel_date_to_str(val):
    try:
        base = datetime(1899, 12, 30)
        dt = base + timedelta(days=float(val))
        return f"{dt.day}/{dt.month}/{dt.year}"
    except Exception:
        return str(val)

with zipfile.ZipFile(path) as z:
    sst = []
    sroot = ET.fromstring(z.read('xl/sharedStrings.xml'))
    for si in sroot.findall('a:si', ns):
        txt = ''.join(t.text or '' for t in si.iter('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t'))
        sst.append(txt)

    root = ET.fromstring(z.read('xl/worksheets/sheet3.xml'))
    rows = {}
    for row in root.find('a:sheetData', ns).findall('a:row', ns):
        rnum = int(row.attrib['r'])
        vals = {}
        for c in row.findall('a:c', ns):
            ref = c.attrib['r']
            m = re.match(r'([A-Z]+)(\d+)', ref)
            col = col_to_num(m.group(1))
            t = c.attrib.get('t')
            v = c.find('a:v', ns)
            if v is None:
                val = ''
            elif t == 's':
                val = sst[int(v.text)]
            else:
                val = v.text or ''
            vals[col] = val
        rows[rnum] = vals

header = rows[10]
fechas = []
for col, val in sorted(header.items()):
    if re.fullmatch(r'\d+(\.\d+)?', str(val)):
        ds = excel_date_to_str(val)
        if ds in {'20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026'}:
            fechas.append((col, ds))

BOT_MAP = {
    'llenadora': [('Llenadora', False), ('Inspector de Botellas Vacias', False)],
    'etiquetadora': [('Etiquetadora', False), ('Pasteurizador', True)],
    'lavadora': [('Lavadora', False)],
    'pasteurizador': [('Pasteurizador', False)],
    'encajonadora': [('Encajonadora', False)],
    'desencajonadora': [('Desencajonadora', False)],
    'despaletizadora': [('Despaletizadora', False)],
    'paletizadora': [('Paletizadora', False)],
    'pz': [('Pasteurizador', False)],
    'depa/pale': [('Despaletizadora', False), ('Paletizadora', False)],
    'enca/desenca': [('Encajonadora', False), ('Desencajonadora', False), ('Lavadora de Cajas', False)],
    'bt4': [('Pasteurizador', False)],
    'bt5': [('Etiquetadora', False)],
}

def turno(horario, codigo):
    s = str(horario or '').strip()
    if '07:30' in s or '06:00' in s: return 'Manana'
    if '15:30' in s or '14:00' in s or '16:00' in s: return 'Tarde'
    if '19:30' in s or '23:30' in s or '22:00' in s: return 'Noche'
    try:
        c = float(str(codigo).strip())
    except Exception:
        return None
    if c in (1,4,14): return 'Manana'
    if c in (5,15): return 'Tarde'
    if c in (7,9): return 'Noche'
    return None

def no_labora(*vals):
    s = ' '.join(str(v or '').lower() for v in vals)
    return any(x in s for x in ['descanso','vacaciones','vacacion','feriado','evento','cumple','medico','calamidad'])

records = []
for rnum, row in rows.items():
    if rnum <= 10:
        continue
    nombre = str(row.get(3,'')).strip()
    if not nombre:
        continue
    for fc, ds in fechas:
        horario = row.get(fc-1, '')
        codigo = row.get(fc-2, '')
        maq = str(row.get(fc, '')).strip()
        if not maq or no_labora(horario, codigo, maq):
            continue
        t = turno(horario, codigo)
        if not t:
            continue
        mapped = BOT_MAP.get(maq.lower().strip(), [(maq, False)])
        for out_maq, fallback in mapped:
            records.append((out_maq, t, ds, nombre, fallback))

explicit = {(maq, t, ds) for maq, t, ds, nombre, fallback in records if not fallback}
final = []
for rec in records:
    maq, t, ds, nombre, fallback = rec
    if fallback and (maq, t, ds) in explicit:
        continue
    final.append(rec)

wanted = ['Pasteurizador','Paletizadora','Despaletizadora','Encajonadora','Llenadora','Etiquetadora','Inspector de Botellas Vacias','Lavadora','Lavadora de Cajas','Desencajonadora']
order_days = ['20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026']
agg = defaultdict(list)
for maq, t, ds, nombre, fallback in final:
    agg[(maq, t, ds)].append(nombre)
for maq in wanted:
    print('MACHINE=' + maq)
    for t in ['Manana','Tarde','Noche']:
        vals = []
        for ds in order_days:
            names = sorted(set(agg.get((maq, t, ds), [])))
            vals.append(', '.join(names) if names else '-')
        print('  ' + t + ' => ' + ' || '.join(vals))
    print('---')
