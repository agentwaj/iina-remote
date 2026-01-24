const { console, menu, overlay } = iina;

console.log("IINA Remote loaded");

let isMenuItemVisible = false;

const toggleOverlay = () => {
  if (isMenuItemVisible) {
    overlay.hide();
    isMenuItemVisible = false;
    return;
  }

  overlay.simpleMode();
  overlay.setStyle(`.title { position: fixed; bottom: 0px; right: 20px; }`);
  overlay.setContent(`<h1 class="title">IINA Remote</h1>`);
  overlay.show();

  isMenuItemVisible = true;
};

const menuItem = menu.item("Toggle connection QR", toggleOverlay, {
  keyBinding: "q",
});

iina.event.on("iina.window-loaded", () => {
  menu.addItem(menuItem);
});

iina.event.on("iina.window-did-close", () => {
  menu.removeAllItems();
});
