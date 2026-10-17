const fs = require('fs');
const path = require('path');

const [root, cfgFile, mode] = process.argv.slice(2);
const apply = mode === 'apply';
const MAX_TINT = 0.1;
const MAX_PHONG = 10;
const MIN_EFFECTIVE = 20;

const cfg = fs.readFileSync(cfgFile, 'utf8');
const ids = {};
for (const m of cfg.matchAll(/"([a-z0-9-]+)"[^\n]*\n\s*\{\s*\n\s*"weapon"[^\n]*\n[^\n]*\n\s*"materials"\s*"materials\/models\/l4d2br\/weapons\/([^"]+)"/g)) ids[m[2]] = m[1];

function meanAlpha(file) {
  const b = fs.readFileSync(file);
  const fmt = b.readInt32LE(52);
  if (fmt === 13 || fmt === 2 || fmt === 3) return 255;
  if (fmt !== 15 && fmt !== 14) return 255;
  const w = b.readUInt16LE(16), h = b.readUInt16LE(18), mips = b[56], header = b.readUInt32LE(12);
  const lowFmt = b.readInt32LE(57), lw = b[61], lh = b[62];
  const low = lowFmt === 13 ? Math.max(1, Math.ceil(lw / 4)) * Math.max(1, Math.ceil(lh / 4)) * 8 : 0;
  let size = 0;
  for (let m = 1; m < mips; m++) size += Math.ceil(Math.max(1, w >> m) / 4) * Math.ceil(Math.max(1, h >> m) / 4) * 16;
  let p = header + low + size, sum = 0, n = 0;
  for (let i = 0; i < (w / 4) * (h / 4); i++, p += 16) {
    if (fmt === 15) sum += (b[p] + b[p + 1]) / 2;
    else { let s = 0; for (let k = 0; k < 8; k++) s += ((b[p + k] & 15) + (b[p + k] >> 4)) * 17 / 2; sum += s / 8; }
    n++;
  }
  return sum / n;
}

const live = (line) => !line.trim().startsWith('//');
const changedSkins = new Set();

for (const folder of fs.readdirSync(root).sort()) {
  const dir = path.join(root, folder);
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.vmt'))) {
    const file = path.join(dir, f);
    const original = fs.readFileSync(file, 'utf8');
    const eol = original.includes('\r\n') ? '\r\n' : '\n';
    const lines = original.split(/\r?\n/);
    const base = (lines.filter(live).join('\n').match(/\$basetexture\s+"([^"]+)"/i) || [])[1];
    if (!base || !base.toLowerCase().startsWith('models/l4d2br/')) continue;
    const skinId = ids[folder] || "";
    if (skinId.startsWith("holographic-") || skinId === "puro-machete") continue;

    const notes = [];
    const envIndex = lines.findIndex(l => live(l) && /^\s*\$envmap\s/i.test(l));
    if (envIndex !== -1) {
      const tintIndex = lines.findIndex(l => live(l) && /^\s*\$envmaptint\s/i.test(l));
      if (tintIndex === -1) {
        lines.splice(envIndex + 1, 0, `$envmaptint "[${MAX_TINT} ${MAX_TINT} ${MAX_TINT}]"`);
        notes.push(`reflexo 100% -> ${MAX_TINT * 100}%`);
      } else {
        const values = (lines[tintIndex].match(/\[([^\]]+)\]/) || [])[1];
        const nums = values ? values.trim().split(/\s+/).map(Number) : [1, 1, 1];
        const max = Math.max(...nums);
        if (max > 0.2) {
          const scaled = nums.map(v => +(v * MAX_TINT / max).toFixed(3));
          lines[tintIndex] = `$envmaptint "[${scaled.join(' ')}]"`;
          notes.push(`reflexo [${nums.join(' ')}] -> [${scaled.join(' ')}]`);
        }
      }
    }

    const text = lines.filter(live).join('\n');
    const phongIndex = lines.findIndex(l => live(l) && /^\s*\$phongboost\s/i.test(l));
    if (phongIndex !== -1 && /\$phong\s+"?1/i.test(text)) {
      const boost = Number((lines[phongIndex].match(/([0-9.]+)\s*"?\s*$/) || [])[1] || 0);
      const masked = /\$basemapalphaphongmask\s+"?1/i.test(text);
      let alpha = 255;
      if (masked) {
        const vtf = path.join(root, '..', '..', '..', '..', 'materials', base.split(String.fromCharCode(92)).join('/') + '.vtf');
        if (fs.existsSync(vtf)) alpha = meanAlpha(vtf);
      }
      const effective = masked ? boost * alpha / 255 : boost;
      if (boost > MAX_PHONG && effective >= MIN_EFFECTIVE) {
        lines[phongIndex] = `$phongboost ${MAX_PHONG}`;
        notes.push(`brilho ${boost} -> ${MAX_PHONG}`);
      }
    }

    if (notes.length === 0) continue;
    const skin = ids[folder] || folder;
    changedSkins.add(skin);
    console.log(`${skin} | ${folder}/${f} | ${notes.join(', ')}`);
    if (apply) fs.writeFileSync(file, lines.join(eol), 'utf8');
  }
}

console.log(`SKINS ${[...changedSkins].sort().join(',')}`);
console.log(`TOTAL ${changedSkins.size}`);
