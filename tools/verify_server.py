#!/usr/bin/env python3
"""Three-process dedicated duel acceptance, room reuse, faults and server loss."""
from pathlib import Path
import argparse
import json
import signal
import subprocess
import time
from build_support import ROOT, digest, isolated_env, workspace
from verify_network import FaultProxy, free_port, read_json


def clients(binary, directory, port, *, editor=False, graphical=False, profile=None, drop='guest', graceful=True, stop_server=None):
    proxies, processes, streams = [], {}, []
    try:
        for role in ['host', 'guest']:
            target_port = port
            if profile:
                proxy = FaultProxy(free_port(), port, profile)
                proxy.thread.start()
                proxies.append(proxy)
                target_port = proxy.sock.getsockname()[1]
            case = directory / role
            case.mkdir(parents=True, exist_ok=True)
            command = [str(binary)]
            command += ['--display-driver', 'x11', '--rendering-method', 'gl_compatibility', '--resolution', '640x400'] if graphical else ['--headless']
            command += ['--audio-driver', 'Dummy', '--max-fps', '50']
            if editor:
                command += ['--path', str(ROOT / 'game')]
            command += ['--', '--debug', '--network-dedicated', '--network-role=' + role, '--network-port=' + str(target_port),
                        '--network-drop=' + drop, '--network-result=' + str(case / 'result.json')]
            if graphical:
                command += ['--network-capture=' + str(case / 'captures')]
            if graceful:
                command += ['--network-graceful']
            stream = (case / 'run.log').open('w')
            streams.append(stream)
            processes[role] = subprocess.Popen(command, cwd=ROOT, env=isolated_env(case), stdout=stream, stderr=subprocess.STDOUT)
            (case / 'launch.json').write_text(json.dumps({'command': command, 'pid': processes[role].pid}, indent=2) + '\n')
            if role == 'host':
                # Wait for seat1 rather than relying on process startup ordering.
                # Include client resource/shader startup in this first-seat budget.
                deadline = time.monotonic() + 30
                while read_json(case / 'result.json').get('phase') != 'seated':
                    if processes[role].poll() is not None or time.monotonic() >= deadline:
                        raise AssertionError('First dedicated client did not receive a seat: ' + str(case) + '; exit=' + str(processes[role].poll()) + '; report=' + str(read_json(case / 'result.json')))
                    time.sleep(0.02)
        deadline = time.monotonic() + 70
        dropped = False
        while time.monotonic() < deadline:
            if not graceful and not dropped and read_json(directory / drop / 'result.json').get('phase') == 'drop':
                if stop_server:
                    stop_server()
                else:
                    processes[drop].kill()
                dropped = True
            if all(p.poll() is not None for p in processes.values()):
                break
            time.sleep(0.02)
        else:
            raise AssertionError('Dedicated client timeout: ' + str(directory))
        rows = {role: read_json(directory / role / 'result.json') for role in processes}
        for role, process in processes.items():
            row = rows[role]
            text = (directory / role / 'run.log').read_text()
            assert row and not row['failures'] and not row['hosting'] and not row['authoritative'], (role, row)
            assert row['local_actor'] == (1 if role == 'host' else 2), row
            assert 'ERROR:' not in text, text[-3000:]
            if graceful or role != drop or stop_server:
                assert process.returncode == 0 and row['phase'] == 'complete' and 'PASS:' in text, row
        assert rows['host']['rounds'] == rows['guest']['rounds'], rows
        assert set(rows['host']['rounds']) == {'1', '2'}, rows
        assert rows['host']['rounds']['1']['outcome'] == 'victory' and rows['host']['rounds']['2']['outcome'] == 'defeat', rows
        faults = [{'packets': p.count, 'dropped': p.dropped, 'blackout_dropped': p.blackout_dropped} for p in proxies]
        if profile == 'stress':
            assert all(p.blackout_dropped > 0 for p in proxies), faults
        print('PASS: dedicated two-client real combat / ' + directory.name, flush=True)
        return {'result': 'PASS', 'players': rows, 'faults': faults, 'profile': profile or 'direct'}
    finally:
        for p in processes.values():
            if p.poll() is None:
                p.kill()
            p.wait()
        for stream in streams:
            stream.close()
        for proxy in proxies:
            proxy.close()



def cli_checks(binary, directory):
    directory.mkdir(parents=True, exist_ok=True)
    env = isolated_env(directory)
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    for name, args, code in [('help', ['--help'], 0), ('zero-port', ['--port', '0'], 2),
                             ('large-port', ['--port=65536'], 2), ('bad-port', ['--port', 'abc'], 2),
                             ('unknown', ['--unknown'], 2), ('campaign-zero-humans', ['--campaign', '--players', '0'], 2),
                             ('campaign-too-many', ['--campaign', '--players=5'], 2), ('campaign-bad-seed', ['--campaign', '--seed=-1'], 2)]:
        result = subprocess.run([str(binary), '--', *args], cwd=ROOT, env=env, text=True, capture_output=True, timeout=10)
        text = result.stdout + result.stderr
        (directory / (name + '.log')).write_text(text)
        assert result.returncode == code and 'MOONSTONE_SERVER_READY' not in text, (name, result.returncode, text)
    log = directory / 'interrupt.log'
    with log.open('w') as stream:
        process = subprocess.Popen([str(binary), '--', '--port', str(free_port())], cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while 'MOONSTONE_SERVER_READY' not in log.read_text():
                assert process.poll() is None and time.monotonic() < deadline, log.read_text()
                time.sleep(0.02)
            assert 'display=headless' in log.read_text()
            process.send_signal(signal.SIGINT)
            process.wait(timeout=5)
            assert process.returncode in [0, -signal.SIGINT, 130], process.returncode
            assert 'ERROR:' not in log.read_text(), log.read_text()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
    print('PASS: server CLI help, invalid arguments, headless startup and Ctrl+C', flush=True)
    return {'result': 'PASS', 'checks': 9}


def wait_for_room(log, server, resets):
    # A remote timeout can finish before the host sees the same lost peer.
    # Wait for its reset, then the host's documented 100ms notification grace.
    deadline = time.monotonic() + 7
    marker = 'MOONSTONE_SERVER_STATE state=listening players=0'
    while log.read_text().count(marker) < resets + 1:
        assert server.poll() is None and time.monotonic() < deadline, log.read_text()[-2000:]
        time.sleep(0.02)
    time.sleep(0.2)


def verify(server_binary, client_binary, directory, *, editor=False, graphical=False):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    port = free_port()
    server_dir = directory / 'server'
    server_dir.mkdir()
    environment = isolated_env(server_dir)
    # A real CLI server must start without any display or player settings.
    environment.pop('DISPLAY', None)
    environment.pop('WAYLAND_DISPLAY', None)
    log = server_dir / 'run.log'
    reports = {'cli': cli_checks(server_binary, directory / 'cli')}
    with log.open('w') as stream:
        server = subprocess.Popen([str(server_binary), '--headless', '--', '--port', str(port)], cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while 'MOONSTONE_SERVER_READY' not in log.read_text():
                if server.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError('Dedicated server did not start headlessly: ' + log.read_text())
                time.sleep(0.02)
            assert 'display=headless' in log.read_text()
            reports['direct-leave'] = clients(client_binary, directory / 'direct-leave', port, editor=editor, graphical=graphical)
            assert server.poll() is None
            wait_for_room(log, server, 1)
            # Reuse the same listening process after both former players left.
            reports['reuse-delayed-loss'] = clients(client_binary, directory / 'reuse-delayed-loss', port, editor=editor, profile='stress', graceful=False)
            assert server.poll() is None
            wait_for_room(log, server, 2)
            reports['server-exit'] = clients(client_binary, directory / 'server-exit', port, editor=editor, drop='host', graceful=False, stop_server=server.kill)
            assert server.poll() is not None
            text = log.read_text()
            assert 'ERROR:' not in text, text[-3000:]
            for report in reports.values():
                if 'players' not in report:
                    continue
                for number, round_data in report['players']['host']['rounds'].items():
                    expected = f"round={number} tick={round_data['tick']} hash={round_data['hash']} outcome={round_data['outcome']}"
                    assert expected in text, ('server/client terminal state differs', expected)
        finally:
            if server.poll() is None:
                server.send_signal(signal.SIGINT)
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
            server.wait()
    result = {'result': 'PASS', 'server_sha256': digest(server_binary), 'client_sha256': digest(client_binary), 'cases': reports, 'server_display': 'headless', 'scope': 'same-machine real UDP; no separate-PC, Windows or internet claim'}
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--editor', action='store_true')
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    verify(args.server.resolve(), args.client.resolve(), args.output or workspace('server-acceptance'), editor=args.editor, graphical=args.graphical)


if __name__ == '__main__':
    main()
