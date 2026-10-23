from pathlib import Path
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from import_parallel import run_lanes
from portmaster_import import STAGES, PARALLEL_LANES, AFTER_LANES
from import_worker import warm_modules, start_converter


class ParallelImportTests(unittest.TestCase):
    def command(self, code, label):
        return [sys.executable,'-c',code],label

    def test_disjoint_lanes_overlap_but_dependencies_stay_ordered(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            first="""from pathlib import Path
import time
Path('first').write_text('ready')
deadline=time.monotonic()+3
while not Path('second').exists():
    assert time.monotonic()<deadline, 'lanes did not overlap'
    time.sleep(.01)
Path('done').write_text('ready')
"""
            lanes=[[self.command(first,'first'),self.command("from pathlib import Path; assert Path('done').exists(); Path('dependent').touch()",'dependent')],
                   [self.command("from pathlib import Path; Path('second').touch()",'second')]]
            rows,usage=run_lanes(lanes,root,os.environ.copy(),root/'logs',lambda *_:None,workers=2)
            self.assertTrue((root/'dependent').exists())
            self.assertEqual({r['stage'] for r in rows},{'first','second','dependent'})
            self.assertGreaterEqual(usage['cpu_seconds'],0)

    def test_failure_stops_other_lane_and_never_starts_dependent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            sleeper="from pathlib import Path; import os,time; Path('pid').write_text(str(os.getpid())); time.sleep(60)"
            failure="""from pathlib import Path
import time
deadline=time.monotonic()+3
while not Path('pid').exists():
    assert time.monotonic()<deadline
    time.sleep(.01)
raise SystemExit(7)
"""
            lanes=[[self.command(sleeper,'sleep'),self.command("from pathlib import Path; Path('bad').touch()",'dependent')],
                   [self.command(failure,'failure')]]
            with self.assertRaisesRegex(RuntimeError,'failure failed'):
                run_lanes(lanes,root,os.environ.copy(),root/'logs',lambda *_:None,workers=2)
            self.assertFalse((root/'bad').exists())
            with self.assertRaises(ProcessLookupError):os.kill(int((root/'pid').read_text()),0)

    def test_interruption_stops_all_started_converters(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            lanes=[[self.command(f"from pathlib import Path; import os,time; Path('pid{n}').write_text(str(os.getpid())); time.sleep(60)",str(n))] for n in range(2)]
            def cancel(*_):
                if (root/'pid0').exists() and (root/'pid1').exists():raise InterruptedError('cancelled')
            with self.assertRaises(InterruptedError):run_lanes(lanes,root,os.environ.copy(),root/'logs',cancel,workers=2)
            for n in range(2):
                with self.assertRaises(ProcessLookupError):os.kill(int((root/f'pid{n}').read_text()),0)

    def test_plan_covers_each_stage_once_and_keeps_shared_outputs_ordered(self):
        self.assertEqual(sorted(sum(PARALLEL_LANES,[])+AFTER_LANES+[31,32]),list(range(len(STAGES))))
        combat=[STAGES[i][0] for i in PARALLEL_LANES[0]]
        self.assertLess(combat.index('death_frames'),combat.index('hit_recovery'))
        self.assertLess(combat.index('hit_recovery'),combat.index('ratman_tree'))
        world=[STAGES[i][0] for i in PARALLEL_LANES[1]]
        ending=[STAGES[i][0] for i in PARALLEL_LANES[2]]
        self.assertLess(world.index('world_art'),world.index('map_locations'))
        self.assertLess(ending.index('ending_opening'),ending.index('ending_complete'))

    def test_warm_workers_isolate_modules_and_cancel_helper_groups(self):
        import signal
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            helper=root/'helper.pid'
            ready=root/'ready'
            script=root/'converter.py'
            script.write_text("import subprocess,sys,time\nfrom pathlib import Path\n"
                "p=subprocess.Popen([sys.executable,'-c',\"import time;time.sleep(60)\"])\n"
                f"Path({str(helper)!r}).write_text(str(p.pid))\nPath({str(ready)!r}).touch()\n"
                "try:p.wait()\nfinally:p.terminate();p.wait()\n")
            env=os.environ|{'MOONSTONE_IMPORT_WARM_WORKERS':'1'}
            warm_modules()
            def cancel(*_):
                if ready.exists():raise InterruptedError('cancel test')
            with self.assertRaises(InterruptedError):
                run_lanes([[([sys.executable,str(script)],'warm')]],root,env,root/'logs',cancel)
            # The native helper may briefly remain a zombie awaiting init's
            # reap, but must no longer be executing after group cancellation.
            pid=int(helper.read_text())
            stat=Path('/proc')/str(pid)/'stat'
            if stat.exists():self.assertEqual(stat.read_text().split()[2],'Z')

    def test_cancellation_before_warm_worker_registration_reaps_child(self):
        import multiprocessing
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);script=root/'wait.py';script.write_text('import time;time.sleep(60)\n')
            before={p.pid for p in multiprocessing.active_children()}
            with (root/'log').open('w') as log, patch('import_worker.os.read',side_effect=InterruptedError('early cancel')):
                with self.assertRaises(InterruptedError):
                    start_converter([sys.executable,str(script)],root,
                                    os.environ|{'MOONSTONE_IMPORT_WARM_WORKERS':'1'},log)
            self.assertEqual({p.pid for p in multiprocessing.active_children()},before)


if __name__=='__main__':unittest.main()
