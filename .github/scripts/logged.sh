#!/usr/bin/env bash
# Runs a command; on failure turns the end of its output into a workflow
# error annotation, which shows on the run page without opening the log.
# usage: logged.sh <title> <command...>
title=$1; shift
log=$(mktemp)
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  body=$(tail -n 80 "$log" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | sed ':a;N;$!ba;s/\n/%0A/g')
  echo "::error title=$title::$body"
fi
exit "$code"
