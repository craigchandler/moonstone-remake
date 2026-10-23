"""Fast, isolated offline workers; no change to decoded pixels or game rules."""
from pathlib import Path
import os
import runpy
import signal
import subprocess
import sys
import time
import traceback
from import_platform import process_options


def warm_modules():
    # Load pure dependencies once before forking. Never preload converters:
    # several of those intentionally read current output at module import time.
    previous=os.environ.get('OPENBLAS_NUM_THREADS')
    os.environ['OPENBLAS_NUM_THREADS']='1'
    try:import numpy
    finally:
        if previous is None:os.environ.pop('OPENBLAS_NUM_THREADS',None)
        else:os.environ['OPENBLAS_NUM_THREADS']=previous
    from PIL import Image, PngImagePlugin
    import json, hashlib, struct, re, argparse, copy


def execute(script, arguments):
    script = Path(script).resolve()
    sys.path.insert(0,str(script.parent))
    project = Path.cwd()
    sys.path.insert(0,str(project/'work/upstream/moonstone-ace/tools'))
    from PIL import Image, PngImagePlugin
    save_png = PngImagePlugin._save
    def fast_png(image, stream, filename, **kwargs):
        # These images are temporary inputs to native resource packing. Lower
        # compression changes storage size, never pixels, indices or palettes.
        image.encoderinfo['compress_level'] = 1
        image.encoderinfo['optimize'] = False
        return save_png(image,stream,filename,**kwargs)
    Image.register_save('PNG',fast_png)
    import import_accel
    if import_accel.library():
        import artconv
        artconv.lzss_decode = import_accel.lzss_decode
    sys.argv = [str(script),*map(str,arguments)]
    if script.name == 'artconv.py':
        import artconv
        artconv.main()
    else:
        runpy.run_path(str(script),run_name='__main__')


class ForkedConverter:
    """Small Popen-compatible wrapper around an isolated, preloaded worker."""
    def __init__(self,command,cwd,env,stdout):
        import multiprocessing
        ready, notify = os.pipe()
        def child():
            os.close(ready)
            os.setsid()
            signal.signal(signal.SIGTERM,signal.SIG_DFL)
            signal.signal(signal.SIGINT,signal.SIG_DFL)
            os.dup2(stdout.fileno(),1);os.dup2(stdout.fileno(),2)
            os.chdir(cwd)
            os.environ.clear();os.environ.update(env)
            os.write(notify,b'1');os.close(notify)
            code=0
            try:execute(command[1],command[2:])
            except SystemExit as error:
                code=error.code if isinstance(error.code,int) else (1 if error.code else 0)
                if error.code and not isinstance(error.code,int):print(error.code,file=sys.stderr)
            except BaseException:
                traceback.print_exc();code=1
            finally:
                sys.stdout.flush();sys.stderr.flush()
            raise SystemExit(code)
        self.process=multiprocessing.get_context('fork').Process(target=child)
        try:
            self.process.start()
            os.close(notify);notify=-1
            if os.read(ready,1)!=b'1':
                self.process.join()
                raise RuntimeError('Converter failed before creating its process group')
        except BaseException:
            # Cancellation can arrive before the coordinator has received this
            # object. Reap that not-yet-registered worker here, including helpers
            # if it already reached execute().
            if self.process.pid is not None:
                try:os.killpg(self.process.pid,signal.SIGKILL)
                except ProcessLookupError:
                    try:os.kill(self.process.pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                self.process.join()
            raise
        finally:
            os.close(ready)
            if notify>=0:os.close(notify)
        self.pid=self.process.pid

    def poll(self):
        code=self.process.exitcode
        if code is not None:self.process.join()
        return code

    def wait(self,timeout=None):
        self.process.join(timeout)
        if self.process.exitcode is None:raise subprocess.TimeoutExpired('converter',timeout)
        return self.process.exitcode


def start_converter(command,cwd,env,stdout):
    command=list(map(str,command))
    if (env.get('MOONSTONE_IMPORT_WARM_WORKERS')=='1' and hasattr(os,'fork')
            and len(command)>1 and command[0]==sys.executable and command[1].endswith('.py')):
        return ForkedConverter(command,cwd,env,stdout)
    if len(command)>1 and command[0]==sys.executable and command[1].endswith('.py'):
        command=[sys.executable,str(Path(__file__).resolve()),*command[1:]]
    return subprocess.Popen(command,cwd=cwd,env=env,stdout=stdout,
                            stderr=subprocess.STDOUT,**process_options())


if __name__=='__main__':
    execute(sys.argv[1],sys.argv[2:])
