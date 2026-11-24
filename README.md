<div align="center">
  <img width="256" height="256" alt="logo" src="https://github.com/user-attachments/assets/1dab8750-af37-4d21-916d-d4170c8f817d" />
</div>




<h1 align="center">IINA Remote</h1>

Remote control for [IINA](https://github.com/iina/iina). There is a WebSocket server that runs over LAN as an [IINA plugin](https://iina.io/plugins/), and an accompanying iOS app that connects via QR code.

## Usage

1. Install the plugin in IINA
2. Press `q` to toggle the connection QR code
3. Scan QR code from app while connected to the same wifi network

<img width="1024" height="512" alt="demo" src="https://github.com/user-attachments/assets/0a7afd18-9f01-41c2-b975-6c5e02720abc" />

## Development

For the plugin:

```bash
cd iina-remote-plugin
npm install
npm run build
npm run link
```

Run the plugin tests with `npm test`. They use a fake IINA, so IINA doesn't need to be running.

For the iOS app, open `iina-remote-app` in Xcode and run.
