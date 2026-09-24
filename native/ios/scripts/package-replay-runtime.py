"""Copy only imported toolchain DLLs for the x64 replay CLI, not the compiler."""
from pathlib import Path
import json
import shutil
import struct
import sys

executable = Path(sys.argv[1])
destination = Path(sys.argv[2])
search = [Path(p) for p in json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))]
libraries = {}
for directory in search:
    if directory.is_dir():
        for path in directory.glob("*.dll"):
            libraries.setdefault(path.name.lower(), path)

def imports(path):
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    assert data[pe:pe+4] == b"PE\0\0"
    sections, optional_size = struct.unpack_from("<H", data, pe+6)[0], struct.unpack_from("<H", data, pe+20)[0]
    optional = pe + 24
    assert struct.unpack_from("<H", data, optional)[0] == 0x20b, "x64 PE32+ required"
    table = optional + optional_size
    def offset(rva):
        for i in range(sections):
            at = table + i*40
            size, address, raw_size, raw = struct.unpack_from("<IIII", data, at+8)
            if address <= rva < address + max(size, raw_size):
                return raw + rva - address
        raise ValueError("Unmapped PE RVA")
    def string(rva):
        start = offset(rva)
        return data[start:data.index(0, start)].decode("ascii")
    result = []
    for directory_index, row_size, name_offset in [(1, 20, 12), (13, 32, 4)]:
        rva, size = struct.unpack_from("<II", data, optional+112+directory_index*8)
        if not rva or not size:
            continue
        start = offset(rva)
        for at in range(start, start+size-row_size+1, row_size):
            if not any(data[at:at+row_size]):
                break
            result.append(string(struct.unpack_from("<I", data, at+name_offset)[0]))
    return result

destination.mkdir(parents=True, exist_ok=True)
queue = [executable]
seen = set()
while queue:
    path = queue.pop()
    if path.name.lower() in seen:
        continue
    seen.add(path.name.lower())
    shutil.copyfile(path, destination / path.name)
    for name in imports(path):
        dependency = libraries.get(name.lower())
        if dependency:
            queue.append(dependency)
print(json.dumps({"bundledFiles": sorted(seen), "bytes": sum(p.stat().st_size for p in destination.iterdir())}))
