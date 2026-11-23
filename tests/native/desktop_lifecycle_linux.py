#!/usr/bin/env python3
"""Test actual windows, not just mocked APIs.

Requires Linux, Go, GTK3/WebKit2GTK 4.1, Xvfb, Openbox, xdotool, and xwd.
Usage: dbus-run-session -- python3 tests/native/desktop_lifecycle_linux.py --out /tmp/bookstark-lifecycle
All application profiles, binaries, logs and screenshots are isolated in --out.
"""
import os, subprocess, time, json, pathlib, traceback
import argparse, shutil, sys
parser = argparse.ArgumentParser(description='Real Linux window lifecycle regression (run under dbus-run-session).')
parser.add_argument('--source', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
parser.add_argument('--out', type=pathlib.Path, required=True)
args = parser.parse_args()
ROOT = args.out.resolve()
SOURCE = args.source.resolve()
ROOT.mkdir(parents=True, exist_ok=True)
for executable in ('go', 'Xvfb', 'openbox', 'xdotool', 'xwd'):
    if not shutil.which(executable):
        raise SystemExit('Missing dependency: ' + executable)
if not os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
    raise SystemExit('Run this script under dbus-run-session.')
env = dict(os.environ, WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS='1', WEBKIT_DISABLE_COMPOSITING_MODE='1', GOMAXPROCS='2', GOMEMLIMIT='400MiB', CGO_ENABLED='0')
subprocess.run(['go', 'test', '-c', '-p=1', '-tags', 'wails,production,gtk3,purego', '-o', str(ROOT / 'retained.test'), '.'], cwd=str(SOURCE), env=env, check=True)
read_fd, write_fd = os.pipe()
xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1440x1000x24', '-ac'], pass_fds=(write_fd,), stdout=open(ROOT / 'xvfb.log', 'w'), stderr=subprocess.STDOUT, env=env)
os.close(write_fd)
with os.fdopen(read_fd) as stream:
    display = stream.readline().strip()
if not display:
    raise SystemExit('Xvfb did not allocate a display.')
env['DISPLAY'] = ':' + display
window_manager = subprocess.Popen(['openbox'], stdout=open(ROOT / 'openbox.log', 'w'), stderr=subprocess.STDOUT, env=env)
time.sleep(1)
results = []
processes = []
serial = 0

def cmd(args):
    return subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def windows():
    r = cmd(['xdotool', 'search', '--onlyvisible', '--name', '^BookStark$'])
    return r.stdout.split() if r.returncode == 0 else []

def wait_for(check, label, timeout=30):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        value = check()
        if value:
            return value
        time.sleep(0.2)
    raise RuntimeError(label)

def record(name, **details):
    results.append(dict(name=name, status='PASS', **details))
    print(json.dumps(results[-1]), flush=True)

def launch(mode):
    global serial
    serial += 1
    appenv = dict(env, XDG_CONFIG_HOME=str(ROOT / 'profiles' / mode))
    if mode == 'retained':
        appenv['BOOKSTARK_GUI_LIFECYCLE_HELPER'] = 'retained'
        args = [str(ROOT / 'retained.test'), '-test.run', '^$']
        cwd = SOURCE
    else:
        args = ['python3', 'build.py', '--run', '--tags', 'wails,production,gtk3,purego', '--output', str(ROOT / ('bookstark-' + mode))]
        cwd = SOURCE
    log = ROOT / (mode + '-' + str(serial) + '.log')
    p = subprocess.Popen(args, cwd=str(cwd), env=appenv, stdout=open(log, 'w'), stderr=subprocess.STDOUT)
    processes.append(p)
    return (p, log)

def second(mode, expected=0):
    p, log = launch(mode)
    p.wait(timeout=45)
    assert p.returncode == expected, (mode, p.returncode, log.read_text()[-5000:])
    return log.read_text()

def close(window):
    r = cmd(['xdotool', 'windowactivate', '--sync', window, 'key', '--clearmodifiers', 'alt+F4'])
    assert r.returncode == 0, r.stderr
    wait_for(lambda: not windows(), 'window did not close', 20)

def run():
    first, log = launch('fixed')
    old = wait_for(windows, 'fixed never opened', 90)[0]
    time.sleep(3)
    second('fixed')
    assert windows() == [old], windows()
    record('duplicate_launch_reuses_main_window', pid=first.pid, window=old)
    cmd(['xdotool', 'windowminimize', old])
    wait_for(lambda: not windows(), 'minimise failed')
    second('fixed')
    restored = wait_for(windows, 'minimised window did not restore')
    assert restored == [old], restored
    record('duplicate_launch_restores_minimised_window', window=old)
    close(old)
    first.wait(timeout=20)
    assert first.returncode == 0, log.read_text()[-5000:]
    record('linux_close_exits_cleanly', exit_code=first.returncode)
    first, log = launch('fixed')
    new = wait_for(windows, 'relaunch did not open', 90)[0]
    time.sleep(2)
    record('linux_relaunch_after_close_opens', pid=first.pid, window=new)
    close(new)
    first.wait(timeout=20)
    first, log = launch('retained')
    old = wait_for(windows, 'retained helper never opened', 90)[0]
    time.sleep(3)
    for cycle in range(3):
        close(old)
        assert first.poll() is None, log.read_text()[-5000:]
        second('retained')
        new = wait_for(windows, 'retained process did not recreate window', 45)[0]
        assert new != old, (new, old)
        assert first.poll() is None, log.read_text()[-5000:]
        record('retained_process_recreates_closed_window', cycle=cycle + 1, pid=first.pid, old_window=old, new_window=new)
        old = new
        time.sleep(2)
    with open(ROOT / 'restored-window.xwd', 'wb') as f:
        subprocess.run(['xwd', '-root', '-silent'], env=env, stdout=f, check=True)
    record('restored_window_screenshot_captured')
try:
    run()
except Exception:
    traceback.print_exc()
    results.append(dict(status='FAIL', error=traceback.format_exc()))
finally:
    (ROOT / 'results.json').write_text(json.dumps(results, indent=2))
    for p in processes:
        if p.poll() is None:
            p.terminate()
    time.sleep(1)
    for p in processes:
        if p.poll() is None:
            p.kill()
    window_manager.terminate()
    xvfb.terminate()
if any((r['status'] == 'FAIL' for r in results)):
    raise SystemExit(1)
