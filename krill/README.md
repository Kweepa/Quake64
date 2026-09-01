# Krill loader v194 — prebuilt for Quake64

Binaries only; the loader source is not vendored here. Built from Krill's
`loader` project, repository version 194:

    make -C src PLATFORM=c64 prg INSTALL=2000 RESIDENT=EE08 ZP=60 \
         EXTCONFIGPATH=<config dir>

with `LOAD_TO_API = 1` and `UNINSTALL_API = 0`; everything else stock.

`quake64-krill.d64` packs these files (`build.bat -DUSE_KRILL=1`).
`quake64.d64` is KERNAL `$FFD5` and does not include them.

| file | load address | notes |
|---|---|---|
| `loader.prg` | `$EE08`–`$EEF3` | resident, 236 B. Splashc KERNAL-loads it, then it stays for the whole session. |
| `install.prg` | `$2000`–`$3B52` | transient. Run once at splash; MENU and GAME overwrite it. |
| `loadersymbols-c64.inc` | — | the build's own symbol/config dump, for reference. |

`LOAD_TO_API = 1` is required: the heap blobs (`E1M1`, `RELOC`, `GRUNT`…) all
carry PRG load address `$0000`, and `LoadPrg` supplies the real destination in
`loadaddrlo`/`loadaddrhi` with carry set.

`UNINSTALL_API = 0` saves 13 bytes, which is what makes the resident fit the
248-byte gap at `$EE08` between the charset B margin glyph and `LOGTAB`.

`$EE08` is under the KERNAL ROM, so `$01` must be `BANK_LOADER` (`$35`) around
every `jsr loadraw`, under `SEI`.
