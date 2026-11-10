// Tela nativa do app externo cidade.emergencia.
// Mantem o contrato AddApp/appEvent, mas evita as limitacoes de foco de iframe do CEF.

const emergencyAppId = "cidade.emergencia";
let emergencyService = "";
let emergencyBusy = false;

function updateEmergencyView(payload = {}) {
  if (app !== emergencyAppId) return;
  const status = q("#emergencyStatus");
  const send = q("#emergencySend");
  const message = q("#emergencyMessage");
  if (!status || !send || !message) return;

  status.className = "emergency-status";
  if (payload.state === "sending") {
    emergencyBusy = true;
    status.textContent = "Enviando sua localizacao...";
  } else if (payload.state === "sent") {
    emergencyBusy = false;
    status.classList.add("success");
    status.textContent = payload.message || "Chamado enviado. Aguarde no local.";
    message.value = "";
  } else if (payload.state === "error") {
    emergencyBusy = false;
    status.classList.add("error");
    status.textContent = payload.message || "Nao foi possivel enviar o chamado.";
  }
  send.disabled = !emergencyService || emergencyBusy;
}

function renderEmergencyApp() {
  content.innerHTML =
    '<div class="emergency-page">' +
    '<div class="emergency-heading"><span>ATENDIMENTO PUBLICO</span><h1>Emergencia</h1><p>Escolha o servico e descreva brevemente o que aconteceu.</p></div>' +
    '<div class="emergency-services">' +
    '<button class="emergency-service police" data-emergency-service="police" type="button"><b>190</b><span><strong>Policia</strong><small>Risco, crime ou ameaca</small></span></button>' +
    '<button class="emergency-service medical" data-emergency-service="ambulance" type="button"><b>192</b><span><strong>Medico</strong><small>Acidente ou emergencia medica</small></span></button>' +
    '</div><label for="emergencyMessage">Descricao do chamado</label>' +
    '<textarea id="emergencyMessage" maxlength="140" placeholder="Ex.: pessoa ferida em frente ao estabelecimento"></textarea>' +
    '<div class="emergency-location"><i></i><span>Sua localizacao atual sera enviada automaticamente.</span></div>' +
    '<button id="emergencySend" type="button" disabled>Enviar chamado</button>' +
    '<output id="emergencyStatus" class="emergency-status"></output></div>';

  content.querySelectorAll("[data-emergency-service]").forEach((button) => {
    button.classList.toggle("selected", button.dataset.emergencyService === emergencyService);
    button.addEventListener("click", () => {
      if (emergencyBusy) return;
      emergencyService = button.dataset.emergencyService;
      content.querySelectorAll("[data-emergency-service]").forEach((entry) =>
        entry.classList.toggle("selected", entry === button),
      );
      q("#emergencySend").disabled = false;
      const status = q("#emergencyStatus");
      status.textContent = "";
      status.className = "emergency-status";
    });
  });

  q("#emergencySend").addEventListener("click", async () => {
    if (!emergencyService || emergencyBusy) return;
    emergencyBusy = true;
    q("#emergencySend").disabled = true;
    const result = await post("externalAppEvent", {
      appId: emergencyAppId,
      event: "request",
      payload: {
        service: emergencyService,
        message: q("#emergencyMessage").value.trim(),
      },
    });
    if (!result?.ok) updateEmergencyView({ state: "error" });
  });
}

