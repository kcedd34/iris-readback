"""Sends HL7 messages over one MLLP connection and prints the acknowledgement code of each.

The inbound TCP service handles one connection at a time per worker, and a connection that is
opened and closed without sending anything leaves the next connection unanswered. Send every
message of a batch on one connection, and never open an empty connection as a readiness check.
"""
import socket
import sys
import time

START, END = b"\x0b", b"\x1c\r"


def connect(host, port, attempts=20, delay=1.0):
    last = None
    for _ in range(attempts):
        try:
            return socket.create_connection((host, port), timeout=20)
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


def send_many(paths, host="127.0.0.1", port=5001):
    """Returns a list of (path, ack code) using a single connection.

    A connection opened soon after another one closed can be reset before anything is acknowledged. That is
    retried on a fresh connection, only until the first acknowledgement; later resets are real failures.
    """
    results = []
    conn = connect(host, port)
    try:
        for path in paths:
            with open(path, "rb") as handle:
                data = START + handle.read() + END
            for attempt in range(6):
                try:
                    conn.sendall(data)
                    results.append((path, read_ack(conn)))
                    break
                except (ConnectionResetError, BrokenPipeError):
                    if results or attempt == 5:
                        raise
                    conn.close()
                    time.sleep(3)
                    conn = connect(host, port)
    finally:
        conn.close()
    return results


if __name__ == "__main__":
    for file_path, code in send_many(sys.argv[1:]):
        print(file_path, code)
