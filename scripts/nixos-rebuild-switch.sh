#!/usr/bin/env bash
# nixos-rebuild-switch.sh — SSH-sicherer Switch via nohup
# Prozess überlebt sshd-Neustart, weil er von der Session entkoppelt ist.
set -e

LOG=/tmp/nixos-switch.log
FLAKE="/etc/nixos#q958"

echo "=== nixos-rebuild switch ===" | tee "$LOG"
echo "Log: $LOG"
echo ""
echo "HINWEIS: SSH-Verbindung kann kurz unterbrechen (sshd-Neustart)."
echo "         Danach reconnecten und 'cat $LOG' prüfen."
echo ""

nohup nixos-rebuild switch --flake "$FLAKE" --impure >> "$LOG" 2>&1 &
SWITCH_PID=$!
echo "PID: $SWITCH_PID"

# Live-Output so lange SSH-Verbindung steht
tail -f "$LOG" --pid=$SWITCH_PID
