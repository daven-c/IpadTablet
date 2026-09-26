#!/usr/bin/env python3
"""Absolute-position TCP-to-CGEvent bridge: turns an iPad+Pencil into a Wacom-style tablet.

Transport: the iPad app listens on TCP :12345 and this daemon reaches it
through `iproxy`, which tunnels that port over the paired USB/usbmuxd link
to the cable itself — no Wi-Fi, no Personal Hotspot required (this matters
on a Wi-Fi-only iPad, which has no Personal Hotspot feature at all).

Wire format: 8-byte records, two little/native-endian float32s (x, y),
NORMALIZED (0.0-1.0) against the iPad app's live view bounds. The iPad's own
settings screen only shapes that input area's aspect ratio/sensitivity — it
has no say in which physical Mac display these coordinates land on. That's
chosen here, with --display, since it's a Mac-side concern (same as any
tablet driver's display mapping).

Requires Accessibility permission: System Settings > Privacy & Security >
Accessibility > add the terminal (or python3 binary) running this script.
"""
import argparse
import signal
import socket
import struct
import subprocess
import sys
import time

import ApplicationServices
import Quartz

DEVICE_PORT = 12345
LOCAL_PORT = 12345
RECORD_SIZE = 8  # two float32s
RECONNECT_DELAY = 0.5


def list_displays():
    _, display_ids, count = Quartz.CGGetActiveDisplayList(16, None, None)
    main_id = Quartz.CGMainDisplayID()
    displays = []
    for display_id in display_ids:
        bounds = Quartz.CGDisplayBounds(display_id)
        displays.append({
            "id": display_id,
            "is_main": display_id == main_id,
            "bounds": bounds,
        })
    return displays


def pick_display(displays, index: int | None):
    if index is None:
        # Default to the largest non-main display if there's more than one,
        # since a second display is usually the one actually being used;
        # falls back to main on a single-display machine.
        if len(displays) > 1:
            non_main = [d for d in displays if not d["is_main"]]
            return max(non_main, key=lambda d: d["bounds"].size.width * d["bounds"].size.height)
        return displays[0]
    return displays[index]


def check_accessibility_trust() -> None:
    if not ApplicationServices.AXIsProcessTrusted():
        print(
            "WARNING: this process is not trusted for Accessibility.\n"
            "Cursor injection will silently do nothing until you grant it:\n"
            "System Settings > Privacy & Security > Accessibility > add your terminal app.",
            file=sys.stderr,
        )


def make_cursor_mover(origin_x: float, origin_y: float, width: float, height: float):
    def move_cursor(norm_x: float, norm_y: float) -> None:
        norm_x = min(max(norm_x, 0.0), 1.0)
        norm_y = min(max(norm_y, 0.0), 1.0)
        point = Quartz.CGPoint(x=origin_x + norm_x * width, y=origin_y + norm_y * height)
        event = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, point, 0)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
    return move_cursor


def start_iproxy() -> subprocess.Popen:
    return subprocess.Popen(
        ["iproxy", f"{LOCAL_PORT}:{DEVICE_PORT}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def connect_with_retry() -> socket.socket:
    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            sock.connect(("127.0.0.1", LOCAL_PORT))
            return sock
        except OSError:
            sock.close()
            time.sleep(RECONNECT_DELAY)


def stream_records(sock: socket.socket):
    buffer = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            return
        buffer += chunk
        while len(buffer) >= RECORD_SIZE:
            record, buffer = buffer[:RECORD_SIZE], buffer[RECORD_SIZE:]
            yield struct.unpack("ff", record)


def run(display_index: int | None) -> None:
    check_accessibility_trust()

    displays = list_displays()
    print("Active displays:")
    for i, d in enumerate(displays):
        b = d["bounds"]
        tag = " (main)" if d["is_main"] else ""
        print(f"  [{i}] id={d['id']}{tag} bounds=({b.origin.x:.0f},{b.origin.y:.0f},{b.size.width:.0f}x{b.size.height:.0f})")

    chosen = pick_display(displays, display_index)
    bounds = chosen["bounds"]
    move_cursor = make_cursor_mover(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height)
    print(f"Targeting display id={chosen['id']}, bounds=({bounds.origin.x:.0f},{bounds.origin.y:.0f},{bounds.size.width:.0f}x{bounds.size.height:.0f})")

    print(f"Starting iproxy tunnel: Mac:{LOCAL_PORT} -> device:{DEVICE_PORT} over USB")
    iproxy = start_iproxy()
    time.sleep(0.3)
    if iproxy.poll() is not None:
        print(
            f"ERROR: iproxy exited immediately (code {iproxy.returncode}). "
            f"Likely another instance is already bound to port {LOCAL_PORT} "
            "(e.g. a daemon killed with plain `kill` rather than Ctrl-C, "
            "leaving its iproxy child orphaned). Try: pkill -9 -f iproxy",
            file=sys.stderr,
        )
        sys.exit(1)

    # A plain `kill` sends SIGTERM, which Python does NOT route through
    # KeyboardInterrupt — without this, that leaves the iproxy child orphaned
    # and holding the port, silently breaking every future run of this script.
    def handle_sigterm(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, handle_sigterm)

    try:
        while True:
            print("Connecting to iPad through iproxy...")
            sock = connect_with_retry()
            print("Connected. Streaming.")
            try:
                for norm_x, norm_y in stream_records(sock):
                    move_cursor(norm_x, norm_y)
            except (ConnectionResetError, OSError):
                pass
            finally:
                sock.close()
            print("Disconnected, retrying...")
            time.sleep(RECONNECT_DELAY)
    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        iproxy.terminate()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--display", type=int, default=None, help="Index into the printed display list")
    args = parser.parse_args()
    run(args.display)
