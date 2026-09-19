#!/bin/bash
set -Eeuo pipefail

# configure.ac appends -Werror to CFLAGS on Linux.  The socket path baked into
# XRDP_SOCKET_ROOT_PATH comes from --with-socketdir, i.e. from $PREFIX, which at
# build time is rattler-build's 255-character placeholder prefix.  That string
# cannot fit into sun_path (108 bytes), so gcc's -Wformat-overflow /
# -Wformat-truncation abort the build in sesman/tools/dis.c and xrdpapi.c.
# Pre-seeding the autoconf-archive cache variable makes AX_CHECK_COMPILE_FLAG
# report -Werror as unsupported, so it is never appended.  If a future xrdp
# bumps that macro the build fails loudly in the same two files.
export ax_cv_check_cflags___Werror=no

# Default build writes xrdp.ini / sesman.ini to /etc/xrdp and the session
# socket dir to /var/run/xrdp.  --enable-strict-locations is what makes
# configure honour --sysconfdir/--localstatedir, so the package stays inside
# $PREFIX; without it configure forces sysconfdir=/etc and localstatedir=/var.
# PAM is disabled: no pam headers/dev library in the channel, so sesman uses
# its built-in /etc/shadow + crypt() authentication (configure's "Builtin").
./configure \
  --prefix="$PREFIX" \
  --enable-strict-locations \
  --sysconfdir="$PREFIX/etc" \
  --localstatedir="$PREFIX/var" \
  --with-socketdir="$PREFIX/var/run/xrdp" \
  --without-systemdsystemunitdir \
  --disable-pam

make -j"${CPU_COUNT:-1}"

# Upstream's keygen install hook generates rsakeys.ini / cert.pem into
# $sysconfdir/xrdp and expects the packager to have created that directory;
# the instfiles target that installs the rest of the config runs later.
mkdir -p "$PREFIX/etc/xrdp"
make install
