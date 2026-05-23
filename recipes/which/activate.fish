#!/usr/bin/env fish

if functions -q which
    functions -c which _conda_backup_which
    functions -e which
end
