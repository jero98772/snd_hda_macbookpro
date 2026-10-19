#!/bin/bash
# Get brightness percentage
BR=$(brightnessctl g)
MAX=$(brightnessctl m)
PERCENT=$(( 100 * BR / MAX ))
echo "BR: $PERCENT%"

