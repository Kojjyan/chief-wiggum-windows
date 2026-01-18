#!/usr/bin/env bash
# Callback: Worker made progress on PRD

WORKER_ID="$1"
echo "[$(date -Iseconds)] Worker $WORKER_ID made progress" >> .ralph/logs/workers.log
