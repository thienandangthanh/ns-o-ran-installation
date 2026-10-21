#!/usr/bin/env python3
"""compare-run-versions.py <dev-m1-evidence-dir> <rerun-m1-evidence-dir> [--out FILE]

Diffs the package and image versions two M1 runs resolved (K15: the installer
falls back to the newest available package, so a re-run can drift). Reads
versions.txt (and the dev run's versions-supplement.txt, which carries the held
kube* packages the first M1 filter dropped). Pod names carry random suffixes,
so images are compared per container as (image, digest). Prints a JSON report;
exit 0 always: drift is reported, not hidden, and judged by the caller.
"""
import json
import re
import sys


def parse(dirpath):
    pkgs, imgs, other = {}, {}, {}
    texts = []
    for name in ("versions.txt", "versions-supplement.txt"):
        try:
            texts.append(open(f"{dirpath}/{name}", encoding="utf-8").read())
        except OSError:
            pass
    section = None
    for text in texts:
        for line in text.splitlines():
            if line.startswith("#"):
                continue
            if line.startswith("--- "):
                section = line[4:].strip()
                continue
            m = re.match(r"^(ii|hi)\s+(\S+)\s+(\S+)", line)
            if m:
                pkgs[m.group(2)] = m.group(3)
                continue
            if section and section.startswith("ricplt/ricinfra pod images"):
                parts = line.split()
                if len(parts) >= 3:
                    pod, container, image = parts[0], parts[1], parts[2]
                    digest = parts[3].split("@")[-1] if len(parts) > 3 else ""
                    base = re.sub(r"(-[a-z0-9]{8,10})?-[a-z0-9]{5}$", "", pod)
                    imgs[f"{base}/{container}"] = (image, digest)
                continue
            if section and line.strip() and section in ("uname -r", "kubectl version",
                                                        "containerd --version", "helm version"):
                other.setdefault(section, []).append(line.strip())
    return pkgs, imgs, {k: " | ".join(v) for k, v in other.items()}


def diff(a, b):
    """Version changes for items both runs recorded."""
    return {k: {"dev": a[k], "rerun": b[k]} for k in sorted(set(a) & set(b)) if a[k] != b[k]}


def only(a, b):
    """Items one run recorded and the other did not (collection, not drift)."""
    return {"dev_only": sorted(set(a) - set(b)), "rerun_only": sorted(set(b) - set(a))}


def main():
    args = sys.argv[1:]
    out = None
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        del args[i:i + 2]
    dev, rerun = args
    dp, di, do = parse(dev)
    rp, ri, ro = parse(rerun)
    report = {
        "dev": dev, "rerun": rerun,
        "packages_compared": len(set(dp) | set(rp)),
        "images_compared": len(set(di) | set(ri)),
        "package_drift": diff(dp, rp),
        "image_drift": {k: {"dev": list(v["dev"] or []), "rerun": list(v["rerun"] or [])}
                        for k, v in diff(di, ri).items()},
        "platform_drift": diff(do, ro),
        "not_compared": {"packages": only(dp, rp), "images": only(di, ri), "platform": only(do, ro)},
    }
    report["drift"] = bool(report["package_drift"] or report["image_drift"] or report["platform_drift"])
    text = json.dumps(report, indent=2)
    if out:
        open(out, "w", encoding="utf-8").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
