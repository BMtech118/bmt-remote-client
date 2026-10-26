# BMT Remote

BM Technologies' branded build of [RustDesk](https://github.com/rustdesk/rustdesk) for one-time remote support sessions, using our own server (`remote.bmtech.co.uk`).

RustDesk is licensed under AGPL-3.0, and so is this fork: the full source of every build we distribute is this repository (branch `bmt`) plus [BMtech118/bmt-remote-hbb-common](https://github.com/BMtech118/bmt-remote-hbb-common) (branch `bmt`). RustDesk's copyright notices are kept. "BMT Remote" is not RustDesk and is not endorsed by its authors.

Changes from upstream 1.5.0:
- `libs/hbb_common`: built-in server, public key and app name (BMT Remote).
- `branding/apply.sh`: icons, logos, product name, macOS bundle id and version info.
- `.github/workflows/bmt-build.yml`: Windows x64 and macOS builds only.
