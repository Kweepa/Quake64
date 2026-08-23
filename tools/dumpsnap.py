"""Dump useful state from a VICE .vsf snapshot."""
from pathlib import Path
import struct
import sys


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\dev\Quake64\vice-snapshot-20260815090939.vsf")
    d = path.read_bytes()
    print("file", path.name, "len", len(d))

    def loc(tag: bytes) -> int:
        i = d.find(tag)
        print("find", tag, i)
        return i

    cpu_i = loc(b"MAINC64CPU")
    print("cpu hdr", d[cpu_i : cpu_i + 64].hex())
    maj, mn = d[cpu_i + 16], d[cpu_i + 17]
    csize = struct.unpack_from("<I", d, cpu_i + 18)[0]
    cpup = d[cpu_i + 22 : cpu_i + csize]
    print("MAINC64CPU v%s.%s size=%s pay=%s" % (maj, mn, csize, len(cpup)))
    print("cpu payload", cpup[:80].hex())

    i = loc(b"C64MEM")
    maj, mn = d[i + 16], d[i + 17]
    size = struct.unpack_from("<I", d, i + 18)[0]
    payload = d[i + 22 : i + size]
    print("C64MEM v%s.%s size=%s pay=%s pport=%02X dir=%02X" % (maj, mn, size, len(payload), payload[0], payload[1]))
    mem = payload[4 : 4 + 65536]
    print("RAM", len(mem))

    def hd(addr, n=16):
        chunk = mem[addr : addr + n]
        return "$%04X: " % addr + " ".join("%02X" % b for b in chunk)

    zp = {
        "x0": 0x12, "y0": 0x13, "x1": 0x14, "y1": 0x15,
        "dx": 0x16, "dy": 0x17, "sx": 0x18, "sy": 0x19,
        "err": 0x1A, "linect": 0x1B,
        "draw_buf": 0x1E, "show_buf": 0x1F, "pending": 0x20,
        "top_hi": 0x21, "bot_hi": 0x22, "tile_ch": 0x23, "tile_half": 0x24,
        "dirty": 0x25, "yaw": 0x2D, "pitch": 0x2E, "z_eye": 0x2F,
        "vindex": 0x35, "dt_ms": 0x38, "colL": 0x06, "colH": 0x07,
        "rx": 0x30, "ry": 0x31, "rz": 0x32, "cs": 0x33, "sn": 0x34,
    }
    print("ZP", {k: "$%02X" % mem[a] for k, a in zp.items()})
    print("mem01", "$%02X" % mem[1])
    print("PROJ_X", hd(0xCA00, 8))
    print("PROJ_Y", hd(0xCA08, 8))
    print("PROJ_Z", hd(0xCA20, 8))
    print("COSTAB", hd(0xD648, 8))
    print("SINTAB", hd(0xD608, 8))
    hud = 18 * 40 + 4
    print("HUD A", mem[0xC000 + hud : 0xC000 + hud + 6].hex())
    print("HUD B", mem[0xC400 + hud : 0xC400 + hud + 6].hex())
    print("SCR_A r0c4", hd(0xC000 + 4, 32))
    for name, a in [("A_TOP", 0xD000), ("A_BOT", 0xD800), ("B_TOP", 0xE000), ("B_BOT", 0xE800), ("UI", 0xF000)]:
        region = mem[a : a + 0x800]
        nz = sum(1 for b in region if b)
        bits = sum(bin(b).count("1") for b in region)
        print("%s nz=%d bits=%d" % (name, nz, bits))

    # stack
    print("stack 01F0", hd(0x01F0, 16))

    # VIC-II
    v = loc(b"VIC-II")
    print("VIC hdr", d[v : v + 40].hex())


if __name__ == "__main__":
    main()
