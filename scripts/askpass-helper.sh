#!/bin/bash
# Simple askpass helper for sudo operations
# This uses zenity if available, otherwise falls back to terminal

if command -v zenity &> /dev/null; then
    # Use zenity (GUI dialog)
    zenity --password --title="sudo password required"
elif command -v ssh-askpass &> /dev/null; then
    # Use ssh-askpass
    ssh-askpass "sudo password:"
else
    # Fallback to terminal (won't work in all contexts)
    echo "ERROR: No askpass utility available" >&2
    echo "Install with: sudo apt install -y ssh-askpass zenity" >&2
    exit 1
fi
