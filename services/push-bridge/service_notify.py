"""Minimal systemd readiness: consumer registration, never provider delivery."""
import os
import socket


def notify_consumer_ready():
    notify_status(True)


def notify_status(ready):
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = "\0" + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as connection:
        connection.settimeout(1)
        connection.connect(address)
        connection.sendall(b"READY=1\nSTATUS=AMQP consumer registered; mobile delivery not verified"
                           if ready else b"STATUS=AMQP consumer disconnected")
