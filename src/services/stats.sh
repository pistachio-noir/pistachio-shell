#!/bin/sh
# One reading for services/SystemStats.qml, a line per source:
#   stat cpu <the counters of /proc/stat's first line>
#   mem <MemTotal kB> <MemAvailable kB>
#   model <the CPU's model name>
#   temp <the CPU package temperature in millidegrees>        (coretemp, k10temp or zenpower)
#   gpu <name>, <load %>, <°C>, <MiB used>, <MiB total>      (an NVIDIA card, through nvidia-smi)
#   shell <CPU ticks> <memory in KiB> <cores>                 (the shell, this script's parent, and its
#                                                             helpers: agents, localsend.py)
#   disk <device> <KiB in all> <KiB free> <mount point>     (for / and /home; the same device twice
#                                                             when /home is on the root filesystem)
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
ticks=0
rss=0
for p in $PPID $(cat /proc/$PPID/task/*/children 2>/dev/null); do
    [ "$p" = "$$" ] || [ ! -r "/proc/$p/stat" ] && continue
    # after "pid (name) " the 12th and 13th fields are the time used in user and kernel mode
    set -- $(sed 's/^.*) //' "/proc/$p/stat")
    ticks=$((ticks + ${12} + ${13}))
    rss=$((rss + $(awk '/^VmRSS:/ { print $2 }' "/proc/$p/status" 2>/dev/null || echo 0)))
done
echo "shell $ticks $rss $(nproc)"
df -P -k / /home 2>/dev/null | awk 'NR > 1 { print "disk", $1, $2, $4, $6 }'
