#!/bin/python3

import subprocess
import time
import json
import paho.mqtt.client as mqtt
from datetime import datetime, timezone, timedelta
import os
import signal

BROKER_IP = "192.168.0.102"   # your MQTT broker
BROKER_PORT = 1883
MQTT_USER = "safeon"
MQTT_PASS = "[REDACTED]"
TOPIC = "safeon/flows"

IFACE = "br-lan"
WINDOW = 10  # seconds per window

KST = timezone(timedelta(hours=9))


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=KST).isoformat()


# MQTT client
client = mqtt.Client()
client.username_pw_set(MQTT_USER, MQTT_PASS)
client.connect(BROKER_IP, BROKER_PORT, 60)

time_bucket = 0  # increases once per 10s window

while True:
    TMP = "/tmp/window.txt"
    if os.path.exists(TMP):
        os.remove(TMP)

    # Start tcpdump in background
    tcp = subprocess.Popen(
        ["tcpdump", "-i", IFACE, "-nn", "-tt", "-q"],
        stdout=open(TMP, "w"),
        stderr=subprocess.DEVNULL
    )

    # Capture for WINDOW seconds
    time.sleep(WINDOW)

    # Kill tcpdump
    tcp.terminate()
    try:
        tcp.wait(timeout=1)
    except Exception:
        tcp.kill()

    # This window's bucket ID
    current_bucket = time_bucket
    time_bucket += 1

    # Read lines
    try:
        with open(TMP) as f:
            lines = f.read().splitlines()
    except Exception:
        continue

    flows = {}
    first_ts = None

    for line in lines:
        parts = line.split()
        if len(parts) < 5:
            continue

        # <ts> IP src > dst: ...
        if parts[1] != "IP":
            continue

        try:
            ts = float(parts[0])
        except Exception:
            continue

        if first_ts is None:
            first_ts = ts

        src_full = parts[2]
        dst_full = parts[4].rstrip(":")

        # Parse src/dst ip + port
        try:
            s = src_full.split(".")
            d = dst_full.split(".")

            src_ip = ".".join(s[:4])
            src_port = int(s[4])

            dst_ip = ".".join(d[:4])
            dst_port = int(d[4])
        except Exception:
            continue

        # You can parse proto from the line if you want; keep 6 for now
        proto = 6  # pretend TCP

        # last token usually length
        try:
            plen = int(parts[-1])
        except Exception:
            plen = 0

        # key = 5-tuple (flow); bucket is global for this window
        key = (src_ip, dst_ip, src_port, dst_port, proto)

        if key not in flows:
            flows[key] = {
                "start": ts,
                "end": ts,
                "pc": 0,
                "bc": 0,
            }

        F = flows[key]
        F["pc"] += 1
        F["bc"] += plen
        if ts < F["start"]:
            F["start"] = ts
        if ts > F["end"]:
            F["end"] = ts

    # Send flows via MQTT for this window
    for (src_ip, dst_ip, src_port, dst_port, proto), F in flows.items():
        dur = max(0.000001, F["end"] - F["start"])
        pps = F["pc"] / dur
        bps = F["bc"] / dur

        msg = {
            "src_ip": src_ip,
            "dst_ip": dst_ip,
            "src_port": src_port,
            "dst_port": dst_port,
            "proto": proto,
            "time_bucket": current_bucket,
            "start_time": iso(F["start"]),
            "end_time": iso(F["end"]),
            "duration": dur,
            "packet_count": F["pc"],
            "byte_count": F["bc"],
            "pps": pps,
            "bps": bps,
        }

        client.publish(TOPIC, json.dumps(msg))

    # tiny pause before next window (not really needed)
    time.sleep(0.1)
