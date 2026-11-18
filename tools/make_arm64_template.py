#!/usr/bin/env python3
"""Make an Apple Silicon-only macOS export template from Godot's universal one.

Godot's official macos.zip only contains universal (x86_64 + arm64) binaries,
but exporting with architecture "arm64" asks for godot_macos_*.arm64. This
script copies the template and replaces each universal binary with just its
arm64 slice (a plain Mach-O file cut out of the fat binary - no Apple tools
needed), so the exported app is roughly half the size.

    python3 tools/make_arm64_template.py <path/to/macos.zip> build/templates/macos_arm64.zip

Standard library only; runs on Linux CI.
"""
import struct
import sys
import zipfile

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
CPU_TYPE_ARM64 = 0x0100000C


def arm64_slice(data: bytes) -> bytes:
    magic, nfat = struct.unpack(">II", data[:8])
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        raise ValueError("not a universal (fat) Mach-O binary")
    is64 = magic == FAT_MAGIC_64
    entry = ">iiQQII" if is64 else ">iiIII"
    size = struct.calcsize(entry)
    for i in range(nfat):
        fields = struct.unpack(entry, data[8 + i * size: 8 + (i + 1) * size])
        cputype, _sub, offset, length = fields[0], fields[1], fields[2], fields[3]
        if cputype == CPU_TYPE_ARM64:
            out = data[offset: offset + length]
            if struct.unpack("<I", out[:4])[0] != 0xFEEDFACF:
                raise ValueError("arm64 slice is not a 64-bit Mach-O")
            return out
    raise ValueError("no arm64 slice in binary")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    converted = 0
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            data = zin.read(info)
            name = info.filename
            if name.endswith(".universal"):
                data = arm64_slice(data)
                name = name[: -len(".universal")] + ".arm64"
                converted += 1
            out = zipfile.ZipInfo(name, info.date_time)
            out.external_attr = info.external_attr
            out.compress_type = zipfile.ZIP_STORED if name.endswith("/") else zipfile.ZIP_DEFLATED
            zout.writestr(out, data)
            if name.endswith(".arm64"):
                print("  %s  %.1f MB" % (name, len(data) / 1e6))
    if converted == 0:
        raise SystemExit("no universal binaries found in " + src)
    print("wrote " + dst)


if __name__ == "__main__":
    main()
