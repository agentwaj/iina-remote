import encodeQr from "qr";

export const getLocalIPv4 = async () => {
  const route = await iina.utils.exec("/sbin/route", ["-n", "get", "default"]);
  const iface = route.stdout.match(/interface:\s+(\S+)/)?.[1]?.trim() ?? "en0";
  const ip = await iina.utils.exec("/usr/sbin/ipconfig", ["getifaddr", iface]);
  return ip.stdout.trim();
};

export const getConnectionQr = ({
  host,
  port,
  token,
}: {
  host: string;
  port: number;
  token: string;
}) => {
  const connectionData = JSON.stringify({ host, port, token });

  return encodeQr(connectionData, "svg", { textEncoder });
};

const textEncoder = (str: string) => {
  const out = [];
  let i = 0;

  while (i < str.length) {
    let c = str.charCodeAt(i++);

    if (c >= 0xd800 && c <= 0xdbff && i < str.length) {
      const c2 = str.charCodeAt(i);
      if (c2 >= 0xdc00 && c2 <= 0xdfff) {
        i++;
        c = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
      }
    }

    if (c <= 0x7f) out.push(c);
    else if (c <= 0x7ff) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    else if (c <= 0xffff)
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    else
      out.push(
        0xf0 | (c >> 18),
        0x80 | ((c >> 12) & 0x3f),
        0x80 | ((c >> 6) & 0x3f),
        0x80 | (c & 0x3f),
      );
  }

  return new Uint8Array(out);
};
