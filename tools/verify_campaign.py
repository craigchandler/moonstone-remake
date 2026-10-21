#!/usr/bin/env python3
"""Exercise real classic campaign clients with embedded and standalone authority."""
import argparse
import json
import subprocess
import time
from pathlib import Path
from build_support import ROOT, digest, isolated_env, workspace
from verify_network import FaultProxy, free_port, read_json


def verify(binary, directory, *, editor=False, graphical=False, server=None, fault=False):
    directory.mkdir(parents=True, exist_ok=True)
    port = free_port()
    proxies, processes, streams = [], [], []
    try:
        if server:
            stream = (directory / 'server.log').open('w');streams.append(stream)
            command = [str(server), '--headless']
            if editor:command += ['--path', str(ROOT / 'game'), 'res://server/duel_server.tscn']
            command += ['--', '--campaign', '--players', '2', '--port', str(port), '--seed', '12345', '--save', str(directory / 'campaign.json')]
            processes.append(subprocess.Popen(command, cwd=ROOT, env=isolated_env(directory / 'authority'), stdout=stream, stderr=subprocess.STDOUT))
            deadline = time.monotonic() + 10
            while 'MOONSTONE_CAMPAIGN_READY' not in (directory / 'server.log').read_text():
                if processes[0].poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('Campaign server did not start: ' + str(directory))
                time.sleep(0.02)
        clients = []
        for seat in range(2):
            role = directory / str(seat);role.mkdir()
            target = port
            if fault and (server or seat == 1):
                proxy = FaultProxy(free_port(), port, 'standard');proxy.thread.start();proxies.append(proxy)
                target = proxy.sock.getsockname()[1]
            command = [str(binary)]
            command += ['--display-driver', 'x11', '--rendering-method', 'gl_compatibility', '--resolution', '640x400', '--position', ('20,20' if seat == 0 else '700,20')] if graphical else ['--headless']
            command += ['--audio-driver', 'Dummy', '--max-fps', '50']
            if editor:command += ['--path', str(ROOT / 'game')]
            command += ['--', '--debug', '--campaign-role=' + str(seat), '--campaign-port=' + str(target), '--campaign-shared=' + str(directory), '--campaign-result=' + str(role / 'result.json')]
            if server:command += ['--campaign-dedicated']
            if graphical:command += ['--campaign-capture=' + str(role / 'captures')]
            stream = (role / 'run.log').open('w');streams.append(stream)
            client = subprocess.Popen(command, cwd=ROOT, env=isolated_env(role), stdout=stream, stderr=subprocess.STDOUT)
            processes.append(client);clients.append(client)
            time.sleep(0.3)
        deadline = time.monotonic() + 125
        while any(client.poll() is None for client in clients) and time.monotonic() < deadline:time.sleep(0.05)
        rows = [read_json(directory / str(seat) / 'result.json') for seat in range(2)]
        for seat, (client, row) in enumerate(zip(clients, rows)):
            log = (directory / str(seat) / 'run.log').read_text()
            if client.poll() != 0 or row.get('result') != 'PASS' or 'ERROR:' in log or 'PASS:' not in log:
                raise AssertionError(f'Campaign client {seat} failed: {row}; see {directory / str(seat) / "run.log"}')
        if server:
            log = (directory / 'server.log').read_text()
            if 'ERROR:' in log or processes[0].poll() is not None:raise AssertionError('Campaign server failed: ' + str(directory))
            saved = json.loads((directory / 'campaign.json').read_text())
            if saved['format'] != 'moonstone.network-campaign':raise AssertionError('No separate campaign save')
        result = {'result': 'PASS', 'hosting': 'standalone' if server else 'embedded', 'client_sha256': digest(binary), 'server_sha256': digest(server) if server else None, 'clients': rows, 'faults': [{'packets': p.count, 'dropped': p.dropped, 'delay_ms': p.profile['delay_ms']} for p in proxies], 'graphical': graphical, 'scope': 'Two independent processes on local UDP; scripted ordinary menu/input; Windows and separate-PC LAN execution NOT_RUN'}
        (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print('PASS: real campaign clients, ' + result['hosting'] + ' host: ' + str(directory), flush=True)
        return directory / 'result.json'
    finally:
        for process in processes:
            if process.poll() is None:process.terminate()
        for process in processes:
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        for proxy in proxies:proxy.close()
        for stream in streams:stream.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--server', type=Path)
    parser.add_argument('--editor', action='store_true')
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--fault', action='store_true')
    args = parser.parse_args()
    verify(args.binary.resolve(), workspace('campaign-runtime'), editor=args.editor, graphical=args.graphical, server=args.server.resolve() if args.server else None, fault=args.fault)
