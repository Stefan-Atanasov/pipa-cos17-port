# Downloads

All current links in one place. Updated 2026-11-27. Current release: **v10** (2026-11-27).

## ROM

| Build | SourceForge (recommended) | Google Drive | Pixeldrain / Gofile (fast) | md5 of the .7z |
|---|---|---|---|---|
| **v10** | [ColorOS17-Port-pipa-v10-20261127.7z](https://sourceforge.net/projects/pipa-cos17-port/files/Releases/v10/ColorOS17-Port-pipa-v10-20261127.7z/download) | [Drive folder](https://drive.google.com/drive/folders/1Kd7b5rWhc0WC5Io_fCQKGUZ7yncnyech?usp=sharing) | https://pixeldrain.com/u/8XU13h9x / https://gofile.io/d/wV7l2C95 | `97dbe098df3e5ebf2c29571a10b27130` |
| v9.3 (previous) | [ColorOS17-Port-pipa-v9.3-20261121.7z](https://sourceforge.net/projects/pipa-cos17-port/files/Releases/v9.3/ColorOS17-Port-pipa-v9.3-20261121.7z/download) | [Drive folder](https://drive.google.com/drive/folders/1Kd7b5rWhc0WC5Io_fCQKGUZ7yncnyech?usp=sharing) | https://gofile.io/d/D5iyheCj | `3428d66f4258823c3cee1c75a72ea982` |
| **v9.3-noenc** (experimental) | [ColorOS17-Port-pipa-v9.3-noenc-20261123.7z](https://sourceforge.net/projects/pipa-cos17-port/files/Releases/v9.3/ColorOS17-Port-pipa-v9.3-noenc-20261123.7z/download) | [Drive folder](https://drive.google.com/drive/folders/1Kd7b5rWhc0WC5Io_fCQKGUZ7yncnyech?usp=sharing) | https://gofile.io/d/Fqn9Po3L | `99d9ea65a053516c2197b6b5a2157511` |

- **Which build?** Take **v10**. Already on v10: Pipa Helper > System > Updates installs the next versions (no PC). Take v9.3-noenc only for dual boot with Linux: it has no `/data` encryption, it was not booted by the maintainer, and it needs a clean flash (`2`, then `ERASE`). See [DUALBOOT-LINUX.md](DUALBOOT-LINUX.md).
- **All releases:** https://sourceforge.net/projects/pipa-cos17-port/files/Releases/ (one folder per release).
- **Gofile** deletes files after some time without downloads. If a Gofile link has expired, use SourceForge or Drive.
- **Check the download:** compare the md5 of the `.7z` with the table. The package has a `SHA256SUMS` file for the files inside.
- **Install:** unpack the `.7z` and read `README-FLASH.txt`. The [README](README.md#download-and-install) has the steps.

## Extras

- **Modules: none needed.** v10 has root (SukiSU Nova) and all fixes built in. Do not install old pipa modules or performance modules (Uperf and similar).
- **susfs root hiding (optional):** `pipa-susfs-v1.0.zip`, in the package folder `extras/` and in the Drive folder `modules/`.
- **SukiSU Nova manager app:** in the package folder `extras/`, or https://github.com/SukiSU-Nova/SukiSU-Nova/releases/download/v3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk
- **Screenshots** of the ROM and Pipa Helper (v9.2): https://drive.google.com/drive/folders/1StUhuz_dL07ydvdHJ1SriYAR-_zObTJ5

## Help and source

- **Report a bug:** https://github.com/Stefan-Atanasov/pipa-cos17-port/issues/new/choose
- **Known issues:** [KNOWN-ISSUES.md](KNOWN-ISSUES.md)
- **Support group (Telegram):** https://t.me/cosforpipa
- **Port source (this repository):** https://github.com/Stefan-Atanasov/pipa-cos17-port
- **Kernel source:** https://github.com/Stefan-Atanasov/kernel_xiaomi_pipa_cos17 (branch `oppo`)
