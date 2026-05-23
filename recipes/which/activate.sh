#!/usr/bin/env bash

# Ignore type 'file' as conda environment will take precedence in PATH
if [ -n "${BASH_VERSION:-}" ]; then
    if [ "$(type -t which)" = "alias" ]; then
        export _CONDA_BACKUP_WHICH_ALIAS="$(alias which)"
        unalias which
    elif [ "$(type -t which)" = "function" ]; then
        export _CONDA_BACKUP_WHICH_FUNCTION="$(declare -f which)"
        unset -f which
    fi
fi
