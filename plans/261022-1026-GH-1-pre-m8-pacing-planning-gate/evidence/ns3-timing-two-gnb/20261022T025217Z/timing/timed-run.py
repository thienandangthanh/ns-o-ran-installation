import json, os, signal, subprocess, sys, time
rundir, tmo = sys.argv[1], float(sys.argv[2])
cmd = sys.argv[3:]
os.makedirs(rundir, exist_ok=True)
out = open(os.path.join(rundir, "stdout.txt"), "wb")
t0 = time.monotonic()
p = subprocess.Popen(cmd, cwd=rundir, stdout=out, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)
pgid = p.pid
timed_out = False
try:
    rc = p.wait(timeout=tmo)
except subprocess.TimeoutExpired:
    timed_out = True
    os.killpg(pgid, signal.SIGKILL)
    p.wait()
    rc = -9
wall = time.monotonic() - t0
try:
    os.killpg(pgid, signal.SIGKILL)  # anything left in our group
    leftover = True
except ProcessLookupError:
    leftover = False
print(json.dumps({"wall_s": wall, "rc": rc, "timed_out": timed_out, "pgid": pgid,
                  "leftover_killed": leftover}))
