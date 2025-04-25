#!/bin/bash

# Replace the directory with actual directory
directory="/hana/backup/PME_pmehana.sapb1mm.com_30013/PME/$1"

# Find and delete directories older than 2 days
dirs=$(find "$directory" -maxdepth 1 -type d -mtime +2)

for dir in $dirs; do
  if [ "$dir" != "$directory" ]; then
    rm -rf "$dir"
    echo "Deleted: $dir"
  fi
done
