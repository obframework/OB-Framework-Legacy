const $ = id => document.getElementById(id);
let state = null, pending = false, template = '';
const post = async (name, data = {}) => {
    const response = await fetch(`https://${GetParentResourceName()}/${name}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
    const result = await response.json();
    if (result.error) throw new Error(result.error);
    return result;
};
function status(text, error = false) { $('status').textContent = text; $('status').classList.toggle('error', error); }
function locked(value) {
    pending = value;
    document.querySelectorAll('#fields input, #restore, #drive, #generate, #copy').forEach(e => e.disabled = value);
}
function invalidateExport() { $('output').value = ''; $('kind').textContent = ''; }
function updateCount() { status(`${HandlingXML.changes(state.fields, state.values, state.original).length} campos alterados · /${state.command} reabre após o teste.`); }
function render() {
    const container = $('fields'); container.replaceChildren();
    const search = $('search').value.toLowerCase(); let group;
    for (const field of state.fields) {
        if (!`${field.key} ${field.label} ${field.group}`.toLowerCase().includes(search)) continue;
        if (field.group !== group) { const h = document.createElement('h2'); h.textContent = field.group; container.append(h); group = field.group; }
        const row = document.createElement('div'); row.className = 'field';
        row.classList.toggle('changed', !HandlingXML.equal(state.values[field.key], state.original[field.key]));
        const label = document.createElement('label'); label.textContent = field.label;
        const hint = document.createElement('small'); hint.textContent = `${field.key} · ${field.min} a ${field.max}`; label.append(hint);
        const inputs = document.createElement('div'); inputs.className = 'values';
        for (const axis of field.type === 'vector' ? ['x','y','z'] : [null]) {
            const input = document.createElement('input'); input.type = 'number'; input.min = field.min; input.max = field.max; input.step = field.step;
            input.setAttribute('aria-label', `${field.label}${axis ? ' '+axis.toUpperCase() : ''}`);
            const value = axis ? state.values[field.key][axis] : state.values[field.key];
            input.value = Number(value.toFixed(6)); input.title = axis ? axis.toUpperCase() : field.key;
            input.addEventListener('change', async () => {
                if (pending) return;
                const numeric = Number(input.value);
                if (!input.value.trim() || !Number.isFinite(numeric) || numeric < field.min || numeric > field.max || (field.type === 'int' && !Number.isInteger(numeric))) { status('Informe um valor dentro dos limites.', true); input.value = value; return; }
                const updated = axis ? {...state.values[field.key], [axis]:Number(input.value)} : Number(input.value);
                locked(true); status('Aplicando…');
                try {
                    const response = await post('apply', {key:field.key, value:updated});
                    state.values[field.key] = response.value; invalidateExport(); updateCount();
                } catch (e) { status(e.message, true); }
                finally { locked(false); render(); }
            });
            inputs.append(input);
        }
        row.append(label, inputs); container.append(row);
    }
}
function tab(exporting) {
    $('editor').hidden = exporting; $('exporter').hidden = !exporting; $('search').hidden = exporting;
    $('editTab').classList.toggle('active', !exporting); $('exportTab').classList.toggle('active', exporting);
}
window.addEventListener('message', ({data}) => {
    if (data.action === 'hide') { $('panel').hidden = true; return; }
    if (data.action !== 'open') return;
    if (!state || state.tag !== data.tag) {
        template = ''; $('template').value = ''; $('entry').replaceChildren(new Option('Sem XML original','')); invalidateExport(); $('search').value = '';
    }
    state = data; $('car').textContent = data.name; $('panel').hidden = false; tab(false); render(); updateCount();
});
$('search').addEventListener('input', render);
$('editTab').onclick = () => tab(false);
$('exportTab').onclick = () => tab(true);
$('restore').onclick = async () => {
    if (pending) return; locked(true);
    try { state = await post('restore'); invalidateExport(); render(); status('Valores capturados ao abrir restaurados.'); }
    catch(e) { status(e.message,true); } finally { locked(false); }
};
$('drive').onclick = async () => { if (!pending) try { await post('drive'); } catch(e) { status(e.message,true); } };
async function close() { if (pending) return status('Aguarde a aplicação antes de fechar.'); try { await post('close'); } catch(e) { status(e.message,true); } }
$('close').onclick = close;
document.addEventListener('keydown', e => { if (e.key === 'Escape' && !$('panel').hidden) close(); });
$('file').onchange = async () => {
    const file = $('file').files[0]; if (!file) return;
    if (file.size > 2000000) return status('Limite de 2 MB por arquivo.', true);
    $('template').value = await file.text(); template = ''; invalidateExport();
    $('entry').replaceChildren(new Option('Leia o XML original novamente',''));
};
$('template').oninput = () => { template=''; invalidateExport(); $('entry').replaceChildren(new Option('Leia o XML original novamente','')); };
$('loadTemplate').onclick = () => {
    try {
        const text = $('template').value, parsed = HandlingXML.parse(text); template = text;
        $('entry').replaceChildren(new Option('Selecione a handling do carro',''));
        parsed.names.forEach((name,i) => $('entry').append(new Option(name,String(i))));
        if (parsed.names.length === 1) $('entry').value = '0';
        invalidateExport(); status('Original carregado. Selecione a entrada correta antes de gerar.');
    } catch(e) { template=''; status(e.message,true); }
};
$('entry').onchange = invalidateExport;
$('generate').onclick = () => {
    try {
        if (template) {
            if ($('entry').value === '') throw new Error('Selecione a handling original.');
            $('output').value = HandlingXML.complete(template, Number($('entry').value), state.fields, state.values, state.original);
            $('kind').textContent = 'XML completo · original preservado';
        } else {
            if ($('template').value.trim()) throw new Error('Leia o XML colado ou limpe o campo para exportar apenas o trecho.');
            $('output').value = HandlingXML.snippet(state.fields, state.values, state.original);
            $('kind').textContent = 'Somente campos alterados';
        }
        status('Texto gerado. Confira e copie; nenhum arquivo foi modificado.');
    } catch(e) { invalidateExport(); status(e.message,true); }
};
$('copy').onclick = async () => {
    if (!$('output').value) return status('Gere o texto primeiro.', true);
    try { await navigator.clipboard.writeText($('output').value); status('Texto copiado!'); }
    catch {
        $('output').focus(); $('output').select();
        status(document.execCommand('copy') ? 'Texto copiado!' : 'Texto selecionado. Pressione Ctrl+C para copiar.');
    }
};
