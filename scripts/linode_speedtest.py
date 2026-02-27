#!/usr/bin/env python3
import subprocess
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

SERVERS = [
    "amsterdam",
    "atlanta",
    "chennai",
    "chicago",
    "dallas",
    "frankfurt",
    "fremont",
    "jakarta",
    "london",
    "los-angeles",
    "madrid",
    "milan",
    "mumbai1",
    "newark",
    "osaka",
    "paris",
    "sao-paulo",
    "seattle",
    "singapore",
    "stockholm",
    "sydney",
    "tokyo2",
    "toronto1",
    "washington",
]

BASE_URL = "https://speedtest.{}.linode.com/100MB-linode.bin"


def test_latency(server):
    try:
        result = subprocess.run(
            [
                "curl",
                "--noproxy",
                "*",
                "-w",
                "%{time_connect}",
                "-o",
                "/dev/null",
                "-s",
                f"https://speedtest.{server}.linode.com/",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = result.stdout.strip()
        latency = float(output) if output else None
        return server, latency
    except Exception:
        return server, None


def test_download_speed(server):
    try:
        start = time.time()
        result = subprocess.run(
            [
                "curl",
                "--noproxy",
                "*",
                "-s",
                "-o",
                "/dev/null",
                "--max-time",
                "30",
                f"https://speedtest.{server}.linode.com/100MB-linode.bin",
            ],
            capture_output=True,
            timeout=35,
        )
        elapsed = time.time() - start
        if elapsed > 0:
            size_mb = 100
            speed_mbps = (size_mb * 8) / elapsed
            return server, speed_mbps, elapsed
        return server, None, None
    except Exception:
        return server, None, None
    except subprocess.TimeoutExpired:
        return server, None, None
    except Exception as e:
        return server, None, None
    except subprocess.TimeoutExpired:
        return server, None, None
    except Exception:
        return server, None, None


def main():
    print("Testing Latency to all Linode servers...")
    print("-" * 50)

    results = []
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(test_latency, s): s for s in SERVERS}
        for future in as_completed(futures):
            server, latency = future.result()
            if latency:
                results.append((server, latency))
                print(f"{server:15} {latency:.3f}s")

    results.sort(key=lambda x: x[1])
    print("\n" + "=" * 50)
    print("TOP 3 SERVERS (by latency):")
    print("=" * 50)
    for i, (server, latency) in enumerate(results[:3], 1):
        print(f"{i}. {server:15} {latency:.3f}s")

    print("\n" + "=" * 50)
    print("Testing Download Speed (this may take a while)...")
    print("=" * 50)

    top_servers = [s[0] for s in results[:5]]
    for server in top_servers:
        print(f"Testing {server}...", end=" ", flush=True)
        _, speed, elapsed = test_download_speed(server)
        if speed:
            print(f"{speed:.1f} Mbps ({elapsed:.1f}s)")
        else:
            print("failed")

    print("\nDone!")


if __name__ == "__main__":
    main()
