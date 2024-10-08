#!/usr/bin/env bash
# https://github.com/steel99xl/Mac-like-automatic-brightness/blob/main/AutomaticBrightness.sh

# How much light change must be seen by the sensor before it will act.
LightChange=10

# How often it checks the sensor
SensorDelay=1

# Scale sensor to displays brightness range
# NOW WITH FLOAT SUPPORT
SensorToDiplayScale=1

# This should match your refresh rate otherwise it will either change the backlight more times than needed or to few for a smooth animation
LevelSteps=60
# This should match the LevelSteps but in the actual time each event should take to see
AnimationDelay=0.016

# Read the variable names
MinimumBrightness=001

# 2 : Default | 1 : Add Offset | 0 : Subtract Offset, Recommended to not change
op=2

# Only look for flags -i or -d with an additional value
# AutomaticBrightness.sh -i 100
while getopts i:d: flag
do
  case "${flag}" in
    i) op=1
       num=${OPTARG};;
    d) op=0
       num=${OPTARG};;
  esac
done

# Verify offset file exists and if so read it
if [[ -f /dev/shm/AB.offset ]]; then
  OffSet=$(cat /dev/shm/AB.offset)
else
  OffSet=0
  $(echo $OffSet > /dev/shm/AB.offset)
  $(chmod 666 /dev/shm/AB.offset)
fi

# If no offset or it's less than 0 make 0
OffSet=$((OffSet < 0 ? 0 : OffSet))

# Relatively change number in Offset file and write it
if [[ $op -lt 2 ]]; then
  if [[ $op -eq 1 ]]; then
    OffSet=$((OffSet + num))
  else
    OffSet=$((OffSet - num))
  fi

  # Verify offset is not less than 0
  OffSet=$((OffSet < 0 ? 0 : OffSet))
  $(echo $OffSet > /dev/shm/AB.offset)
  exit
fi

# This was moved down here to not affect performance of setting AB.offset
priority=19 # Priority level, 0 = regular app, 19 = very much background app

# Set the priority of the current script, Thank you Theluga.
renice "$priority" "$$"

sleep 5

# Get screen max brightness value
MaxScreenBrightness=$(find -L /sys/class/backlight -maxdepth 2 -name "max_brightness" 2>/dev/null | grep "max_brightness" | xargs cat)

# Set path to current screen brightness value
BLightPath=$(find -L /sys/class/backlight -maxdepth 2 -name "brightness" 2>/dev/null | grep "brightness")

# Set path to current luminance sensor
LSensorPath=$(find -L /sys/bus/iio/devices -maxdepth 2 -name "in_illuminance_raw" 2>/dev/null | grep "in_illuminance_raw")

# Set the current light value so we have something to compare it to
OldLight=$(cat "$LSensorPath")

while true
do
  if [[ -f /dev/shm/AB.offset ]]; then
    OffSet=$(cat /dev/shm/AB.offset)
  else
    OffSet=0
    $(echo $OffSet >/dev/shm/AB.offset)
    $(chmod 666 /dev/shm/AB.offset)
  fi

  Light=$(cat "$LSensorPath")
  # Apply offset to current light value
  Light=$((Light + OffSet))

  # Set allowed range for light
  MaxOld=$((OldLight + OldLight / LightChange))
  MinOld=$((OldLight - OldLight / LightChange))

  if [[ $Light -gt $MaxOld ]] || [[ $Light -lt $MinOld ]]; then
    CurrentBrightness=$(cat "$BLightPath")

    # Add MinimumBrightness here to not effect comparison but the outcome
    Light=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; $Light + (($MaxScreenBrightness * ($MinimumBrightness / 100)) / $SensorToDiplayScale)" | bc))

    # Generate a TempLight value for the screen to be set to
    # Float math thanks Matthias_Wachter
    TempLight=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; $Light * $SensorToDiplayScale" | bc))

    # Check we don't ask the screen to go brighter than it can
    if [[ $TempLight -gt $MaxScreenBrightness ]]; then
      NewLight=$MaxScreenBrightness
    else
      NewLight=$TempLight
    fi

    # How different should each stop be
    DiffCount=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; ( $NewLight - $CurrentBrightness ) / $LevelSteps" | bc ))

    # Step once per screen HZ to make animation
    for i in $(eval echo {1..$LevelSteps})
    do

      # Set new relative light value
      NewLight=$(( DiffCount ))

        CurrentBrightness=$(cat "$BLightPath")
        FakeLight=$(( $NewLight + $CurrentBrightness ))

        if [[ $FakeLight -gt $MaxScreenBrightness ]]; then
          NewLight=$MaxScreenBrightness
          echo "ERROR"
        else
          echo $FakeLight > "$BLightPath"
        fi

      # Sleep for the screen HZ time so the effect is visible
      sleep $AnimationDelay
    done

    # Store new light as old light for next comparison
    OldLight=$Light
  fi
  sleep $SensorDelay
done
