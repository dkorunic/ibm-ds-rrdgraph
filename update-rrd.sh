#!/bin/sh

# constants and other
SAN_NAME="my-DS3300-SAN"
DS_CMD="SMcli -n $SAN_NAME -c \"show allLogicalDrives performanceStats;\""
RRD_FILE_PATH="rrd"
AWK_CMD='BEGIN { FS="," } /CONTROLLER|Logical Drive/ { gsub(/\"/, ""); gsub(/[ \t]+/, "_"); gsub(/CONTROLLER_IN_SLOT/, "CTRL"); gsub(/Logical_Drive/, "LUN"); print $1, $3, $4, $5, $7 }'

# time constants (don't touch pls)
HEARTBEAT=300
EPOCH=$(date +%s)
UPD=$(expr \( $EPOCH / $HEARTBEAT \) \* $HEARTBEAT)
UPD_PREV=$(expr $UPD - $HEARTBEAT)

# $1 = file
# $2 = calculated secs since epoch
create_rrd() {
    rrdtool create "$1" \
        --start "$2" \
        --step $HEARTBEAT \
        "DS:read_percent:GAUGE:$HEARTBEAT:0:100" \
        "DS:cache_hit_percent:GAUGE:$HEARTBEAT:0:100" \
        "DS:current_kbps:GAUGE:$HEARTBEAT:0:U" \
        "DS:current_iops:GAUGE:$HEARTBEAT:0:U" \
        "RRA:AVERAGE:0.5:1:300" \
        "RRA:AVERAGE:0.5:6:700" \
        "RRA:AVERAGE:0.5:24:775" \
        "RRA:AVERAGE:0.5:288:797" \
        "RRA:MAX:0.5:1:300" \
        "RRA:MAX:0.5:6:700" \
        "RRA:MAX:0.5:24:775" \
        "RRA:MAX:0.5:288:797"
    return $?
}

# $1 = file
# $2 = absolute value (gauge) for read percentage
# $3 = absolute value (gauge) for cache hit percentage
# $4 = absolute value (gauge) for current kb/s
# $5 = absolute value (gauge) for current io/s
update_rrd() {
    if [ ! -e "$1" ]; then
        if ! create_rrd "$1" $UPD_PREV; then
            echo "FATAL: Cannot create RRD file $1. Exiting."
            exit 1
        fi
    fi

    if ! rrdtool update "$1" "$UPD:$2:$3:$4:$5"; then
        echo "FATAL: Error updating RRD file $1. Exiting."
        exit 1
    fi
}

fetch_data() {
    if ! eval $DS_CMD | awk "$AWK_CMD"; then
        echo "FATAL: SMcli returned error. Exiting."
        exit 1
    fi
}

fetch_data | while read arry_name read_percent cache_hit_percent \
        current_kbps current_iops; do
    update_rrd "$RRD_FILE_PATH/$SAN_NAME-$arry_name.rrd" \
        $read_percent $cache_hit_percent $current_kbps $current_iops
done
