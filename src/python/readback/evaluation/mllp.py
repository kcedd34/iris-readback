"""A minimal MLLP sender for the evaluation: one connection, the acknowledgement code of every message.

The inbound TCP service handles one connection at a time per worker, and a connection that is opened and closed without sending
anything leaves the next connection unanswered. Every message of a run goes on one connection, and no empty connection is opened as
a readiness check. A reset before the first acknowledgement is retried on a new connection; a later reset is a real failure.
"""
import os
import socket
import time

START, END = b"\x0b", b"\x1c\r"


def connect(host, port, attempts=20, delay=1.0):
    last = None
    for _ in range(attempts):
        try:
            return socket.create_connection((host, port), timeout=30)
        except OSError as error:
            last = error
            time.sleep(delay)
    raise last


def read_ack(conn):
    reply = b""
    while not reply.endswith(END):
        chunk = conn.recv(4096)
        if not chunk:
            break
        reply += chunk
    for segment in reply.strip(b"\x0b\x1c\r").split(b"\r"):
        if segment.startswith(b"MSA"):
            return segment.decode().split("|")[1]
    return "NOACK"


def send_many(messages, host="127.0.0.1", port=int(os.environ.get("READBACK_HL7_PORT") or 5001), progress=None):
    """messages: list of (id, text). Returns a list of (id, acknowledgement code), in order."""
    results = []
    conn = connect(host, port)
    try:
        for message_id, text in messages:
            data = START + text.encode("ascii", "replace") + END
            for attempt in range(6):
                try:
                    conn.sendall(data)
                    results.append((message_id, read_ack(conn)))
                    break
                except (ConnectionResetError, BrokenPipeError):
                    if results or attempt == 5:
                        raise
                    conn.close()
                    time.sleep(3)
                    conn = connect(host, port)
            if progress:
                progress(len(results), len(messages))
    finally:
        conn.close()
    return results
