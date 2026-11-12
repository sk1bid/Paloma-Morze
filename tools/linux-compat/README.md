# Linux compatibility build

The x86_64 helper is compiled with Debian 10's GCC 8, glibc 2.28 and
libstdc++ (GLIBCXX up to 3.4.25). This targets the older library baseline
needed by Astra Linux 1.7 and also suitable for newer libraries in 1.8.
Passing this check does not replace installation and device testing on Astra.

From the repository root on a Linux packaging host, with Docker running:

```sh
bash tools/linux-compat.sh build
cd ui
npm ci
npm run build
npx electron-builder --linux --x64 --publish never
cd ..
bash tools/linux-compat.sh test ui/release/*.AppImage
```

CI, preview and release use the same build and test commands. Node 22 and
Electron packaging run on a modern host. Only native compilation and packaged
runtime checks run in the pinned amd64 Debian container. Those container steps
also support Docker amd64 emulation on ARM; AppImage packaging itself should run
on Linux, since electron-builder's bundled macOS squashfs tool may not run on
Apple Silicon.

The Dockerfile pins the Debian base by digest. Its archived repositories retain
APT signature checks, with only the metadata expiration check disabled. They
provide a historical compatibility toolchain, not an environment for deployment.
These commands do not change libraries or audio settings on the target desktop.

The smoke test checks the packaged ELF dependency versions, starts the packaged
Electron app under Xvfb, checks the rendered interface, and exercises the packaged
audio helper through a private PulseAudio server. It runs as an unprivileged
container account. The wrapper passes `--no-sandbox` solely for this restricted
container test; normal desktop launches should use Electron's sandbox.
