#!/bin/bash
for d in /sys/class/hwmon/*; do
  if [ "$(cat "$d/name")" = "nct6687" ]; then
    val=$(cat "$d/pwm1")
    echo 1 > "$d/pwm2_enable"
    echo "$val" > "$d/pwm2"
    exit 0
  fi
done
exit 1
