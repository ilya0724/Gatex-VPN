#!/bin/bash
# usage: render.sh <html> <w> <h> <out.png> [query]
C=$(ls -d /opt/pw-browsers/chromium_headless_shell-1194/*/)headless_shell
$C --no-sandbox --disable-gpu --allow-file-access-from-files --run-all-compositor-stages-before-draw --virtual-time-budget=3000 --hide-scrollbars --window-size=$2,$3 --screenshot=$4 "file://$1${5:+?$5}" >/dev/null 2>&1
