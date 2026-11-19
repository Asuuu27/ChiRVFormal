#!/usr/bin/env python3
"""Generate the ChiRVFormal checker and run the bounded Ibex regression."""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


INTEGRATION = Path(__file__).resolve().parent
REPO = INTEGRATION.parents[1]
IBEX_REV = "0d1b1723253cdf804aad263e805544d54aa5aa57"
TASKS = ("bmc", "cover", "negative")


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def stage_sources(ibex_dir, run_dir, checker):
    staged = run_dir / "sources"
    staged.mkdir()
    includes = []
    rtl = []
    for line in (INTEGRATION / "ibex.sources").read_text(encoding="utf-8").splitlines():
        entry = line.partition("#")[0].strip()
        if not entry:
            continue
        if entry.startswith("+incdir+"):
            relative = Path("ibex") / entry.removeprefix("+incdir+")
            shutil.copytree(ibex_dir / relative.relative_to("ibex"), staged / relative)
            includes.append(f"-I sources/{relative.as_posix()}")
        else:
            relative = Path("ibex") / entry
            target = staged / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ibex_dir / entry, target)
            rtl.append(f"sources/{relative.as_posix()}")

    for source in (checker, INTEGRATION / "ibex_rvfi.sv", INTEGRATION / "ibex_formal.sv"):
        shutil.copy2(source, staged / source.name)
        rtl.append(f"sources/{source.name}")
    return " ".join(includes + rtl)


def run_task(task, run_dir, sources, depth, timeout):
    mode = "cover" if task == "cover" else "bmc"
    expected = "FAIL" if task == "negative" else "PASS"
    mutation = "-D IBEX_MUTATE_RF_WRITE " if task == "negative" else ""
    cover_assert = "cover_assert on\n" if task == "cover" else ""
    job = run_dir / f"{task}.sby"
    job.write_text(
        f"""[options]
mode {mode}
depth {depth}
timeout {timeout}
expect {expected.lower()}
{cover_assert}
[engines]
smtbmc boolector

[script]
plugin -i slang
read_slang --top ibex_formal -D RVFI -D SYNTHESIS {mutation}{sources}
prep -top ibex_formal -flatten -nordff
check -assert

[files]
sources sources
""",
        encoding="utf-8",
    )
    result = subprocess.run(["sby", "-d", task, job.name], cwd=run_dir, check=False)
    output = run_dir / task
    status_file = output / "status"
    status = status_file.read_text(encoding="utf-8").split() if status_file.exists() else []
    if result.returncode or status[:1] != [expected]:
        raise RuntimeError(f"{task}: expected {expected}, got {status[:1] or 'no status'} ({output})")
    if task == "negative":
        failure = (output / "FAIL").read_text(encoding="utf-8")
        if "rf_write_matches_rvfi" not in failure:
            raise RuntimeError(f"{task}: expected the register-file write assertion to fail ({output})")
    print(f"{task}: {expected} (expected, depth {depth}) — {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibex-dir", required=True, type=Path, help=f"Ibex checkout or archive at {IBEX_REV}")
    parser.add_argument("--checker", type=Path, help="pre-generated ActionChecker.sv for config.json")
    parser.add_argument("--task", choices=(*TASKS, "all"), default="all")
    parser.add_argument("--depth", type=positive_int, default=32)
    parser.add_argument("--timeout", type=positive_int, default=300, help="seconds per SBY task")
    args = parser.parse_args()

    ibex_dir = args.ibex_dir.resolve(strict=True)
    if (ibex_dir / ".git").exists():
        actual = subprocess.check_output(["git", "-C", str(ibex_dir), "rev-parse", "HEAD"], text=True).strip()
        if actual != IBEX_REV:
            raise RuntimeError(f"Ibex HEAD must be {IBEX_REV}; found {actual}")
        dirty = subprocess.check_output(
            ["git", "-C", str(ibex_dir), "status", "--porcelain", "--untracked-files=no"], text=True
        )
        if dirty:
            raise RuntimeError("Ibex has local changes in tracked files; use the pinned unmodified checkout")

    build = REPO / "build" / "ibex"
    build.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=build))
    print(f"Run directory: {run_dir}", flush=True)
    if args.checker:
        checker = args.checker.resolve(strict=True)
        if checker.name != "ActionChecker.sv":
            raise RuntimeError("--checker must point to ActionChecker.sv")
    else:
        target = run_dir.relative_to(REPO).as_posix() + "/generated"
        command = f"svcore/runMain svcore.Main -m action -c sv-core/ibex/config.json -t {target}"
        subprocess.run(["sbt", command], cwd=REPO, check=True)
        checker = REPO / target / "ActionChecker.sv"
    sources = stage_sources(ibex_dir, run_dir, checker)

    tasks = TASKS if args.task == "all" else (args.task,)
    for task in tasks:
        run_task(task, run_dir, sources, args.depth, args.timeout)


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"ibex regression: {error}", file=sys.stderr)
        sys.exit(1)
