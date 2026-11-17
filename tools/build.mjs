// Builds what ships, with no dependencies beyond Node (so Vercel can run it too):
//
//   node tools/build.mjs site    site/ext (the demo's copy of the extension) and site/intercede.zip
//   node tools/build.mjs store   dist/intercede-<version>.zip for the Chrome Web Store
//
// Both zips leave out dev/ and test/. The store zip also drops the manifest's "key", which pins the
// extension ID for unpacked installs and which the Web Store rejects.
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { deflateRawSync } from 'node:zlib';

const root = new URL('..', import.meta.url).pathname;
const ext = join(root, 'Extension');
const SKIP = new Set(['dev', 'test', '.DS_Store']);

function files(dir) {
  return readdirSync(dir).filter(name => !SKIP.has(name)).sort().flatMap(name => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : [path];
  });
}

// ── A minimal zip writer (deflate, no extras) ──

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function zip(entries) {  // [{ name, data }]
  const locals = [], centrals = [];
  let offset = 0;
  for (const { name, data } of entries) {
    const nameBuf = Buffer.from(name), packed = deflateRawSync(data), crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(8, 8);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(packed.length, 18); local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(8, 10); central.writeUInt32LE(crc, 16); central.writeUInt32LE(packed.length, 20);
    central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBuf.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local, nameBuf, packed);
    centrals.push(central, nameBuf);
    offset += 30 + nameBuf.length + packed.length;
  }
  const dir = Buffer.concat(centrals), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(dir.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, dir, end]);
}

function extensionZip({ store }) {
  return zip(files(ext).map(path => {
    const name = relative(ext, path);
    let data = readFileSync(path);
    if (store && name === 'manifest.json') {
      const manifest = JSON.parse(data);
      delete manifest.key;
      data = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
    }
    return { name, data };
  }));
}

// ── Targets ──

const target = process.argv[2];
if (target === 'site') {
  const site = join(root, 'site');
  rmSync(join(site, 'ext'), { recursive: true, force: true });
  mkdirSync(join(site, 'ext'));
  for (const f of ['dissolve.js', 'patron.js', 'patrons.js']) cpSync(join(ext, 'src', f), join(site, 'ext', f));
  cpSync(join(ext, 'patrons'), join(site, 'ext', 'patrons'), { recursive: true });
  for (const size of [32, 128]) cpSync(join(ext, 'icons', `icon-${size}.png`), join(site, 'ext', `icon-${size}.png`));
  writeFileSync(join(site, 'intercede.zip'), extensionZip({ store: false }));
  console.log('built site/ext and site/intercede.zip');
} else if (target === 'store') {
  const { version } = JSON.parse(readFileSync(join(ext, 'manifest.json')));
  mkdirSync(join(root, 'dist'), { recursive: true });
  const out = join(root, 'dist', `intercede-${version}.zip`);
  writeFileSync(out, extensionZip({ store: true }));
  console.log('built', relative(root, out));
} else {
  console.error('usage: node tools/build.mjs site|store');
  process.exit(1);
}
