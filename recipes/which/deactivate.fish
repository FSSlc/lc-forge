#!/usr/bin/env fish

if functions -q _conda_backup_which
    functions -c _conda_backup_which which
    functions -e _conda_backup_which
end
