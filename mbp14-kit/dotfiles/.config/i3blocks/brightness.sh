#!/bin/bash
# ~/.config/i3blocks/brightness.sh

DEVICE="gmux_backlight"

# Handle clicks AND SCROLL
case "$BLOCK_BUTTON" in
    1) brightnessctl -d $DEVICE set +10% ;;   # Left click increases brightness
    3) brightnessctl -d $DEVICE set 10%- ;;   # Right click decreases brightness
    4) brightnessctl -d $DEVICE set +5% ;;    # Scroll UP increases brightness
    5) brightnessctl -d $DEVICE set 5%- ;;    # Scroll DOWN decreases brightness
esac

# Get current brightness percentage
CURRENT=$(brightnessctl -d $DEVICE g)
MAX=$(brightnessctl -d $DEVICE m)
PERCENT=$(( 100 * CURRENT / MAX ))

# Choose icon based on brightness level
if [ "$PERCENT" -eq 0 ]; then
    ICON="🌑"   # dark
elif [ "$PERCENT" -le 30 ]; then
    ICON="🌘"
elif [ "$PERCENT" -le 60 ]; then
    ICON="🌗"
elif [ "$PERCENT" -le 90 ]; then
    ICON="🌖"
else
    ICON="🌕"   # bright
fi

echo "$ICON $PERCENT%"
