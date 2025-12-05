#!/bin/python3

import subprocess
import json
import paho.mqtt.client as mqtt

BROKER_IP = "192.168.0.106"
BROKER_PORT = 1883
TOPIC_CMD = "safeon/block"

# resolve correct MAC from IP
def mac_from_ip(ip):
    try:
        out = subprocess.check_output(
            ["ip", "neigh", "show", ip]
        ).decode()
        parts = out.split()
        if "lladdr" in parts:
            return parts[parts.index("lladdr") + 1]
    except:
        pass
    return None

# disconnect
def kick_mac(mac):
    try:
        data = {
            "addr": mac,
            "reason": 5,
            "deauth": True,
            "ban_time": 60000
        }
        subprocess.run([
            "ubus", "call", "hostapd.phy0-ap0", "del_client",
            json.dumps(data)
        ])
    except Exception as e:
        print("Kick error:", e)
# MQTT handler
def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())

        # expected backend format:
        # { macAddress, ip, name }
        ip   = payload.get("ip")
        name = payload.get("name", "unknown")

        if not ip:
            print("Invalid payload, missing IP")
            return

        # get correct MAC from ARP
        real_mac = mac_from_ip(ip)

        if not real_mac:
            print("Cannot resolve MAC for", ip)
            return

        print(f"Disconnecting [{name}] {ip} ({real_mac})")

        kick_mac(real_mac)

    except Exception as e:
        print("Error:", e)

# Start MQTT client
client = mqtt.Client()
client.on_message = on_message
client.connect(BROKER_IP, BROKER_PORT, 60)
client.subscribe(TOPIC_CMD)
client.loop_forever()

