"""Bounded converter lanes with ordered dependencies and group cancellation."""
from collections import deque
from pathlib import Path
import os
import signal
import subprocess
import time
from import_worker import start_converter
from import_platform import child_usage, usage_delta, stop_group


def run_lanes(lanes, cwd, env, log_folder, report, workers=3):
    """Run disjoint lanes concurrently, preserving every lane's internal order.

    report receives active labels and completed result rows. Each subprocess has
    its own log and status file; only this coordinator updates the visible UI.
    A failure or cancellation terminates all active converter process groups,
    including native audio helpers, before the caller removes temporary files.
    """
    if workers < 1:raise ValueError('At least one converter worker is required')
    queues = [deque(lane) for lane in lanes]
    active = {}
    completed = []
    log_folder = Path(log_folder)
    log_folder.mkdir(parents=True, exist_ok=True)
    usage_before = child_usage()
    started = time.monotonic()
    last_report = float('-inf')
    serial = 0
    try:
        while active or any(queues):
            for lane, queue in enumerate(queues):
                if len(active) >= workers:break
                if not queue or lane in active:continue
                command, label = queue.popleft()
                path = log_folder / f'{serial:02d}.log'
                status = log_folder / f'{serial:02d}.json'
                serial += 1
                child_env = env | {'MOONSTONE_IMPORT_STATUS': str(status)}
                status.write_text('{"state":"running"}\n')
                stream = path.open('w')
                try:
                    process = start_converter(command,cwd,child_env,stream)
                except BaseException:
                    stream.close()
                    raise
                active[lane] = (process, stream, label, path, time.monotonic(), status)
            finished = False
            for lane, (process, stream, label, path, began, status) in list(active.items()):
                code = process.poll()
                if code is None:continue
                stream.close()
                row = {'stage': label, 'seconds': round(time.monotonic()-began, 3),
                       'log': str(path), 'exit': code}
                completed.append(row)
                if code:
                    raise RuntimeError(label + ' failed. Details: ' + str(path))
                del active[lane]
                finished = True
            now = time.monotonic()
            if finished or now-last_report >= 0.5:
                report([(entry[2], entry[5]) for entry in active.values()], completed)
                last_report = now
            if active:time.sleep(0.02)
        return completed, {'seconds': round(time.monotonic()-started, 3),
                           **usage_delta(usage_before), 'workers': workers}
    finally:
        for process, stream, *_ in active.values():
            stop_group(process)
        deadline = time.monotonic()+5
        for process, stream, *_ in active.values():
            try:process.wait(timeout=max(0, deadline-time.monotonic()))
            except subprocess.TimeoutExpired:
                stop_group(process, force=True)
                process.wait()
            stream.close()
