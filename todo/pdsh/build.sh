#!/usr/bin/env bash
# Build pdsh 2.36 — parallel remote shell utility from LLNL.
#
# Modules enabled:
#   --with-ssh        ssh-based rcmd (most common)
#   --with-exec       local exec rcmd
#   --with-machines   flat file host list
#   --with-dshgroups   dsh group file
#   --with-netgroup   NIS netgroups
#   --with-readline   readline interactive support
#
# Modules disabled (no conda deps):
#   --without-genders --without-slurm --without-torque
#   --without-nodeupdown --without-mrsh --without-xcpu
set -Eeuo pipefail

./configure \
  --prefix="${PREFIX}" \
  --with-ssh \
  --with-exec \
  --with-machines \
  --with-dshgroups \
  --with-netgroup \
  --with-readline \
  --without-genders \
  --without-slurm \
  --without-torque \
  --without-nodeupdown \
  --without-mrsh \
  --without-xcpu \
  --enable-static-modules

make -j"${CPU_COUNT}"
make install