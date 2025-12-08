#!/bin/sh

BROKER_IP="192.168.0.106"
BROKER_PORT="1883"
MQTT_USER="safeon"
MQTT_PASS="[REDACTED]"
TOPIC="safeon/devices"

logread -f | while read -r line; do
    EVENT=""
    MAC=""

    # Only care about hostapd lines
    echo "$line" | grep -q "hostapd:" || continue

    if echo "$line" | grep -q "AP-STA-CONNECTED"; then
        EVENT="connect"
        # pattern: ... AP-STA-CONNECTED <MAC> auth_alg=open
        MAC="$(echo "$line" | sed -n 's/.*AP-STA-CONNECTED \([^ ]*\).*/\1/p')"
        # give DHCP a moment to issue ACK so lease file is updated
        sleep 1
    elif echo "$line" | grep -q "AP-STA-DISCONNECTED"; then
        EVENT="disconnect"
        # pattern: ... AP-STA-DISCONNECTED <MAC>
        MAC="$(echo "$line" | sed -n 's/.*AP-STA-DISCONNECTED \([^ ]*\).*/\1/p')"
    else
        continue
    fi

    [ -n "$EVENT" ] || continue
    [ -n "$MAC" ] || continue

    IP="unknown"
    NAME="unknown"

    # Map MAC -> IP + hostname from dhcp.leases if possible
    if [ -f /tmp/dhcp.leases ]; then
        LEASE_LINE="$(grep -i " $MAC " /tmp/dhcp.leases | head -n1)"
        if [ -n "$LEASE_LINE" ]; then
            # format: <exp> <mac> <ip> <hostname> <id>
            set -- $LEASE_LINE
            # $1=exp, $2=mac, $3=ip, $4=hostname
            IP="$3"
            [ -n "$4" ] && NAME="$4"
        fi
    fi

    TS="$(date +%Y-%m-%dT%H:%M:%S%z)"

    JSON='{"status":"'"$EVENT"'","ip":"'"$IP"'","mac":"'"$MAC"'","name":"'"$NAME"'"}'

    echo "$JSON" > /tmp/last_device_event.json

    mosquitto_pub -h "$BROKER_IP" -p "$BROKER_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "$TOPIC" -m "$JSON" &
done
