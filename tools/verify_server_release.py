#!/usr/bin/env python3
"""Accept a real exported Linux server using art-free shared protocol clients."""
import json
import signal
import subprocess
import time
from pathlib import Path
from build_support import ROOT, artifact_path, digest, godot_binary, config, isolated_env, run, workspace
from build_server import stage
from verify_server import cli_checks
from verify_network import free_port


def verify_campaign_server(binary, editor, project, directory, env, root):
    rows = []
    port = free_port()
    for attempt in range(2):
        log = directory / f'campaign-server-{attempt}.log'
        with log.open('w') as stream:
            server = subprocess.Popen([str(binary), '--headless', '--', '--campaign', '--players', '4', '--port', str(port), '--seed', '12345', '--save', str(directory / 'campaign.json')], cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 10
                while 'MOONSTONE_CAMPAIGN_READY' not in log.read_text():
                    if server.poll() is not None or time.monotonic() >= deadline:raise RuntimeError('Exported campaign host did not start: ' + str(log))
                    time.sleep(0.02)
                command = [editor, '--headless', '--path', project, '--script', root / 'game/tests/server_campaign_probe.gd', '--', port, directory]
                if attempt:command += ['--resume']
                text = run(command, directory / f'campaign-clients-{attempt}.log', env=env, timeout=60)
                row = json.loads((directory / ('campaign-resume.json' if attempt else 'campaign-clients.json')).read_text())
                if row['result'] != 'PASS' or 'PASS:' not in text or server.poll() is not None or 'ERROR:' in log.read_text():raise ValueError('Campaign exported host acceptance failed.')
                rows.append(row)
            finally:
                if server.poll() is None:server.send_signal(signal.SIGINT)
                try:server.wait(timeout=5)
                except subprocess.TimeoutExpired:server.kill();server.wait()
        time.sleep(0.2)
    if rows[0]['room'] != rows[1]['room'] or not rows[1]['resumed_saved_room']:raise ValueError('Campaign restart lost its saved room.')
    return {'result': 'PASS', 'runs': rows, 'scope': 'Exported Linux standalone server, four asset-free clients, classic turns, map agreement, personal inventory, disconnect/reconnect and process restart from saved reserved room.'}


def verify(root=ROOT):
    report = json.loads((root / 'outputs/duel-server-build-manifest.json').read_text())
    linux = next(row for row in report['builds'] if row['platform'] == 'Linux')
    binary = artifact_path(root, linux['file'])
    if digest(binary) != linux['sha256']:
        raise ValueError('Server executable has changed since export.')
    editor, _ = godot_binary(config(root), root)
    directory = workspace('server-release-check', root)
    project = directory / 'project'
    project.mkdir()
    compatibility, names = stage(project, root)
    if any(name.startswith(('assets/', 'content/generated/')) for name in names):
        raise ValueError('Server must build from source gameplay definitions only.')
    campaign_hash = json.loads((project / 'content/campaign_compatibility.json').read_text())['digest']
    if report.get('campaign_compatibility') != campaign_hash:
        raise ValueError('Campaign server export does not match current source.')
    if report['compatibility'] != compatibility['digest']:
        raise ValueError('Server export does not match current gameplay source.')
    env = isolated_env(directory)
    env.pop('DISPLAY', None); env.pop('WAYLAND_DISPLAY', None)
    run([editor, '--headless', '--editor', '--path', project, '--import'], directory / 'import.log', env=env, allow_editor_socket_errors=True, timeout=180)
    for name in ['test_network_duel.gd', 'test_duel_host.gd', 'test_campaign_session.gd', 'test_campaign_host.gd']:
        text = run([editor, '--headless', '--path', project, '--script', root / 'game/tests' / name], directory / (name + '.log'), env=env, timeout=60)
        if 'PASS:' not in text:
            raise ValueError('Source protocol suite did not complete: ' + name)
    cli = cli_checks(binary, directory / 'cli')
    text = run([binary, '--', '--version'], directory / 'version.log', env=env)
    if f"server {report['version']} protocol=2 combat={report['compatibility']}" not in text:
        raise ValueError('Exported release identity does not match source.')
    port = free_port()
    log = directory / 'server.log'
    with log.open('w') as stream:
        server = subprocess.Popen([str(binary), '--headless', '--', '--port', str(port)], cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while 'MOONSTONE_SERVER_READY' not in log.read_text():
                if server.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Exported server did not start: ' + str(log))
                time.sleep(0.02)
            text = run([editor, '--headless', '--path', project, '--script', root / 'game/tests/server_protocol_probe.gd', '--', port, directory / 'clients.json'], directory / 'clients.log', env=env, timeout=80)
            clients = json.loads((directory / 'clients.json').read_text())
            if clients['result'] != 'PASS' or 'PASS:' not in text or server.poll() is not None:
                raise ValueError('Exported server protocol acceptance failed.')
            server_text = log.read_text()
            for number, row in clients['rounds'].items():
                if f"round={number} tick={row['tick']} hash={row['hash']} outcome={row['outcome']}" not in server_text:
                    raise ValueError('Client terminal snapshot differs from server authority.')
            if 'ERROR:' in server_text or 'display=headless' not in server_text:
                raise ValueError('Server emitted errors or used a display.')
        finally:
            if server.poll() is None:server.send_signal(signal.SIGINT)
            try:server.wait(timeout=5)
            except subprocess.TimeoutExpired:server.kill();server.wait()
    campaign = verify_campaign_server(binary, editor, project, directory, env, root)
    result = {'campaign': campaign, 'campaign_compatibility': campaign_hash, 'result': 'PASS', 'kind': 'server-protocol-release', 'server_sha256': digest(binary), 'compatibility': report['compatibility'], 'version': report['version'], 'cli': cli, 'clients': clients, 'scope': 'Linux exported duel/campaign server with two duel and four campaign asset-free clients on local UDP; graphical game, separate-PC LAN and Windows execution NOT_RUN'}
    accepted = directory / 'result.json'
    accepted.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: asset-free source suites and exported Linux server acceptance: ' + str(accepted.relative_to(root)), flush=True)
    return accepted


if __name__ == '__main__':
    verify()
