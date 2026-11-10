(() => {
  'use strict';

  const defaults = Object.freeze({
    code: 'USD',
    locale: 'en-US',
    symbol: '$',
    symbolPosition: 'before',
    spaceBetween: false,
    decimals: 0,
    thousandsSeparator: ',',
    decimalSeparator: '.',
  });

  let config = { ...defaults };

  const configure = (value) => {
    const candidate = value && typeof value === 'object' ? value : {};
    const decimals = Math.max(0, Math.min(4, Math.floor(Number(candidate.decimals ?? defaults.decimals))));
    config = {
      code: typeof candidate.code === 'string' && candidate.code ? candidate.code : defaults.code,
      locale: typeof candidate.locale === 'string' && candidate.locale ? candidate.locale : defaults.locale,
      symbol: typeof candidate.symbol === 'string' && candidate.symbol ? candidate.symbol : defaults.symbol,
      symbolPosition: candidate.symbolPosition === 'after' ? 'after' : 'before',
      spaceBetween: candidate.spaceBetween === true,
      decimals,
      thousandsSeparator: typeof candidate.thousandsSeparator === 'string' ? candidate.thousandsSeparator : defaults.thousandsSeparator,
      decimalSeparator: typeof candidate.decimalSeparator === 'string' ? candidate.decimalSeparator : defaults.decimalSeparator,
    };
    refresh();
    if (typeof window.dispatchEvent === 'function' && typeof window.CustomEvent === 'function') {
      window.dispatchEvent(new window.CustomEvent('obcurrencychange', { detail: { ...config } }));
    }
    return { ...config };
  };

  const format = (value) => {
    const numeric = Number(value || 0);
    const amount = Number.isFinite(numeric) ? numeric : 0;
    const parts = Math.abs(amount).toFixed(config.decimals).split('.');
    const integer = config.thousandsSeparator
      ? parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, config.thousandsSeparator)
      : parts[0];
    const formatted = config.decimals > 0
      ? `${integer}${config.decimalSeparator}${parts[1]}`
      : integer;

    const spacing = config.spaceBetween ? ' ' : '';
    const sign = amount < 0 ? '-' : '';
    return config.symbolPosition === 'after'
      ? `${sign}${formatted}${spacing}${config.symbol}`
      : `${sign}${config.symbol}${spacing}${formatted}`;
  };

  const refresh = (root) => {
    const target = root || (typeof document !== 'undefined' ? document : null);
    if (!target?.querySelectorAll) return;
    target.querySelectorAll('[data-ob-money]').forEach((node) => {
      const prefix = node.dataset.obPrefix || '';
      const suffix = node.dataset.obSuffix || '';
      node.textContent = `${prefix}${format(node.dataset.obMoney)}${suffix}`;
    });
  };

  window.OBCurrency = { configure, format, refresh, getConfig: () => ({ ...config }) };
  refresh();

  if (typeof GetParentResourceName !== 'function') return;
  fetch(`https://${GetParentResourceName()}/ob_lib_currency`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: '{}',
  })
    .then((response) => response.ok ? response.json() : null)
    .then((value) => { if (value) configure(value); })
    .catch(() => undefined);
})();
