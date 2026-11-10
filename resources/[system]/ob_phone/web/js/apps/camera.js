// Captura, upload e controles do aplicativo Câmera.

async function uploadMedia(blob, mediaType, variantForMediaId = 0) {
  const request = await post("mediaRequestUpload", { mediaType });
  if (!request.ok)
    throw new Error(request.message || "Não foi possível iniciar o envio.");
  const info = request.data,
    form = new FormData(),
    extension = mediaType === "photo" ? ".jpg" : ".webm";
  form.append("file", blob, "ob-phone-" + Date.now() + extension);
  const controller = new AbortController(),
    timeout = setTimeout(
      () => controller.abort(),
      Number(info.uploadTimeoutMs) || 25000,
    );
  try {
    const response = await fetch(info.presignedUrl, {
        method: "POST",
        body: form,
        signal: controller.signal,
      }),
      payload = await response.json(),
      file = payload.data || payload;
    if (!response.ok || !file.id || !file.url)
      throw new Error(payload.message || "Falha no envio.");
    const saved = await post("mediaCompleteUpload", {
      requestId: info.requestId,
      remoteId: file.id,
      url: file.url,
      mediaType,
      variantForMediaId,
    });
    if (!saved.ok)
      throw new Error(saved.message || "Não foi possível salvar a mídia.");
    return saved.data;
  } finally {
    clearTimeout(timeout);
  }
}
function camera() {
  clearInterval(cameraRecordingTimer);
  cameraRecordingStarted = 0;
  cameraLandscape = false;
  cameraFront = false;
  content.innerHTML =
    '<div class="camera-shell"><canvas id="cameraView"></canvas><div class="camera-tools"><button data-do="flipCamera" aria-label="Virar câmera">↻</button><span id="cameraStatus"></span><button data-do="rotateCamera" aria-label="Girar câmera">▭</button></div><div class="camera-modes"><button class="selected" data-camera-mode="photo">FOTO</button><button data-camera-mode="video">VÍDEO</button></div><button class="shutter" data-do="capture"><i></i></button></div>';
  requestAnimationFrame(async () => {
    try {
      await post("cameraActive", { active: true });
      await window.OBMediaCapture.start(q("#cameraView"), {
        landscape: false,
        front: false,
      });
      inputFocusMode = "game";
      await post("inputFocus", { mode: "game" });
      const status = q("#cameraStatus");
      if (status) status.textContent = "";
    } catch (error) {
      toast("A captura da câmera não está disponível.", "error");
      const status = q("#cameraStatus");
      if (status) status.textContent = error?.message || "Câmera indisponível";
    }
  });
}
function updateCameraRecordingTime() {
  const status = q("#cameraStatus");
  if (!status || !cameraRecordingStarted) return;
  const seconds = Math.max(
    0,
    Math.floor((Date.now() - cameraRecordingStarted) / 1000),
  );
  status.textContent =
    "● " +
    String(Math.floor(seconds / 60)).padStart(2, "0") +
    ":" +
    String(seconds % 60).padStart(2, "0");
}
function resumeCameraGameInput() {
  setTimeout(() => {
    if (opened && app === "camera") {
      inputFocusMode = "game";
      post("inputFocus", { mode: "game" });
    }
  }, 60);
}
async function capture() {
  const status = q("#cameraStatus"),
    captureApi = window.OBMediaCapture;
  if (!captureApi)
    return toast(
      "Módulo da câmera não carregado. Execute refresh e restart ob_phone.",
      "error",
    );
  if (cameraCaptureBusy) return;
  cameraCaptureBusy = true;
  resumeCameraGameInput();
  try {
    if (cameraMode === "photo") {
      status.textContent = "Enviando foto…";
      const blob = await captureApi.photo();
      await uploadMedia(blob, "photo");
      status.textContent = "Foto salva";
    } else if (!captureApi.recording()) {
      status.textContent = "Iniciando gravação…";
      await captureApi.startVideo();
      cameraRecordingStarted = Date.now();
      status.classList.add("recording");
      updateCameraRecordingTime();
      clearInterval(cameraRecordingTimer);
      cameraRecordingTimer = setInterval(updateCameraRecordingTime, 250);
      q(".shutter")?.classList.add("recording");
      cameraVideoTimer = setTimeout(() => capture(), 30000);
    } else {
      clearTimeout(cameraVideoTimer);
      clearInterval(cameraRecordingTimer);
      cameraRecordingStarted = 0;
      status.classList.remove("recording");
      status.textContent = "Enviando vídeo…";
      const recording = await captureApi.stopVideo();
      await uploadMedia(recording.blob, "video");
      status.textContent = "Vídeo salvo";
      q(".shutter")?.classList.remove("recording");
    }
  } catch (error) {
    clearInterval(cameraRecordingTimer);
    cameraRecordingStarted = 0;
    status.classList.remove("recording");
    status.textContent = "Não foi possível salvar";
    q(".shutter")?.classList.remove("recording");
    const message =
      error?.message === "microphone_permission_required"
        ? "Não foi possível ativar o áudio automático da gravação."
        : error?.message === "microphone_unavailable"
          ? "Áudio indisponível para a gravação."
          : error?.message;
    toast(message || "Falha na câmera.", "error");
  } finally {
    cameraCaptureBusy = false;
  }
}
