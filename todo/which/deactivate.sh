#!/usr/bin/env bash

if [ -n "${BASH_VERSION:-}" ]; then
    if [ -n "${_CONDA_BACKUP_WHICH_ALIAS:-}" ]; then
        eval "${_CONDA_BACKUP_WHICH_ALIAS}"
        unset _CONDA_BACKUP_WHICH_ALIAS
    fi
    if [ -n "${_CONDA_BACKUP_WHICH_FUNCTION:-}" ]; then
        eval "${_CONDA_BACKUP_WHICH_FUNCTION}"
        unset _CONDA_BACKUP_WHICH_FUNCTION
    fi
fi
