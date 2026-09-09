"""Adversarial TCP peer for the EXACT Swift production batch sender. macOS only."""
import socket, struct, subprocess, threading, time, sys
from pathlib import Path
harness = Path(__file__).resolve().parents[1] / 'build/network-harness'

def run(codes, expected, expected_loaded, final_delay=0):
    server = socket.socket()
    server.bind(('127.0.0.1', 0))
    server.listen()
    errors = []
    def peer():
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                def exact(n):
                    data = b''
                    while len(data) < n:
                        chunk = conn.recv(min(n - len(data), 4093))
                        assert chunk
                        data += chunk
                    return data
                assert exact(4) == b'IBAT'
                assert struct.unpack('<I', exact(4))[0] == 3
                for index, code in enumerate(codes):
                    length = struct.unpack('<I', exact(4))[0]
                    assert length == 300_000 + index
                    assert exact(length) == bytes([index + 1]) * length
                    conn.settimeout(.1)
                    try:
                        unexpected = conn.recv(1)
                        raise AssertionError(f'sent before ACK: {unexpected}')
                    except socket.timeout:
                        pass
                    conn.settimeout(3)
                    if code == "cancel":
                        assert conn.recv(1) == b''
                        break
                    if code is None:
                        break
                    if index == 2 and final_delay:
                        time.sleep(final_delay)
                    conn.sendall(bytes([code]))
                    if code:
                        assert conn.recv(1) == b''
                        break
        except BaseException as error:
            errors.append(error)
        finally:
            server.close()
    thread = threading.Thread(target=peer)
    thread.start()
    result = subprocess.run([str(harness), '--batch-local-test', str(server.getsockname()[1]), expected], capture_output=True, text=True, timeout=15 + final_delay)
    thread.join(5)
    assert not thread.is_alive()
    assert not errors, errors
    assert result.returncode == 0, result.stderr
    assert f'LOADED {expected_loaded}' in result.stdout, result.stdout

run([0,0,0], 'success', 3)
run([0,1], '1/3', 2)
run([0,0,2], '3/3', 3)
run([2], '0/3', 1)
run([255], '0/3', 1)
run([0,None], '1/3', 2)
run(['cancel'], '已取消', 1)
print('PASS: actual TCP production sender: ordered lazy loading, no bytes before ACK, failure stops, final ACK2, invalid ACK, disconnect partial count')

if "--preview-reserve" in sys.argv:
    run([0,0,0], "success", 3, final_delay=31)
    print("PASS: final ACK after 31 seconds succeeds within final 45-second operation budget")
