#!/bin/bash

printf "%-15s %5s %6s %6s %8s %8s %-5s %s\n" USER PID CPU_usage MEM VSZ_MB RSS_MB STAT COMMAND

mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
uptime=$(awk '{print $1}' /proc/uptime)
clk_tck=$(getconf CLK_TCK)
page_size=$(getconf PAGESIZE)

for p in /proc/[0-9]*; do
    pid=$(basename "$p")

    [ -r "$p/stat" ] || continue

    stat=($(cat $p/stat))

    state=${stat[2]}
    utime=${stat[13]}
    stime=${stat[14]}
    process_start_time=${stat[21]}
    vsize=${stat[22]}
    rss=${stat[23]}

    total_time=$((utime + stime))

    process_seconds=$(awk -v up=$uptime -v start=$process_start_time -v hz=$clk_tck \
        'BEGIN {print up - (start/hz)}')

    cpu_usage=$(awk -v total=$total_time -v sec=process_seconds -v hz=$clk_tck \
        'BEGIN { if(sec>0) printf "%.2f", (total/hz)/sec*100; else print 0 }')

    rss_bytes=$((rss * page_size))
    rss_kb=$((rss_bytes / 1024))

    mem_usage=$(awk -v rss=$rss_kb -v total=$mem_total_kb \
        'BEGIN {printf "%.3f", rss/total}')

    vsz_mb=$(awk -v v=$vsize 'BEGIN {printf "%.3f", v/1024/1024}')
    rss_mb=$(awk -v r=$rss_bytes 'BEGIN {printf "%.3f", r/1024/1024}')

    uid=$(awk '/Uid:/ {print $2}' $p/status 2>/dev/null)
    user=$(getent passwd "$uid" | cut -d: -f1)

    cmd=$(tr '\0' ' ' < $p/cmdline 2>/dev/null)
    [ -z "$cmd" ] && cmd=$(cat $p/comm 2>/dev/null)

    printf "%-15s %5s %6s %6s %8s %8s %-5s %s\n" \
        "$user" "$pid" "$cpu_usage" "$mem_usage" "$vsz_mb" "$rss_mb" "$state" "$cmd"

done | sort -k3 -nr