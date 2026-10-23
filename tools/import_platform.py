"""OS boundaries for the packaged importer; no game or conversion policies."""
from contextlib import contextmanager
import os
import signal
import subprocess


@contextmanager
def installation_lock(path):
    with path.open('a+b') as stream:
        if os.name == 'nt':
            import msvcrt
            if path.stat().st_size == 0:
                stream.write(b'0');stream.flush()
            stream.seek(0)
            try:msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as error:raise ValueError('Another content import is already running') from error
        else:
            import fcntl
            try:fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:raise ValueError('Another content import is already running') from error
        try:yield
        finally:
            if os.name == 'nt':
                stream.seek(0);msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)


def child_usage():
    if os.name == 'nt':return None
    import resource
    return resource.getrusage(resource.RUSAGE_CHILDREN)


def usage_delta(before):
    after = child_usage()
    if before is None or after is None:
        return {'cpu_seconds': None, 'major_page_faults': None}
    return {'cpu_seconds': round(after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime, 3),
            'major_page_faults': after.ru_majflt - before.ru_majflt}


def process_options():
    return ({'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == 'nt'
            else {'start_new_session': True})


def stop_group(process, force=False):
    if os.name == 'nt':
        # The converter owns its helper processes. Kill the entire tree, not
        # just Python, before its incomplete workspace is removed.
        if process.poll() is None:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    else:
        try:os.killpg(process.pid, signal.SIGKILL if force else signal.SIGTERM)
        except ProcessLookupError:pass


def engine_command(engine, pack, arguments=(), *, headless=True):
    """Official desktop templates use adjacent PCKs; PortMaster allows overrides."""
    command = [engine]
    if headless:command += ['--headless', '--audio-driver', 'Dummy']
    if os.environ.get('MOONSTONE_ENGINE_PACK_MODE') != 'adjacent':
        command += ['--main-pack', pack]
    if arguments:command += ['--', *arguments]
    return command
