"""PT-BR overlay (dub + text) for the native TotK 1.0.0 runtime, merged with the port's own RomFS patches."""
import hashlib, json, math, os, shutil, struct, sys, zlib
from pathlib import Path
import argparse
import compression.zstd as zstd
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument("tree", type=Path, help="the build work tree, e.g. ~/Games/TOTK_build/totk (after one normal build)")
ap.add_argument("--dub", type=Path, required=True, help="romfs/ folder of the \"Dublagem Triforce Heroes\" mod (3.1)")
ap.add_argument("--text", type=Path, required=True, help="romfs/ folder of the \"Sem Legenda nas Falas Dubladas\" mod (Mals/USpt.Product.142.sarc.zs)")
args = ap.parse_args()
TREE = args.tree.expanduser()
OUT = TREE / "extracted/v0/romfs-patches"
ROMFS = TREE / "extracted/v0/romfs"
DUB, SL = args.dub.expanduser(), args.text.expanduser()
files = {f["path"]: f for f in json.loads((ROMFS / "index.json").read_text())["files"]}
img = open(ROMFS / "romfs.bin", "rb")
def orig(p): f = files[p]; img.seek(f["offset"]); b = img.read(f["size"]); assert len(b) == f["size"]; return b
def sarc_members(data):
    h, size, start = struct.unpack_from('<HxxII', data, 4); c = struct.unpack_from('<H', data, h + 6)[0]; n = h + 12 + c * 16 + 8; out = {}
    for i in range(c):
        _, a, lo, hi = struct.unpack_from('<4I', data, h + 12 + i * 16); o = n + (a & 0xffffff) * 4
        out[data[o:data.index(0, o, start)].decode()] = (start + lo, start + hi)
    return out
pack = zstd.decompress(orig('Pack/ZsDic.pack.zs')); dicts = {}
for name, (lo, hi) in sarc_members(pack).items(): d = zstd.ZstdDict(pack[lo:hi]); dicts[d.dict_id] = d
def dec(b):
    i = zstd.get_frame_info(b).dictionary_id
    return zstd.decompress(b, zstd_dict=dicts[i]) if i else zstd.decompress(b)
def flvi_keys(data, base):   # same walk as scripts/make_romfs_patches.py
    pos, out = base + 0x14, []
    for _ in range(struct.unpack_from('<H', data, base + 0x10)[0]):
        magic, size = data[pos:pos + 4], struct.unpack_from('<I', data, pos + 4)[0]
        if magic == b'pai1':
            count, table = struct.unpack_from('<H', data, pos + 14)[0], pos + struct.unpack_from('<I', data, pos + 16)[0]
            for e in range(count):
                eo = pos + struct.unpack_from('<I', data, table + 4 * e)[0]
                name = data[eo:eo + 28].split(b'\0')[0].decode()
                for t in range(data[eo + 28]):
                    to = eo + struct.unpack_from('<I', data, eo + 32 + 4 * t)[0]
                    if data[to:to + 4] != b'FLVI': continue
                    for g in range(data[to + 4]):
                        go = to + struct.unpack_from('<I', data, to + 8 + 4 * g)[0]
                        ko = go + struct.unpack_from('<I', data, go + 8)[0]
                        keys = [struct.unpack_from('<fH', data, ko + 8 * k) for k in range(struct.unpack_from('<H', data, go + 4)[0])]
                        out.append((name, ko, keys))
        pos += size
    return out

overlay = {}   # RomFS path -> bytes, or Path to copy
# 1. UI: the mod's 1.1.0 archives differ from 1.0.0 only in timg/__Combined.bntx (checked); Common also gets the port's capture fix.
COMMON = 'UI/LayoutArchive/Common.Product.100.Nin_NX_NVN.blarc.zs'
raw = orig(COMMON); base = dec(raw); blarc = bytearray(dec((DUB / 'UI/LayoutArchive/Common.Product.110.Nin_NX_NVN.blarc.zs').read_bytes()))
mb, mm = sarc_members(base), sarc_members(blarc)
assert mb.keys() == mm.keys() and [k for k in mb if base[slice(*mb[k])] != blarc[slice(*mm[k])]] == ['timg/__Combined.bntx']
for member, panes in {'anim/ShortCutBG_00_In.bflan': ('C_CaptureBG_00', 'C_CaptureClearBG_00', 'P_CaptureClearBG_00'), 'anim/AutoBuilder_00_In.bflan': ('C_CaptureBG_00',)}.items():
    changed = []
    for name, ko, keys in flvi_keys(blarc, mm[member][0]):
        if name in panes: assert keys == [(0.0, 0), (1.0, 1)]; struct.pack_into('<f', blarc, ko + 8, 0.0); changed.append(name)
    assert sorted(changed) == sorted(panes)
d = dicts[zstd.get_frame_info(raw).dictionary_id]; overlay[COMMON] = zstd.compress(bytes(blarc), level=19, zstd_dict=d)
TITLE = 'UI/LayoutArchive/Title.Product.100.Nin_NX_NVN.blarc.zs'
t_mod = (DUB / 'UI/LayoutArchive/Title.Product.110.Nin_NX_NVN.blarc.zs').read_bytes(); t_b, t_m = dec(orig(TITLE)), dec(t_mod)
a, b = sarc_members(t_b), sarc_members(t_m); assert a.keys() == b.keys() and [k for k in a if t_b[slice(*a[k])] != t_m[slice(*b[k])]] == ['timg/__Combined.bntx']
overlay[TITLE] = t_mod
# 2. The port's game-over fix, unchanged.
overlay['Event/EventFlow/DmF_SY_GameOver.bfevfl.zs'] = (TREE / 'extracted/v0/romfs-patches/Event/EventFlow/DmF_SY_GameOver.bfevfl.zs').read_bytes()
# 3. Text: "Sem Legenda nas Falas Dubladas" USpt (PT-BR, no subtitles on dubbed lines) in the USen slot (; the game runs with TOTK_LANG=en-US).
overlay['Mals/USen.Product.100.sarc.zs'] = (SL / 'Mals/USpt.Product.142.sarc.zs').read_bytes()
# 4. Voices, sounds, textures at the same paths.
for p in DUB.rglob('*'):
    if not p.is_file() or p.name.startswith('._'): continue
    rel = str(p.relative_to(DUB))
    if rel.startswith(('Mals/', 'UI/LayoutArchive/', 'System/Resource/')): continue
    assert rel in files, rel
    if p.stat().st_size == files[rel]['size'] and p.read_bytes() == orig(rel): continue
    overlay[rel] = p
# 5. Resource size table: 1.0.0 values raised to what the new files need.
RSTB = 'System/Resource/ResourceSizeTable.Product.100.rsizetable.zs'
def parse(b):
    ver, sl, nc, nn = struct.unpack_from('<4I', b, 6); o = 22; crc = {}
    for _ in range(nc): h, s = struct.unpack_from('<II', b, o); crc[h] = (o + 4, s); o += 8
    return crc
tbl = bytearray(zstd.decompress(orig(RSTB))); crc = parse(tbl)
mod_crc = {h: s for h, (_, s) in parse(zstd.decompress((DUB / 'System/Resource/ResourceSizeTable.Product.121.rsizetable.zs').read_bytes())).items()}
alias = {'Mals/USen.Product.100.sarc': 'Mals/USen.Product.121.sarc', 'UI/LayoutArchive/Common.Product.100.Nin_NX_NVN.blarc': 'UI/LayoutArchive/Common.Product.110.Nin_NX_NVN.blarc', 'UI/LayoutArchive/Title.Product.100.Nin_NX_NVN.blarc': 'UI/LayoutArchive/Title.Product.110.Nin_NX_NVN.blarc'}
raised = {}
for path, src in overlay.items():
    key = path[:-3] if path.endswith('.zs') else path; h = zlib.crc32(key.encode())
    if h not in crc: continue
    off, old = crc[h]; new_bytes = src if isinstance(src, bytes) else src.read_bytes()
    if path.endswith('.zs'):
        ratio = old / len(dec(orig(path))); need = math.ceil(len(dec(new_bytes)) * ratio / 0x100) * 0x100
    else: need = old + max(0, len(new_bytes) - files[path]['size'])
    need = max(need, mod_crc.get(zlib.crc32(alias.get(key, key).encode()), 0))
    if need > old: struct.pack_into('<I', tbl, off, need); raised[key] = (old, need)
overlay[RSTB] = zstd.compress(bytes(tbl), level=19)
# 6. Write the folder and its manifest.
tmp = OUT.with_name('romfs-patches.ptbr-tmp'); shutil.rmtree(tmp, ignore_errors=True); lines = []
for path in sorted(overlay):
    src = overlay[path]; data = src if isinstance(src, bytes) else src.read_bytes()
    t = tmp / path; t.parent.mkdir(parents=True, exist_ok=True); t.write_bytes(data)
    lines.append('\t'.join([path, str(len(data)), hashlib.sha256(data).hexdigest(), hashlib.sha256(orig(path)).hexdigest()]))
(tmp / 'manifest.tsv').write_text('# path\tsize\tsha256\toriginal_sha256 (port patches + PT-BR dub/text overlay)\n' + '\n'.join(lines) + '\n')
shutil.rmtree(OUT); tmp.rename(OUT)
print(json.dumps(dict(files=len(overlay), mb=round(sum(int(l.split('\t')[1]) for l in lines) / 2**20), rstb_raised=raised), indent=1))
