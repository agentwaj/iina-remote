import { getConnectionQr } from "./qr";
import { startServer } from "./server";

const { menu, overlay } = iina;
const host = "localhost";
const port = 9990;
const token = Math.random().toString(36).substring(2, 15);
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

iina.event.on("iina.window-loaded", () => {
  overlay.loadFile("./overlay.html");
  const menuItem = menu.item("Toggle connection QR", toggleOverlay, {
    keyBinding: "q",
  });
  menu.addItem(menuItem);

  startServer(port, token);
});

iina.event.on("iina.plugin-overlay-loaded", () => {
  overlay.postMessage("updateConnection", {
    host,
    port,
    token,
    qr: getConnectionQr({ host, port, token }),
  });
});

iina.event.on("iina.window-did-close", () => {
  menu.removeAllItems();
});
