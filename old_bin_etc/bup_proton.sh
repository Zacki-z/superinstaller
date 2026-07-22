#!/bin/sh
set -x
# set -euo pipefail
echo on
rclone sync /home/alain/bup_base q:backups/bup_base
