# FFmpeg source for Ayris

[Ayris](https://ayris.nalonix.dev) includes `ffmpeg.exe` and `ffprobe.exe`. They are built from
the sources here and licensed under the GNU General Public License, version 3 (see `COPYING`).
Ayris runs them as separate programs.

This repository is their complete corresponding source:

- **`build.sh`**: the script that compiled them (cross-compiled for Windows x64 with MinGW-w64).
- **`BUILD-CONFIGURATION.txt`**: the exact versions and FFmpeg configure flags.
- **The release for each Ayris version** has every library's source archive at the exact
  version used. Nothing was patched.

| Ayris | Release |
|---|---|
| 1.0 | [ayris-1.0](../../releases/tag/ayris-1.0) |

## Sources in `ayris-1.0`

| Component | Version | Upstream |
|---|---|---|
| FFmpeg | 9.0.2 | https://ffmpeg.org |
| x264 | b35605ace3ddf7c1a5d67a2eb553f034aef41d55 | https://code.videolan.org/videolan/x264 |
| LAME | 3.100 | https://lame.sourceforge.io |
| libogg | 1.3.6 | https://xiph.org |
| libvorbis | 1.3.7 | https://xiph.org |
| Opus | 1.6.1 | https://opus-codec.org |
| libvpx | v1.17.0 | https://chromium.googlesource.com/webm/libvpx |
| zimg | release-3.0.6 | https://github.com/sekrit-twc/zimg |
| dav1d | 1.5.4 | https://code.videolan.org/videolan/dav1d |
| zlib | 1.3.2 | https://zlib.net |

`SHA256SUMS` in each release lists every archive's checksum.

## Rebuilding

In a Linux shell with the MinGW-w64 cross compiler, NASM, CMake, Meson and Ninja:

```sh
./build.sh <output dir> <licenses dir>
```

It fetches the same versions listed above and produces `ffmpeg.exe` and `ffprobe.exe`.

Questions: support@nalonix.dev
