// Aplicativos de serviços da cidade: banco e garagem.

const incomingKinds = new Set(["deposit", "refund", "salary", "transfer_in"]);
async function bank(version) {
  content.innerHTML = empty("Consultando sua conta...");
  const result = await post("bank");
  if (version !== pageVersion) return;
  if (!result.ok) {
    content.innerHTML = empty(esc(result.message || "Banco indisponível."));
    return;
  }
  const account = result.data || {},
    transactions = account.transactions || [],
    fines = account.fines || [];
  content.innerHTML =
    '<div class="bank-welcome"><b>Olá novamente</b><small>Conta digital OB</small></div><div class="bank-card"><small>SALDO TOTAL</small><h2>' +
    esc(money(account.balance)) +
    "</h2><div><span>Em mãos " +
    esc(money(account.cash)) +
    "</span><span>•••• " +
    esc(String(account.card?.number || data.number || "").slice(-4)) +
    '</span></div></div><div class="bank-week"><div><small>Entradas em 7 dias</small><b>+' +
    esc(money(account.week?.incoming)) +
    "</b></div><div><small>Saídas em 7 dias</small><b>-" +
    esc(money(account.week?.outgoing)) +
    '</b></div></div><section class="form-card"><div class="form-title"><span class="form-icon">↗</span><div><b>Enviar dinheiro</b><small>Transferência pelo ID do cidadão</small></div></div><input id="transferId" inputmode="numeric" placeholder="ID do destinatário"><div class="money-field"><span>$</span><input id="transferValue" type="number" min="1" placeholder="0"></div><button class="action" data-do="transfer">Confirmar transferência</button></section><div class="section-heading"><b>Multas pendentes</b><span>' +
    esc(money(account.pendingFineTotal)) +
    '</span></div><div class="bank-list">' +
    (fines
      .map(
        (fine) =>
          '<article class="fine-row"><div><b>#' +
          Number(fine.id) +
          " · " +
          esc(fine.reason || "Multa") +
          "</b><small>" +
          esc(fine.officer_name || "Polícia") +
          " · " +
          esc(fine.created_at || "") +
          '</small></div><button data-fine="' +
          Number(fine.id) +
          '">Pagar ' +
          esc(money(fine.fine)) +
          "</button></article>",
      )
      .join("") || empty("Nenhuma multa pendente.")) +
    '</div><div class="section-heading"><b>Últimas transações</b><span>' +
    transactions.length +
    '</span></div><div class="bank-list">' +
    (transactions
      .map((row) => {
        const incoming = incomingKinds.has(row.kind);
        return (
          '<article class="transaction-row"><i class="' +
          (incoming ? "in" : "out") +
          '">' +
          (incoming ? "↙" : "↗") +
          "</i><div><b>" +
          esc(row.description || row.kind) +
          "</b><small>" +
          esc(row.created_at || "") +
          '</small></div><strong class="' +
          (incoming ? "in" : "out") +
          '">' +
          (incoming ? "+" : "-") +
          esc(money(row.amount)) +
          "</strong></article>"
        );
      })
      .join("") || empty("Nenhuma movimentação.")) +
    "</div>";
}
function percent(value) {
  value = Number(value) || 0;
  if (value > 100) value /= 10;
  return Math.max(0, Math.min(100, Math.round(value)));
}
function vehicleImage(model) {
  const config = data.publicConfig || {},
    base = String(config.garageImageBaseUrl || "").replace(/\/+$/, "") + "/",
    safe = String(model || "")
      .toLowerCase()
      .replace(/[^a-z0-9_-]/g, "");
  return {
    src: base + encodeURIComponent(safe || "carro") + ".png",
    fallback:
      base + encodeURIComponent(config.garageImageFallback || "carro.png"),
  };
}
async function garage(version) {
  content.innerHTML = empty("Buscando seus veículos...");
  const result = await post("garage");
  if (version !== pageVersion) return;
  if (!result.ok) {
    content.innerHTML = empty(esc(result.message || "Garagem indisponível."));
    return;
  }
  const cars = Array.isArray(result.data)
      ? result.data
      : result.data?.vehicles || [],
    storedCount = cars.filter((v) => Number(v.stored) === 1).length;
  content.innerHTML =
    '<div class="garage-summary"><div><small>MEUS VEÍCULOS</small><b>' +
    cars.length +
    " veículo" +
    (cars.length === 1 ? "" : "s") +
    "</b><em>" +
    storedCount +
    " guardado" +
    (storedCount === 1 ? "" : "s") +
    " · " +
    (cars.length - storedCount) +
    ' fora</em></div><span>▱</span></div><input class="vehicle-search" id="vehicleSearch" placeholder="Buscar nome, modelo ou placa"><div class="vehicle-list">' +
    (cars
      .map((vehicle) => {
        const stored = Number(vehicle.stored) === 1,
          image = vehicleImage(vehicle.model);
        return (
          '<article class="vehicle-card" data-vehicle="' +
          esc(
            [vehicle.label, vehicle.model, vehicle.plate]
              .join(" ")
              .toLowerCase(),
          ) +
          '"><div class="vehicle-art"><img data-vehicle-image src="' +
          esc(image.src) +
          '" data-fallback="' +
          esc(image.fallback) +
          '" alt="' +
          esc(vehicle.label || vehicle.model || "Veículo") +
          '"></div><div class="vehicle-main"><div><h3>' +
          esc(vehicle.label || vehicle.model || "Veículo") +
          '</h3><span class="status ' +
          (stored ? "stored" : "outside") +
          '">' +
          (stored ? "Guardado" : "Em uso") +
          "</span></div><p><b>" +
          esc(vehicle.plate || "SEM PLACA") +
          "</b><span>" +
          esc(vehicle.garage || "Localização indisponível") +
          '</span></p><div class="vehicle-stats"><span>Combustível <b>' +
          percent(vehicle.fuel) +
          "%</b></span><span>Motor <b>" +
          percent(vehicle.engine) +
          "%</b></span><span>Lataria <b>" +
          percent(vehicle.body) +
          "%</b></span></div>" +
          (!stored
            ? '<button class="track" data-id="' + Number(vehicle.id) + '" data-model="' + esc(vehicle.model) + '" data-plate="' +
              esc(vehicle.plate) +
              '">⌖ Rastrear por 30 segundos</button>'
            : "") +
          "</div></article>"
        );
      })
      .join("") || empty("Nenhum veículo vinculado à sua conta.", "▱")) +
    "</div>";
  content.querySelectorAll("[data-vehicle-image]").forEach(
    (img) =>
      (img.onerror = () => {
        if (img.src !== img.dataset.fallback) {
          img.src = img.dataset.fallback;
        } else img.onerror = null;
      }),
  );
  q("#vehicleSearch")?.addEventListener("input", (event) => {
    const term = event.target.value.toLowerCase();
    content
      .querySelectorAll("[data-vehicle]")
      .forEach((card) =>
        card.classList.toggle("hidden", !card.dataset.vehicle.includes(term)),
      );
  });
}
