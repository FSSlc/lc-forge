#!/usr/bin/env csh

if ( $?_CONDA_BACKUP_WHICH_ALIAS ) then
    alias which "$_CONDA_BACKUP_WHICH_ALIAS"
    unsetenv _CONDA_BACKUP_WHICH_ALIAS
endif
