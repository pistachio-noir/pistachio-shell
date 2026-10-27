#!/bin/sh
# One reading for services/SystemStats.qml, a line per source:
#   stat cpu <the counters of /proc/stat's first line>
#   mem <MemTotal kB> <MemAvailable kB>
#   model <the CPU's model name>
#   temp <the CPU package temperature in millidegrees>        (coretemp, k10temp or zenpower)
#   gpu <name>, <load %>, <°C>, <MiB used>, <MiB total>      (an NVIDIA card, through nvidia-smi)
head -n 1 /proc/stat | sed 's/^/stat /'
awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print "mem", t, a }' /proc/meminfo
grep -m 1 '^model name' /proc/cpuinfo | sed 's/^[^:]*: */model /'
for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2>/dev/null)" in
    coretemp | k10temp | zenpower)
        echo "temp $(cat "$h/temp1_input")"
        break
        ;;
    esac
done
if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | sed 's/^/gpu /'
fi
