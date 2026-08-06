#!/bin/bash
for d in /sys/class/hwmon/*; do
  if [ "$(cat "$d/name")" = "nct6687" ]; then
    echo 99 > "$d/pwm1_enable"
    echo 1 > "$d/pwm3_enable"; echo 51 > "$d/pwm3"
    echo 1 > "$d/pwm4_enable"; echo 51 > "$d/pwm4"
    exit 0
  fi
done
exit 1
