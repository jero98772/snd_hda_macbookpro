#!/bin/bash
# Get current volume
VOL=$(amixer get Master | grep -o "[0-9]*%" | head -1)
MUTE=$(amixer get Master | grep -o "\[on\]")

if [ "$MUTE" != "[on]" ]; then
    echo "VOL: MUTE"
else
    echo "VOL: $VOL"
fi

