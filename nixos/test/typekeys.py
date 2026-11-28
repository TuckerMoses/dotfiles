#!/usr/bin/env python3
"""Type a line on a QEMU guest's keyboard through the monitor socket.

    typekeys.py <monitor.sock> <text>

For guests whose console is on the screen, not the serial port (the x86-64
installer). Enough of a US keymap for shell commands.
"""
import socket
import sys
import time

NAMES = {
    " ": "spc", "-": "minus", "=": "equal", ".": "dot", ",": "comma", "/": "slash",
    ";": "semicolon", "'": "apostrophe", "\\": "backslash", "[": "bracket_left",
    "]": "bracket_right", "`": "grave_accent", "\n": "ret",
}
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "minus", "+": "equal", ":": "semicolon", '"': "apostrophe",
    "<": "comma", ">": "dot", "?": "slash", "|": "backslash", "~": "grave_accent",
    "{": "bracket_left", "}": "bracket_right",
}


def key(ch):
    if ch in NAMES:
        return NAMES[ch]
    if ch in SHIFTED:
        return "shift-" + SHIFTED[ch]
    if ch.isupper():
        return "shift-" + ch.lower()
    if ch.isalnum():
        return ch
    raise SystemExit(f"no key for {ch!r}")


def main():
    path, text = sys.argv[1], sys.argv[2]
    s = socket.socket(socket.AF_UNIX)
    s.connect(path)
    for ch in text + "\n":
        s.sendall(f"sendkey {key(ch)}\n".encode())
        time.sleep(0.08)
    time.sleep(0.5)
    s.close()


if __name__ == "__main__":
    main()
