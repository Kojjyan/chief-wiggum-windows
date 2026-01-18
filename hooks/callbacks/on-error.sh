#!/usr/bin/env bash
# Callback: Log errors

WORKER_ID="$1"
MESSAGE="$2"
echo "[$(date -Iseconds)] ERROR Worker $WORKER_ID: $MESSAGE" >> .ralph/logs/errors.log
