#!/bin/bash

# --- Настройки ---
LOG_DIR="/var/log/nginx"
LOG_FILE="$LOG_DIR/access.log"
ERROR_LOG="$LOG_DIR/error.log"
LAST_RUN_FILE="/var/tmp/log_report.last"
LOCK_FILE="/var/tmp/log_report.lock"
MAIL_TO="fake@gmail.com"
TMP_REPORT="/tmp/log_report.txt"

# --- Функция очистки lock и временных файлов ---
cleanup() {
    rm -f "$LOCK_FILE" /tmp/log_report_filtered.log
}
trap cleanup EXIT INT TERM

# --- Проверка lock ---
if [ -f "$LOCK_FILE" ] && kill -0 $(cat "$LOCK_FILE") 2>/dev/null; then
    echo "Скрипт уже запущен, выходим."
    exit 1
fi
echo $$ > "$LOCK_FILE"

# --- Функция получения временного диапазона ---
get_time_range() {
    if [ -f "$LAST_RUN_FILE" ]; then
        SINCE=$(cat "$LAST_RUN_FILE")
    else
        SINCE="1970-01-01 00:00:00"
    fi
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$NOW" > "$LAST_RUN_FILE"

    SINCE_EPOCH=$(date -d "$SINCE" +%s)
    NOW_EPOCH=$(date -d "$NOW" +%s)
}

# --- Фильтрация логов ---
filter_logs() {
    # Очистим файл перед записью
    : > /tmp/log_report_filtered.log

    # Перебираем все access.log*
    for file in "$LOG_DIR"/access.log*; do
        [ -f "$file" ] || continue

        awk -v start="$SINCE_EPOCH" -v end="$NOW_EPOCH" '
        {
            # Убираем квадратные скобки
            gsub(/\[|\]/,"",$4)

            # $4 = 27/Feb/2026:15:35:34, $5 = +0000
            split($4, dt, /[:\/]/)
            day = dt[1]
            month_str = dt[2]
            year = dt[3]
            hour = dt[4]
            min = dt[5]
            sec = dt[6]

            # Преобразуем строку месяца в число
            months["Jan"]=1; months["Feb"]=2; months["Mar"]=3; months["Apr"]=4
            months["May"]=5; months["Jun"]=6; months["Jul"]=7; months["Aug"]=8
            months["Sep"]=9; months["Oct"]=10; months["Nov"]=11; months["Dec"]=12
            month = months[month_str]

            # Создаем epoch с помощью mktime: "YYYY MM DD HH MM SS"
            t = mktime(year " " month " " day " " hour " " min " " sec)

            if (t >= start && t <= end)
                print
        }' "$file" >> /tmp/log_report_filtered.log
    done
}

# --- Формирование отчёта ---
generate_report() {
    {
    echo "Subject: Отчет по веб серверу за период: $SINCE - $NOW"
    echo "Отчёт за период: $SINCE - $NOW"
    echo

    echo "--- TOP IP по количеству запросов ---"
    awk '{print $1}' /tmp/log_report_filtered.log | sort | uniq -c | sort -nr | head -10

    echo
    echo "--- TOP URL по количеству запросов ---"
    awk '{print $7}' /tmp/log_report_filtered.log | sed 's/\/$//' | sort | uniq -c | sort -nr | head -10

    echo
    echo "--- Ошибки веб-сервера/приложения ---"
    find "$LOG_DIR" -type f -name 'error.log*' | while read f; do
        awk -v start="$SINCE_EPOCH" -v end="$NOW_EPOCH" '
        /^[0-9]{4}\/[0-9]{2}\/[0-9]{2}/ {
            log_date = $1 " " $2
            cmd = "date -d \"" log_date "\" +%s"
            cmd | getline t
            close(cmd)
            if (t >= start && t <= end) print
        }' "$f"
    done
    echo
    echo "--- HTTP-коды ответов ---"
    awk '{print $9}' /tmp/log_report_filtered.log | sort | uniq -c | sort -nr

    } > "$TMP_REPORT"
}

# --- Отправка отчёта ---
send_mail() {
    cat "$TMP_REPORT"
    cat "$TMP_REPORT" | msmtp -a default "$MAIL_TO"
}

main() {
    get_time_range
    filter_logs
    generate_report
    send_mail
}

main