#!/usr/bin/env csh

set _conda_which_alias = "`alias which`"
if ( "$_conda_which_alias" != "" ) then
    setenv _CONDA_BACKUP_WHICH_ALIAS "$_conda_which_alias"
    unalias which
endif
unset _conda_which_alias
