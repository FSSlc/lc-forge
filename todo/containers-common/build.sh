#! /bin/sh

mkdir -p "${PREFIX}/etc/containers"
mkdir -p "${PREFIX}/share/containers"

mkdir "${PREFIX}/etc/containers/registries.conf.d"
cp $RECIPE_DIR/config/registries.conf "${PREFIX}/etc/containers/"

mkdir "${PREFIX}/etc/containers/registries.d"
cp skopeo/default.yaml "${PREFIX}/etc/containers/registries.d/"

cp skopeo/default-policy.json "${PREFIX}/etc/containers/policy.json"

# Exclude Linux-specific configuration on other platforms.
case "${target_platform}" in linux-*)
  cp common/pkg/seccomp/seccomp.json "${PREFIX}/share/containers/"

  sed '
    /^# *hooks_dir = \[/ {
      :loop_hooks_dir
      N
      /\]/b end_hooks_dir
      b loop_hooks_dir
      :end_hooks_dir
      s/# *//g
      s|"/usr/|"'"${PREFIX}"'/|
    }

    /^# *seccomp_profile = "/ {
      s/# *//g
      s|"/usr/|"'"${PREFIX}"'/|
    }

    /^# *cni_plugin_dirs = \[/ {
      :loop_cni_plugin_dirs
      N
      /\]/b end_cni_plugin_dirs
      b loop_cni_plugin_dirs
      :end_cni_plugin_dirs
      s/# *//g
      s|"/usr/libexec/|"'"${PREFIX}"'/lib/|
    }

    /^# *network_config_dir = "/ {
      s/# *//g
      s|"/|"'"${PREFIX}"'/|
    }
    ' \
    common/pkg/config/containers.conf \
    > "${PREFIX}/share/containers/containers.conf"
esac
