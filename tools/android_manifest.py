"""Raise the prebuilt Android template's minimum SDK without changing its code.

Godot's non-Gradle exporter otherwise keeps the template minimum, which can be
lower than the NDK target used by bundled extensions. Godot signs the final APK.
"""
import struct
import zipfile


def _strings(data, offset):
    _, header, _ = struct.unpack_from('<HHI', data, offset)
    count, _, flags, start, _ = struct.unpack_from('<IIIII', data, offset + 8)
    result = []
    for index in range(count):
        position = offset + start + struct.unpack_from('<I', data, offset + header + index * 4)[0]
        if flags & 0x100:
            def length(position):
                value = data[position]
                return (((value & 127) << 8) | data[position + 1], position + 2) if value & 128 else (value, position + 1)
            _, position = length(position)
            size, position = length(position)
            result.append(bytes(data[position:position + size]).decode('utf-8'))
        else:
            size = struct.unpack_from('<H', data, position)[0]
            position += 2
            if size & 0x8000:
                size = ((size & 0x7fff) << 16) | struct.unpack_from('<H', data, position)[0]
                position += 2
            result.append(bytes(data[position:position + size * 2]).decode('utf-16-le'))
    return result


def minimum_sdk(manifest, minimum):
    data = bytearray(manifest)
    if struct.unpack_from('<H', data)[0] != 3 or struct.unpack_from('<I', data, 4)[0] != len(data):
        raise ValueError('Invalid Android binary manifest')
    offset = struct.unpack_from('<H', data, 2)[0]
    pool = None
    found = 0
    while offset < len(data):
        kind, header, size = struct.unpack_from('<HHI', data, offset)
        if size < header or size == 0 or offset + size > len(data):
            raise ValueError('Invalid Android manifest chunk')
        if kind == 1:
            pool = _strings(data, offset)
        elif kind == 0x102:
            _, name, start, width, count = struct.unpack_from('<IIHHH', data, offset + 16)
            if pool is None or pool[name] != 'uses-sdk':
                offset += size
                continue
            for index in range(count):
                position = offset + 16 + start + index * width
                _, name, _ = struct.unpack_from('<III', data, position)
                if pool[name] == 'minSdkVersion':
                    if data[position + 15] != 0x10:
                        raise ValueError('Expected integer minimum SDK')
                    current = struct.unpack_from('<I', data, position + 16)[0]
                    struct.pack_into('<I', data, position + 8, 0xffffffff)
                    struct.pack_into('<I', data, position + 16, max(current, minimum))
                    found += 1
        offset += size
    if found != 1:
        raise ValueError('Expected one minimum SDK attribute')
    return bytes(data)


def align_template(path, minimum):
    temporary = path.with_suffix('.minimum-sdk.apk')
    with zipfile.ZipFile(path) as source, zipfile.ZipFile(temporary, 'w') as target:
        for entry in source.infolist():
            data = source.read(entry.filename)
            if entry.filename == 'AndroidManifest.xml':
                data = minimum_sdk(data, minimum)
            target.writestr(entry, data)
    with zipfile.ZipFile(path) as source, zipfile.ZipFile(temporary) as target:
        assert target.testzip() is None
        assert source.namelist() == target.namelist()
        assert all(source.read(name) == target.read(name) for name in source.namelist() if name != 'AndroidManifest.xml')
    temporary.replace(path)
