#!/usr/bin/env python3
"""Release-only, generated-fixture session storage measurements on macOS."""
import argparse
import concurrent.futures
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time
import uuid


class Usage(ctypes.Structure):
    # SDK sys/resource.h, rusage_info_v2: UUID then 18 uint64_t fields.
    _fields_ = [("uuid", ctypes.c_uint8 * 16), ("values", ctypes.c_uint64 * 18)]


class UsageV4(ctypes.Structure):
    # SDK rusage_info_v4: UUID then 35 uint64_t fields, lifetime peak at index 28.
    _fields_ = [("uuid", ctypes.c_uint8 * 16), ("values", ctypes.c_uint64 * 35)]


LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
LIBPROC.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]


def usage(pid):
    value = Usage()
    if LIBPROC.proc_pid_rusage(pid, 2, ctypes.byref(value)) != 0:
        raise OSError(ctypes.get_errno(), "proc_pid_rusage")
    return value.values[16], value.values[17]


def wait_file(path, process, timeout=300):
    deadline = time.monotonic() + timeout
    while not path.exists():
        if process.poll() is not None:
            raise RuntimeError(f"Benchmark child exited {process.returncode}; see {path.parent}")
        if time.monotonic() > deadline:
            process.kill()
            raise TimeoutError(path.name)
        time.sleep(0.002)


def summarize(values):
    warm = sorted(values[1:])
    return {"first_access_ms": values[0], "warm_p50_ms": statistics.median(warm),
            "warm_p95_ms": warm[math.ceil(len(warm) * 0.95) - 1]}


def measure(executable, root, session, phase):
    ready = root / (uuid.uuid4().hex + ".ready")
    timing = ready.with_suffix(".time")
    log = ready.with_suffix(".log")
    command = ["/usr/bin/time", "-l", "-o", str(timing), str(executable), "benchmark",
               str(root / "store"), session, phase, str(ready)]
    started = time.perf_counter()
    with log.open("wb") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        try:
            wait_file(ready, process)
            pid = int(ready.read_text())
            opening_ms = (time.perf_counter() - started) * 1000
            before = usage(pid)
            Path(str(ready) + ".go").touch()
            result_file = Path(str(ready) + ".json")
            wait_file(result_file, process)
            after = usage(pid)
            result = json.loads(result_file.read_text())
            Path(str(ready) + ".finish").touch()
            if process.wait(timeout=10) != 0:
                raise RuntimeError(log.read_text()[-1500:])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    result["latency"] = summarize(result["samplesMS"])
    result.update({"process_to_ready_ms": opening_ms,
                   "disk_bytes_read": after[0] - before[0],
                   "disk_bytes_written": after[1] - before[1]})
    match = re.search(r"(\d+)\s+maximum resident set size", timing.read_text())
    result["peak_rss_bytes"] = int(match.group(1)) if match else None
    return result


def measure_ui(repo, root, output):
    environment = dict(os.environ, TAG_SESSION_BENCHMARK_ROOT=str(root), TAG_LIVE_TESTS="0")
    with output.with_suffix(".ui.log").open("wb") as log:
        process = subprocess.Popen(["swift", "test", "-c", "release", "--filter", "SessionPerformanceTests"],
                                   cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_file(root / "ui.ready", process)
            pid = int((root / "ui.ready").read_text())
            (root / "ui.go").touch()
            wait_file(root / "benchmark-ui.json", process)
            peak = UsageV4()
            if LIBPROC.proc_pid_rusage(pid, 4, ctypes.byref(peak)) != 0:
                raise OSError(ctypes.get_errno(), "proc_pid_rusage v4")
            result = json.loads((root / "benchmark-ui.json").read_text())
            for measurement in result:
                measurement["test_process_peak_footprint_bytes"] = peak.values[28]
                measurement["latency"] = {key: summarize(value) for key, value in measurement.items()
                                          if key.endswith("MS")}
        finally:
            (root / "ui.go").touch()
            (root / "ui.finish").touch()
            if process.wait(timeout=30) != 0:
                raise RuntimeError("UI benchmark failed; see its log")
    return result


def source_fingerprint(repo):
    paths = [repo / "Package.swift", repo / "Package.resolved", Path(__file__).resolve()]
    paths += list((repo / "Sources").rglob("*.swift")) + list((repo / "Tests").rglob("*.swift"))
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(repo)).encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skip-build", action="store_true")
    arguments = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = arguments.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if not arguments.skip_build:
        with output.with_suffix(".build.log").open("wb") as log:
            build_environment = dict(os.environ)
            build_environment.pop("TAG_SESSION_BENCHMARK_ROOT", None)
            subprocess.run(["swift", "test", "-c", "release", "--filter", "SessionPerformanceTests"],
                           cwd=repo, env=build_environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    candidates = [repo / ".build/release/SessionProbe", repo / ".build/out/Products/Release/SessionProbe"]
    executable = next((path.resolve() for path in candidates if path.is_file()), None)
    if executable is None:
        raise RuntimeError("Build the release SessionProbe first")
    subprocess.run(["codesign", "--force", "--sign", "-", str(executable)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix="tag-session-benchmark-") as temporary:
        root = Path(temporary)
        os.chmod(root, 0o700)
        (root / ".session-probe-fixture").write_text("generated fixture")
        seed_log = output.with_suffix(".seed.log")
        with seed_log.open("wb") as log:
            subprocess.run([str(executable), "benchmark-seed", str(root / "store"), str(uuid.UUID(int=1)),
                            "full", str(root / "seed.ready")], stdout=log, stderr=subprocess.STDOUT, check=True)
        fixture = json.loads((root / "benchmark-fixture.json").read_text())
        ui = measure_ui(repo, root, output)
        results = []
        for count in (1000, 10000):
            session = fixture["small" if count == 1000 else "large"]
            for phase in ("sqlite-4k", "jsonl-4k", "sqlite-1m", "jsonl-1m", "load", "jsonl-load"):
                results.append({"initial_entries": count, **measure(executable, root, session, phase)})
        for phase in ("list", "discover", "discover-miss", "discover-unicode", "search"):
            results.append(measure(executable, root, fixture["source"], phase))
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            jobs = [(fixture["small"], "sqlite-4k"),
                    (fixture["large"], "sqlite-4k"), (fixture["source"], "list")]
            concurrent_results = list(executor.map(lambda job: measure(executable, root, *job), jobs))
        report = {"source_fingerprint_sha256": source_fingerprint(repo), "optimization": "release",
                  "fixture": fixture, "ui": ui, "results": results, "concurrent": concurrent_results,
                  "measurement_notes": [
                      "Release build; deterministic generated content. No provider calls.",
                      "First sample uses a fresh process/connection; OS page cache is uncontrolled.",
                      "JSONL acknowledges only after fsync and F_FULLFSYNC; SQLite uses DELETE/FULL/fullfsync.",
                      "SQLite also atomically maintains metadata and text indexes; JSONL baseline has no such indexes.",
                      "Disk bytes are OS-accounted I/O deltas, including a small result report, not physical NAND writes.",
                      "Peak RSS is measured per storage child by time -l; build/fixture-generation memory is excluded.",
                      "UI peak footprint is the lifetime kernel maximum of the entire test process across both sizes and startup trials.",
                      "Usable-input samples include controller recovery, trusted-context revision, rendering and an actual local edit; provider catalogues and environment are generated fixtures.",
                      "Startup uses a separate consistent backup so its context/draft writes do not change storage workloads."]}
        output.write_text(json.dumps(report, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    main()
