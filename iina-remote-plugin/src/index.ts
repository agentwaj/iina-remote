import { getLocalIPv4, getConnectionQr } from "./utils";
import { startServer } from "./server";

const { menu, overlay, core } = iina;
const keyBinding = "q";
const token = Math.random().toString(36).substring(2, 15);
let host = "";
let port = 0;
let isOverlayVisible = false;

const toggleOverlay = () => {
  if (isOverlayVisible) {
    overlay.hide();
    isOverlayVisible = false;
  } else {
    overlay.show();
    isOverlayVisible = true;
  }
};

iina.event.on("iina.window-loaded", async () => {
  host = await getLocalIPv4();
  startServer(token, (successPort) => {
    port = successPort;
    overlay.loadFile("./overlay.html");
  });
});

iina.event.on("iina.plugin-overlay-loaded", () => {
  overlay.postMessage("updateConnection", {
    host,
    port,
    token,
    qr: getConnectionQr({ host, port, token }),
  });
  overlay.postMessage("updateTitle", { title: core.status.title });

  const menuItem = menu.item("Toggle connection QR", toggleOverlay, {
    keyBinding,
  });
  menu.addItem(menuItem);

  iina.input.onKeyDown(keyBinding, () => {
    toggleOverlay();
    return true;
  });
});

iina.event.on("iina.window-did-close", () => {
  menu.removeAllItems();
});
