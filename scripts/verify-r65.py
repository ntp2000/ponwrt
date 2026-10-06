#!/usr/bin/env python3
"""Verify native r65 sources and all four actual HG5585F FIT images.

Usage: python3 scripts/verify-r65.py /absolute/new/output-directory /absolute/r65-reference.json
Supply the frozen reference from the separately delivered validation data.
It contains hashes read from the original r65 tree.
This does not modify build outputs, access a router, or perform a flash.
"""
from pathlib import Path
import gzip
import hashlib
import json
import re
import struct
import subprocess
import sys
import zlib

root = Path(__file__).resolve().parents[1]
if len(sys.argv) != 3:
    raise SystemExit(__doc__)
reference = json.loads(Path(sys.argv[2]).resolve().read_text())
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=False)
build = root/'build_dir/target-aarch64_cortex-a53_musl'
base = build/'linux-airoha_an7581'
sources = {
    'firmware': build/'airoha-clanker-npu-735529c10d5120e10f7e4a6ddf97fb384fce9903',
    'mt76': base/'mt76-2026.09.01~be5ce791',
    'mac80211': base/'mac80211-regular/backports-7.2',
    'kernel': base/'linux-6.18.52',
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def allocated_sections(path):
    """Fingerprint ELF64 code/data/layout, excluding non-loaded debug metadata."""
    blob = path.read_bytes()
    assert blob[:6] == b'\x7fELF\x02\x01'
    offset = struct.unpack_from('<Q', blob, 40)[0]
    size, count, string_index = struct.unpack_from('<3H', blob, 58)
    headers = [struct.unpack_from('<IIQQQQIIQQ', blob, offset+i*size) for i in range(count)]
    strings = headers[string_index]
    names = blob[strings[4]:strings[4]+strings[5]]
    result = {}
    for header in headers:
        if not header[2] & 2:  # SHF_ALLOC
            continue
        name = names[header[0]:names.index(b'\0', header[0])].decode()
        data = b'' if header[1] == 8 else blob[header[4]:header[4]+header[5]]
        result[name] = {'type': header[1], 'flags': header[2], 'bytes': header[5],
                        'alignment': header[8], 'sha256': digest(data)}
    return result

source_checks = {}
for group, files in reference['sources'].items():
    for name, expected in files.items():
        key = group+'/'+name
        source_checks[key] = digest((sources[group]/name).read_bytes()) == expected
for name, expected in reference['native_inputs'].items():
    source_checks[name] = digest((root/name).read_bytes()) == expected
(out/'sources.json').write_text(json.dumps(source_checks, indent=2)+'\n')
assert all(source_checks.values()), [k for k, v in source_checks.items() if not v]
for name, expected in reference['reference_airoha_sections'].items():
    assert allocated_sections(sources['kernel']/name) == expected, ('Airoha code/data mismatch', name)

def properties(blob):
    magic, total, off, strings = struct.unpack_from('>4I', blob)
    assert magic == 0xd00dfeed and total <= len(blob)
    stack = []
    while off+4 <= total:
        token = struct.unpack_from('>I', blob, off)[0]
        off += 4
        if token == 1:
            end = blob.index(b'\0', off)
            stack.append(blob[off:end].decode())
            off = (end+4) & ~3
        elif token == 2:
            stack.pop()
        elif token == 3:
            size, name = struct.unpack_from('>2I', blob, off)
            off += 8
            assert off+size <= total
            name = blob[strings+name:blob.index(b'\0', strings+name)].decode()
            yield '/'+('/'.join(x for x in stack if x)), name, blob[off:off+size]
            off = (off+size+3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            return
        else:
            raise ValueError(token)
    raise ValueError('unterminated FDT')

def payload(blob, fields):
    if 'data' in fields:
        return fields['data']
    length = int.from_bytes(fields['data-size'], 'big')
    if 'data-position' in fields:
        pos = int.from_bytes(fields['data-position'], 'big')
    else:
        total = struct.unpack_from('>I', blob, 4)[0]
        pos = ((total+3) & ~3) + int.from_bytes(fields['data-offset'], 'big')
    assert pos+length <= len(blob)
    return blob[pos:pos+length]

def cpio_files(blob):
    off = 0
    while True:
        assert blob[off:off+6] == b'070701'
        fields = [int(blob[off+6+i*8:off+14+i*8], 16) for i in range(13)]
        length, size = fields[11], fields[6]
        name = blob[off+110:off+110+length-1].decode()
        off = (off+110+length+3) & ~3
        if name == 'TRAILER!!!':
            return
        assert off+size <= len(blob)
        yield name, blob[off:off+size]
        off = (off+size+3) & ~3

firmware = sources['firmware']/'build/AN7581_MT7916'
for name, expected in reference['npu_binaries'].items():
    data = (firmware/name.removeprefix('en7581_MT7916_')).read_bytes()
    assert digest(data) == expected['sha256'] and len(data) == expected['bytes'], name

modules = {
    'mt76.ko': sources['mt76']/'ipkg-aarch64_cortex-a53/kmod-mt76-core',
    'mt7915e.ko': sources['mt76']/'ipkg-aarch64_cortex-a53/kmod-mt7915e',
    'mac80211.ko': sources['mac80211']/'ipkg-aarch64_cortex-a53/kmod-mac80211',
    'nf_flow_table.ko': base/'packages/ipkg-aarch64_cortex-a53/kmod-nf-flow',
}
unsquashfs = root/'staging_dir/host/bin/unsquashfs4'
rows = []
for board in ('cu', 'ct'):
    for kind in ('recovery', 'sysupgrade'):
        path = root/f'bin/targets/airoha/an7581/ponwrt-airoha-an7581-fiberhome_hg5585f-{board}-squashfs-{kind}.itb'
        blob = path.read_bytes()
        props = {}
        for node, key, value in properties(blob):
            props.setdefault(node, {})[key] = value
        for node, fields in props.items():
            if node.startswith('/images/') and '/hash' in node:
                algorithm = fields['algo'].rstrip(b'\0').decode()
                assert algorithm in ('crc32', 'sha1', 'sha256'), algorithm
                data = payload(blob, props[node.rsplit('/', 1)[0]])
                actual = (zlib.crc32(data).to_bytes(4, 'big') if algorithm == 'crc32'
                          else hashlib.new(algorithm, data).digest())
                assert actual == fields['value'], node
        assert props['/images/kernel-1']['compression'] == b'gzip\0'
        assert gzip.decompress(payload(blob, props['/images/kernel-1'])) == (base/'Image').read_bytes()
        assert digest(payload(blob, props['/images/fdt-1'])) == reference['reference_dtbs'][board+'-'+kind]
        if kind == 'recovery':
            entries = dict(cpio_files(payload(blob, props['/images/initrd-1'])))
            sqdata = entries['root.squashfs']
            assert entries['init'] == (root/'target/linux/airoha/image/hg5585f-ramboot-init').read_bytes()
            for name, expected in reference['npu_binaries'].items():
                assert digest(entries['lib/firmware/airoha/'+name]) == expected['sha256']
        else:
            sqdata = payload(blob, props['/images/rootfs-1'])
        assert sqdata[:4] == b'hsqs'
        sq = out/f'{board}-{kind}.squashfs'
        sq.write_bytes(sqdata)
        def cat(name):
            return subprocess.check_output([str(unsquashfs), '-cat', str(sq), name])
        for name, expected in reference['npu_binaries'].items():
            assert digest(cat('lib/firmware/airoha/'+name)) == expected['sha256'], name
        for name, expected in reference['installed_files'].items():
            assert digest(cat(name)) == expected, (board, kind, name)
        module_hashes = {}
        for name, directory in modules.items():
            data = cat('lib/modules/6.18.52/'+name)
            assert data == (directory/'lib/modules/6.18.52'/name).read_bytes(), name
            assert digest(data) == reference['reference_modules'][name], ('r65 module mismatch', name)
            module_hashes[name] = {'sha256': digest(data), 'reference_binary_identical': digest(data) == reference['reference_modules'][name]}
        assert b'Kite datapath r65 ABI12 bound:' in cat('lib/modules/6.18.52/mt7915e.ko')
        info = cat('lib/firmware/airoha/en7581_MT7916_ClankerNPU_BUILDINFO.txt').decode()
        assert 'Release65: 145/179/983' in info and 'mt76 patches 120-179/release51' in info
        listing = subprocess.check_output([str(unsquashfs), '-ll', str(sq)], text=True)
        assert not re.search(r'/(?:[^/\s]*[.-])?(?:passwall2?|rathole|x?frp[cs]?)(?:[./\s-]|$)', listing)
        rows.append({'board': board, 'kind': kind, 'image': path.name, 'sha256': digest(blob),
                     'bytes': len(blob), 'npu_identical_to_r65': True, 'dtb_identical_to_r65': True,
                     'installed_files_identical_to_r65': len(reference['installed_files']),
                     'modules': module_hashes, 'fit_hashes_valid': True})
        print('PASS', path.name, flush=True)

(out/'images.json').write_text(json.dumps(rows, indent=2)+'\n')
config = (root/'.config').read_text()
selected = re.findall(r'^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_(.+)=y$', config, re.M)
assert set(selected) == {'fiberhome_hg5585f-cu', 'fiberhome_hg5585f-ct'}
assert not re.search(r'^CONFIG_PACKAGE_[^\n=]*(?:passwall|rathole|frp)[^\n=]*=[ym]$', config, re.M)
assert (root/'feeds.conf').read_bytes() == (root/'feeds.conf.default').read_bytes()
feed_lines = [line.split() for line in (root/'feeds.conf.default').read_text().splitlines()
              if line.strip() and not line.startswith('#')]
assert len(feed_lines) == 11
for method, name, url in feed_lines:
    assert method == 'src-git' and re.search(r'\^[0-9a-f]{40}$', url)
    assert not re.search(r'passwall|rathole|frp', name+' '+url, re.I)
assert not (root/'package/feeds/packages/frp').exists()
manifests = sorted((root/'bin/targets/airoha/an7581').glob('ponwrt-*.manifest'))
assert manifests, 'Native package manifest missing'
for manifest in manifests:
    names = [line.split()[0] for line in manifest.read_text().splitlines() if line.strip()]
    assert not any(re.search(r'passwall|rathole|frp', name, re.I) for name in names), manifest.name
print(f'PASS {len(source_checks)} native/source checks; r65 NPU bytes and 4 actual FIT images')
