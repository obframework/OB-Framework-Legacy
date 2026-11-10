/* Exporta somente alteracoes confirmadas pelas natives. Nunca inventa SubHandlingData. */
window.HandlingXML = (() => {
    const axes = ['x', 'y', 'z'];
    const equal = (a, b) => typeof a === 'object' && a !== null
        ? axes.every(k => Math.abs(a[k] - b[k]) < 0.000001) : Math.abs(a - b) < 0.000001;
    function decimal(value) {
        if (!Number.isFinite(value)) throw new Error('Valor não finito na exportação.');
        return value.toFixed(6);
    }
    function changes(fields, values, original) {
        return fields.filter(f => !equal(values[f.key], original[f.key]));
    }
    function snippet(fields, values, original) {
        const changed = changes(fields, values, original);
        if (!changed.length) throw new Error('Nenhum campo foi alterado.');
        return '<!-- TRECHO: substitua estas tags no Item original. Não é um arquivo completo. -->\n' + changed.map(f => {
            const v = values[f.key];
            const attributes = f.type === 'vector' ? axes.map(k => `${k}="${decimal(v[k])}"`).join(' ')
                : `value="${f.type === 'int' ? Math.round(v) : decimal(v)}"`;
            return `<${f.key} ${attributes} />`;
        }).join('\n');
    }
    function parse(text) {
        if (!text || text.length > 2000000 || /<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error('XML vazio, grande demais ou com declaração não permitida.');
        const doc = new DOMParser().parseFromString(text, 'application/xml');
        if (doc.querySelector('parsererror')) throw new Error('XML inválido. Cole o arquivo original completo.');
        if (doc.documentElement.tagName !== 'CHandlingDataMgr') throw new Error('O XML deve começar com CHandlingDataMgr.');
        const data = [...doc.documentElement.children].find(e => e.tagName === 'HandlingData');
        const entries = data ? [...data.children].filter(e => e.tagName === 'Item' && e.getAttribute('type') === 'CHandlingData') : [];
        const names = entries.map(e => [...e.children].find(c => c.tagName === 'handlingName')?.textContent.trim());
        if (!entries.length || names.some(n => !n)) throw new Error('Nenhuma entrada CHandlingData válida foi encontrada.');
        return { doc, entries, names };
    }
    function complete(text, index, fields, values, original) {
        const parsed = parse(text);
        const entry = parsed.entries[index];
        if (!entry) throw new Error('Selecione a handling original do carro.');
        const changed = changes(fields, values, original);
        if (!changed.length) throw new Error('Nenhum campo foi alterado.');
        for (const f of changed) {
            const matches = [...entry.children].filter(e => e.tagName === f.key);
            if (matches.length !== 1) throw new Error(`O XML original deve conter exatamente uma tag ${f.key}.`);
            const tag = matches[0], v = values[f.key];
            if (f.type === 'vector') axes.forEach(k => tag.setAttribute(k, decimal(v[k])));
            else tag.setAttribute('value', f.type === 'int' ? String(Math.round(v)) : decimal(v));
        }
        const xml = new XMLSerializer().serializeToString(parsed.doc);
        return xml.startsWith('<?xml') ? xml : '<?xml version="1.0" encoding="UTF-8"?>\n' + xml;
    }
    return { equal, changes, snippet, parse, complete };
})();
