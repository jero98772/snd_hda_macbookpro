#!/bin/bash
# ~/.config/i3blocks/volume.sh

PCTL=/usr/bin/pactl

# Handle mouse clicks AND SCROLL
case "$BLOCK_BUTTON" in
    1) $PCTL set-sink-mute @DEFAULT_SINK@ toggle ;;      # Left click to mute/unmute
    3) pavucontrol & ;;                                   # Right click opens mixer (optional)
    4) $PCTL set-sink-volume @DEFAULT_SINK@ +5% ;;       # Scroll UP to increase
    5) $PCTL set-sink-volume @DEFAULT_SINK@ -5% ;;       # Scroll DOWN to decrease
esac

# Get current volume
VOL=$($PCTL get-sink-volume @DEFAULT_SINK@ | awk -F'/' 'NR==1{gsub(/ /,"",$2); print $2}')
MUTE=$($PCTL get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')

if [ "$MUTE" = "yes" ]; then
    echo "🔇 MUTE"
else
    echo "🔊 $VOL"
fi
