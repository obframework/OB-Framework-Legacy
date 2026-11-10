const text = document.querySelector("#text");
const status = document.querySelector("#status");

document.querySelector("#save").addEventListener("click", () => {
  window.parent.postMessage(
    {
      type: "ob-phone:event",
      event: "save",
      payload: { text: text.value },
    },
    "*",
  );
});

window.addEventListener("message", (event) => {
  const message = event.data;

  if (message?.type === "ob-phone:ready") {
    document.documentElement.dataset.theme = message.theme;
  }

  if (message?.type === "ob-phone:message" && message.payload?.saved) {
    status.textContent = `Salvo: ${message.payload.text}`;
  }
});
