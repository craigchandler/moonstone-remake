#!/usr/bin/env python3
"""Two independent local players over real UDP; optional proxy adds bounded faults."""
from pathlib import Path
import argparse
import heapq
import json
import socket
import subprocess
import threading
import time
from build_support import ROOT, isolated_env, workspace


CASES = ['direct-leave', 'delayed-loss-client-exit', 'host-exit']
PROFILES = {
    'standard': {'delay_ms': 40, 'jitter_ms': 8, 'drop_every': 257, 'blackout_after': 0, 'blackout_for': 0},
    'stress': {'delay_ms': 100, 'jitter_ms': 40, 'drop_every': 17, 'blackout_after': 6, 'blackout_for': 0.8},
}


class FaultProxy:
    def __init__(self, port, server_port, profile='standard'):
        self.profile = PROFILES[profile]
        self.started = None
        self.blackout_dropped = 0
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('127.0.0.1', port))
        self.sock.setblocking(False)
        self.server = ('127.0.0.1', server_port)
        self.client = None
        self.pending = []
        self.count = self.dropped = 0
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        while not self.stop.is_set():
            try:
                payload, sender = self.sock.recvfrom(65536)
                if sender == self.server:
                    target = self.client
                else:
                    self.client = sender
                    target = self.server
                self.count += 1
                now = time.monotonic()
                if self.started is None:
                    self.started = now
                elapsed = now - self.started
                blackout = self.profile['blackout_after'] <= elapsed < self.profile['blackout_after'] + self.profile['blackout_for']
                if blackout or self.count % self.profile['drop_every'] == 0:
                    self.dropped += 1
                    self.blackout_dropped += int(blackout)
                elif target:
                    delay = (self.profile['delay_ms'] + (self.count % 5) * self.profile['jitter_ms'] / 4) / 1000
                    heapq.heappush(self.pending, (time.monotonic() + delay, self.count, payload, target))
            except BlockingIOError:
                pass
            while self.pending and self.pending[0][0] <= time.monotonic():
                _, _, payload, target = heapq.heappop(self.pending)
                self.sock.sendto(payload, target)
            time.sleep(0.0005)

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        self.sock.close()


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def verify(binary, directory, *, editor=False, graphical=False, only=None, profile='standard', rounds=2):
    if only is not None and only not in CASES:
        raise ValueError('Unknown network case: ' + only)
    if profile not in PROFILES or not 2 <= rounds <= 12:
        raise ValueError('Choose a known fault profile and 2 to 12 rounds.')
    directory.mkdir(parents=True, exist_ok=True)
    cases = [('direct-leave', False, 'guest', True), ('delayed-loss-client-exit', True, 'guest', False), ('host-exit', False, 'host', False)]
    reports = {}
    for name, delayed, drop, graceful in cases:
        if only and name != only:
            continue
        case = directory / name
        case.mkdir(parents=True, exist_ok=True)
        port = free_port()
        proxy = FaultProxy(free_port(), port, profile) if delayed else None
        if proxy:
            proxy.thread.start()
        processes, streams = {}, []
        try:
            for role in ['host', 'guest']:
                role_dir = case / role
                role_dir.mkdir(parents=True, exist_ok=True)
                command = [str(binary)]
                command += ['--display-driver', 'x11', '--rendering-method', 'gl_compatibility', '--resolution', '640x400', '--position', ('20,20' if role == 'host' else '700,20')] if graphical else ['--headless']
                # Fixed-fps is a synthetic clock and bypasses real pacing; peers need wall time.
                command += ['--audio-driver', 'Dummy', '--max-fps', '50']
                if editor:
                    command += ['--path', str(ROOT / 'game')]
                command += ['--', '--debug', '--network-role=' + role,
                            '--network-port=' + str(port if role == 'host' or not proxy else proxy.sock.getsockname()[1]),
                            '--network-result=' + str(role_dir / 'result.json'), '--network-drop=' + drop,
                            '--network-rounds=' + str(rounds)]
                if graceful:
                    command += ['--network-graceful']
                if graphical:
                    command += ['--network-capture=' + str(role_dir / 'captures')]
                stream = (role_dir / 'run.log').open('w')
                streams.append(stream)
                processes[role] = subprocess.Popen(command, cwd=ROOT, env=isolated_env(role_dir), stdout=stream, stderr=subprocess.STDOUT)
                if role == 'host':
                    time.sleep(0.2)
            deadline = time.monotonic() + max(65, rounds * 12 + 35)
            killed = False
            while time.monotonic() < deadline:
                if not graceful and not killed and read_json(case / drop / 'result.json').get('phase') == 'drop':
                    processes[drop].kill()
                    killed = True
                if all(process.poll() is not None for process in processes.values()):
                    break
                time.sleep(0.02)
            else:
                raise AssertionError(f'{name}: network process timeout; see {case}')
            rows = {role: read_json(case / role / 'result.json') for role in processes}
            for role, process in processes.items():
                assert rows[role] and not rows[role]['failures'], (name, role, rows[role])
                text = (case / role / 'run.log').read_text()
                assert 'ERROR:' not in text, (name, role, text[-2000:])
                if graceful or role != drop:
                    assert process.returncode == 0 and rows[role]['phase'] == 'complete' and 'PASS:' in text, (name, role, process.returncode, rows[role])
            assert rows['host']['rounds'] == rows['guest']['rounds'], (name, 'authoritative results differ', rows)
            assert set(rows['host']['rounds']) == {str(n) for n in range(1, rounds + 1)}, rows
            for number in range(1, rounds + 1):
                assert rows['host']['rounds'][str(number)]['outcome'] == ('victory' if number % 2 else 'defeat'), rows
            if proxy and profile == 'stress':
                assert proxy.blackout_dropped > 0, 'Stress run did not exercise the blackout'
            faults = {'profile': profile if delayed else 'direct',
                      'one_way_delay_ms': [proxy.profile['delay_ms'], proxy.profile['delay_ms'] + proxy.profile['jitter_ms']] if proxy else [0, 0],
                      'packets': proxy.count if proxy else 0, 'dropped': proxy.dropped if proxy else 0,
                      'blackout_dropped': proxy.blackout_dropped if proxy else 0}
            reports[name] = {'result': 'PASS', 'players': rows, 'faults': faults, 'drop': drop, 'graceful': graceful}
            print('PASS: independent UDP players / ' + name, flush=True)
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait()
            for stream in streams:
                stream.close()
            if proxy:
                proxy.close()
    (directory / 'result.json').write_text(json.dumps(reports, indent=2) + '\n')
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--editor', action='store_true')
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--case', choices=CASES)
    parser.add_argument('--profile', choices=PROFILES, default='standard')
    parser.add_argument('--rounds', type=int, choices=range(2, 13), default=2)
    args = parser.parse_args()
    verify(args.binary.resolve(), args.output or workspace('network-acceptance'), editor=args.editor, graphical=args.graphical, only=args.case, profile=args.profile, rounds=args.rounds)


if __name__ == '__main__':
    main()
