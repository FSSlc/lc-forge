#!/bin/bash
# Package opencode-desktop (Electron AppImage) for legacy RHEL/CentOS 7.
# Every ELF executable is pointed at a bundled glibc 2.28 loader so the app
# runs on hosts whose system glibc is older than Electron requires.
set -Eeuo pipefail

case "$(uname -m)" in
  x86_64)
    CTG="x86_64-conda-linux-gnu"
    LOADER="ld-linux-x86-64.so.2"
    ;;
  aarch64)
    CTG="aarch64-conda-linux-gnu"
    LOADER="ld-linux-aarch64.so.1"
    ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

APP_NAME="opencode-desktop"
APP="$PREFIX/$APP_NAME"
mkdir -p "$APP"

# ---- 1. extract the AppImage ----
cd "$SRC_DIR"
APPIMAGE="$(find . -maxdepth 1 -name '*.AppImage' -print -quit)"
[[ -n "$APPIMAGE" ]] || { echo "AppImage not found in $SRC_DIR" >&2; exit 1; }
chmod +x "$APPIMAGE"
"./$APPIMAGE" --appimage-extract >/dev/null 2>&1
[[ -d squashfs-root ]] || { echo "appimage-extract produced no squashfs-root" >&2; exit 1; }
cp -a squashfs-root/. "$APP/"
rm -rf squashfs-root "$APPIMAGE"

# ---- 2. bundle the glibc 2.28 runtime (copied from the conda-forge sysroot) ----
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SR_PKG="$(find "$SRC_DIR" -maxdepth 1 -name 'sysroot_linux-*.conda' -print -quit)"
if [[ -n "$SR_PKG" ]]; then
  # .conda is a zip wrapping pkg-*.tar.zst; unpack both layers.
  bsdtar -xf "$SR_PKG" -C "$WORK"
  INNER="$(find "$WORK" -maxdepth 1 -name 'pkg-sysroot_linux-*.tar.zst' -print -quit)"
else
  INNER="$(find "$SRC_DIR" -maxdepth 1 -name 'pkg-sysroot_linux-*.tar.zst' -print -quit)"
fi
[[ -n "$INNER" ]] || { echo "sysroot package not found in $SRC_DIR" >&2; exit 1; }
bsdtar -xf "$INNER" -C "$WORK"

SYSROOT_SRC="$(find "$WORK" -maxdepth 1 -type d -name '*conda-linux-gnu' -print -quit)"
[[ -n "$SYSROOT_SRC" ]] || { echo "sysroot tree not found" >&2; exit 1; }

mkdir -p "$APP/sysroot"
cp -a "$SYSROOT_SRC/sysroot/lib64" "$APP/sysroot/lib64"
if [[ -d "$SYSROOT_SRC/sysroot/usr/lib64/gconv" ]]; then
  mkdir -p "$APP/sysroot/usr/lib64"
  cp -a "$SYSROOT_SRC/sysroot/usr/lib64/gconv" "$APP/sysroot/usr/lib64/gconv"
fi

# ---- 3. repoint every shipped ELF executable at the bundled loader ----
# The interpreter string contains the (build-time) prefix; conda relocates it
# to the install prefix at install time via has_prefix.
for bin in ai.opencode.desktop chrome_crashpad_handler chrome-sandbox; do
  if [[ -f "$APP/$bin" ]]; then
    patchelf --set-interpreter "$PREFIX/$APP_NAME/sysroot/lib64/$LOADER" \
             --set-rpath '$ORIGIN:$ORIGIN/usr/lib:$ORIGIN/sysroot/lib64' \
             "$APP/$bin"
  fi
done

# ---- 4. launcher ----
mkdir -p "$PREFIX/bin"
cat > "$PREFIX/bin/$APP_NAME" <<'EOF'
#!/bin/bash
# opencode-desktop launcher.
# Runs the Electron app on the bundled glibc 2.28 loader. The setuid chrome
# sandbox cannot work from a conda install, so fall back to it only when
# unprivileged user namespaces are available; otherwise pass --no-sandbox.
set -Eeuo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
prefix="$(cd "$here/.." && pwd)"
app="$prefix/opencode-desktop"

export LD_LIBRARY_PATH="$app/sysroot/lib64:$app:$app/usr/lib:$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GCONV_PATH="$app/sysroot/usr/lib64/gconv"

args=("$@")
if ! command -v unshare >/dev/null 2>&1 || ! unshare -Ur true 2>/dev/null; then
  args=(--no-sandbox "${args[@]}")
fi

exec "$app/ai.opencode.desktop" "${args[@]}"
EOF
chmod 0755 "$PREFIX/bin/$APP_NAME"

# ---- 5. desktop integration ----
mkdir -p "$PREFIX/share/applications"
if [[ -f "$APP/opencode-desktop.desktop" ]]; then
  sed "s|^Exec=.*|Exec=${PREFIX}/bin/${APP_NAME} %U|" \
    "$APP/opencode-desktop.desktop" > "$PREFIX/share/applications/opencode-desktop.desktop"
else
  cat > "$PREFIX/share/applications/opencode-desktop.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenCode Desktop
Comment=OpenCode desktop app
Exec=${PREFIX}/bin/${APP_NAME} %U
Icon=opencode-desktop
Terminal=false
Categories=Development;IDE;
StartupWMClass=opencode-desktop
EOF
fi

if [[ -d "$APP/usr/share/icons" ]]; then
  mkdir -p "$PREFIX/share/icons"
  cp -a "$APP/usr/share/icons/." "$PREFIX/share/icons/"
fi

# ---- 6. license ----
lic=""
for cand in "$APP"/LICENSE* "$APP"/license*; do
  if [[ -f "$cand" ]]; then lic="$cand"; break; fi
done
if [[ -n "$lic" ]]; then
  mkdir -p "$PREFIX/share/licenses/$APP_NAME"
  cp "$lic" "$PREFIX/share/licenses/$APP_NAME/"
fi

# remove AppRun & meta files that would bypass the launcher
rm -f "$APP/AppRun" "$APP/.DirIcon" || true

echo "opencode-desktop staged at $APP ($(du -sh "$APP" | cut -f1))"