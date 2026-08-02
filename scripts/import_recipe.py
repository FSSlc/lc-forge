#!/usr/bin/env python3
"""Import a conda-forge package (and missing deps) into todo/, then build & upload.

Workflow for a package name P:

1. If P is not on conda-forge → error with reason.
2. If P is already on https://prefix.dev/scns → print and exit 0.
3. prep.sh --strict P  (clone feedstock, require recipe.yaml via crm).
4. Parse recipe.yaml build/host/run/test deps.
5. For each real package dep not on scns:
   - must exist on conda-forge, else error;
   - recursively apply the same prep flow.
6. Once every prepared recipe's deps are on scns *or* present as local
   todo/ recipes, start the pixi container and rattler-build the whole
   prepared set; any failure aborts; on success upload to scns.

Exit codes:
  0  success (already on scns, or built & uploaded)
  1  user/input/resolve/prep/build/upload failure
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCNS_CHANNEL = os.environ.get("DEFAULT_CHANNEL", "https://prefix.dev/scns")
CONDA_FORGE_CHANNEL = "conda-forge"
FEEDSTOCK_OUTPUTS_RAW = (
    "https://raw.githubusercontent.com/conda-forge/feedstock-outputs/main/outputs"
)
ANACONDA_PKG_API = "https://api.anaconda.org/package/conda-forge/{name}"
GITHUB_FEEDSTOCK = "https://github.com/conda-forge/{name}-feedstock"
PACKAGE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")

# MatchSpec-ish tokens that are not real packages to import.
SKIP_DEP_EXACT = {
    "pip",
    "python",
    "pypy",
    "r-base",
    "m2-base",
    "vs2015_runtime",
    "vs2017_runtime",
    "vs2019_runtime",
    "vs2022_runtime",
}

# Leading name patterns treated as toolchain / virtual / selectors noise.
SKIP_DEP_PREFIXES = (
    "__",  # virtual packages: __glibc, __unix, ...
)

JINJA_RE = re.compile(r"\$\{\{.*?\}\}")
SELECTOR_RE = re.compile(r"\s+#\s*\[.*?\]\s*$")
# pin_subpackage / pin_compatible / compiler / stdlib references
INTERNAL_PIN_RE = re.compile(
    r"pin_subpackage|pin_compatible|compiler\s*\(|stdlib\s*\("
)

USER_AGENT = "lc-forge-import-recipe/1.0"


class ImportError_(Exception):
    """Fatal import failure with a concrete reason for the user."""


# ---------------------------------------------------------------------------
# HTTP / channel helpers
# ---------------------------------------------------------------------------


def http_get_json(url: str, timeout: float = 60.0) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        raise ImportError_(f"HTTP {e.code} fetching {url}: {body}") from e
    except urllib.error.URLError as e:
        raise ImportError_(f"Network error fetching {url}: {e}") from e


def http_get_text(url: str, timeout: float = 60.0) -> tuple[int, str]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, body
    except urllib.error.URLError as e:
        raise ImportError_(f"Network error fetching {url}: {e}") from e


def feedstock_outputs_url(pkg: str) -> str:
    """Path layout: outputs/<c0>/<c1>/<c2>/<name>.json (name lowercased)."""
    name = pkg.lower()
    if len(name) < 3:
        # short names still use three path segments with what is available
        parts = list(name) + ["_"] * (3 - len(name))
        return f"{FEEDSTOCK_OUTPUTS_RAW}/{parts[0]}/{parts[1]}/{parts[2]}/{name}.json"
    return f"{FEEDSTOCK_OUTPUTS_RAW}/{name[0]}/{name[1]}/{name[2]}/{name}.json"


@dataclass
class ChannelIndex:
    """Cached set of package names available on a channel (all subdirs)."""

    channel: str
    subdirs: tuple[str, ...] = ("linux-64", "linux-aarch64", "noarch")
    _names: set[str] | None = field(default=None, init=False, repr=False)

    def _load_via_conda_search(self, name: str) -> bool:
        """Point query via `conda search` (handles prefix.dev auth/HMAC)."""
        cmd = [
            "conda",
            "search",
            "-c",
            self.channel,
            "--override-channels",
            name,
        ]
        try:
            proc = subprocess.run(
                cmd,
                check=False,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except FileNotFoundError as e:
            raise ImportError_(
                "conda is required to query channels but was not found on PATH"
            ) from e
        except subprocess.TimeoutExpired as e:
            raise ImportError_(
                f"Timed out querying {self.channel} for package {name!r}"
            ) from e
        return proc.returncode == 0

    def _try_bulk_load(self) -> set[str] | None:
        """Best-effort bulk load; returns None if repodata is not directly fetchable."""
        names: set[str] = set()
        loaded_any = False
        for subdir in self.subdirs:
            for base in (
                self.channel.rstrip("/"),
                self.channel.rstrip("/").replace(
                    "https://prefix.dev/", "https://packages.prefix.dev/"
                ),
            ):
                url = f"{base}/{subdir}/repodata.json"
                code, body = http_get_text(url, timeout=120)
                if code != 200:
                    continue
                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    continue
                for key in ("packages", "packages.conda"):
                    for meta in (data.get(key) or {}).values():
                        if isinstance(meta, dict) and "name" in meta:
                            names.add(meta["name"])
                loaded_any = True
                break
        return names if loaded_any else None

    def ensure_loaded(self) -> None:
        if self._names is not None:
            return
        bulk = self._try_bulk_load()
        self._names = bulk if bulk is not None else set()
        # empty set means "use point queries only"

    def has(self, name: str) -> bool:
        self.ensure_loaded()
        assert self._names is not None
        if name in self._names:
            return True
        # Point query (and cache positive hits). Always query when bulk load
        # failed or name was not in the bulk set (bulk may be partial).
        if self._load_via_conda_search(name):
            self._names.add(name)
            return True
        return False


# ---------------------------------------------------------------------------
# conda-forge existence / feedstock mapping
# ---------------------------------------------------------------------------


def on_conda_forge(pkg: str) -> tuple[bool, str]:
    """Return (exists, detail). Uses anaconda.org API then feedstock HEAD."""
    url = ANACONDA_PKG_API.format(name=quote(pkg, safe=""))
    code, body = http_get_text(url)
    if code == 200:
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = {}
        if data.get("error"):
            return False, f"anaconda.org: {data['error']}"
        latest = data.get("latest_version") or "?"
        return True, f"anaconda.org/conda-forge/{pkg} (latest={latest})"
    if code == 404:
        # Fall back to feedstock existence for edge cases.
        fs_url = GITHUB_FEEDSTOCK.format(name=pkg)
        fs_code, _ = http_get_text(fs_url)
        if fs_code == 200:
            return True, f"feedstock exists at {fs_url}"
        return (
            False,
            f"package {pkg!r} not found on conda-forge "
            f"(anaconda.org HTTP {code}; feedstock HTTP {fs_code} at {fs_url})",
        )
    return False, f"unexpected HTTP {code} from {url}: {body[:200]}"


def resolve_feedstock(pkg: str) -> str:
    """Map a package output name to a conda-forge feedstock name."""
    url = feedstock_outputs_url(pkg)
    code, body = http_get_text(url)
    if code == 200:
        try:
            data = json.loads(body)
        except json.JSONDecodeError as e:
            raise ImportError_(
                f"Invalid JSON from feedstock-outputs for {pkg!r} ({url}): {e}"
            ) from e
        feedstocks = data.get("feedstocks") or []
        if not feedstocks:
            raise ImportError_(
                f"feedstock-outputs has no feedstocks for {pkg!r}: {data}"
            )
        # Prefer an exact name match, else first entry.
        if pkg in feedstocks:
            return pkg
        if pkg.replace("_", "-") in feedstocks:
            return pkg.replace("_", "-")
        return feedstocks[0]

    # Fallback: assume package name == feedstock name if the repo exists.
    fs_url = GITHUB_FEEDSTOCK.format(name=pkg)
    fs_code, _ = http_get_text(fs_url)
    if fs_code == 200:
        return pkg

    raise ImportError_(
        f"Cannot map package {pkg!r} to a conda-forge feedstock "
        f"(feedstock-outputs HTTP {code} at {url}; "
        f"no repo at {fs_url})."
    )


# ---------------------------------------------------------------------------
# recipe.yaml dependency extraction
# ---------------------------------------------------------------------------


def _strip_selectors_and_jinja_line(line: str) -> str:
    line = SELECTOR_RE.sub("", line)
    return line.rstrip()


def _is_skipped_dep(name: str) -> bool:
    if not name:
        return True
    if name in SKIP_DEP_EXACT:
        return True
    if name.startswith(SKIP_DEP_PREFIXES):
        return True
    # compiler/stdlib activation packages still appear as concrete names
    # like gxx_linux-64 after rendering; for unrendered recipe.yaml we mostly
    # see ${{ compiler(...) }} which is dropped below.
    return False


def _dep_name_from_spec(spec: str) -> str | None:
    """Extract the package name from a MatchSpec-like string.

    Returns None when the spec is jinja/internal/not a real importable dep.
    """
    spec = _strip_selectors_and_jinja_line(spec.strip())
    if not spec or spec.startswith("#"):
        return None
    # Drop pure jinja expressions / pin helpers.
    if INTERNAL_PIN_RE.search(spec):
        return None
    if JINJA_RE.fullmatch(spec.strip()):
        return None
    # Remove embedded jinja fragments but keep surrounding name if any.
    cleaned = JINJA_RE.sub("", spec).strip()
    if not cleaned:
        return None
    # YAML list form may still have leading "- ".
    if cleaned.startswith("- "):
        cleaned = cleaned[2:].strip()
    # MatchSpec: name[version] or name version build
    # Take first token; strip conda operators glued to name rarely happen.
    token = re.split(r"[\s<=>!@,\[/]+", cleaned, maxsplit=1)[0].strip()
    token = token.strip("\"'")
    if not token or not PACKAGE_NAME_RE.match(token):
        return None
    if _is_skipped_dep(token):
        return None
    return token


def _condition_applies_linux(condition: Any) -> bool | None:
    """Return True/False if we can evaluate a rattler `if:` for linux targets.

    This repo only builds linux-64 / linux-aarch64, so win/osx-only branches are
    skipped. Returns None when the expression is too complex to evaluate safely
    (caller should then include *both* branches conservatively, or neither for
    known-foreign platforms only).
    """
    if condition is None:
        return True
    if not isinstance(condition, str):
        return None
    expr = condition.strip().lower()
    if not expr:
        return True

    # Normalize common rattler/conda selector words.
    # Fast paths for pure platform checks.
    positive_linux = {
        "linux",
        "unix",
        "linux64",
        "linux-64",
        "linux-aarch64",
        "aarch64",
        "x86_64",
        "true",
    }
    negative_linux = {
        "win",
        "win32",
        "win64",
        "osx",
        "osx-64",
        "osx-arm64",
        "emscripten",
        "false",
    }
    if expr in positive_linux:
        return True
    if expr in negative_linux:
        return False

    # not win / not osx → true on linux; not unix / not linux → false
    if expr.startswith("not "):
        inner = expr[4:].strip()
        sub = _condition_applies_linux(inner)
        if sub is None:
            return None
        return not sub

    # Simple conjunction/disjunction of known atoms.
    for sep, combiner in ((" and ", all), (" or ", any)):
        if sep in expr:
            parts = [p.strip() for p in expr.split(sep)]
            vals = [_condition_applies_linux(p) for p in parts]
            if any(v is None for v in vals):
                return None
            return combiner(vals)  # type: ignore[arg-type]

    # Unknown expression (e.g. py==3.10, build_platform != target_platform):
    # include the branch to be safe so we do not miss a real linux dep.
    return None


def _walk_requirement_nodes(node: Any, acc: list[str]) -> None:
    """Collect raw requirement strings from nested recipe YAML structures."""
    if node is None:
        return
    if isinstance(node, str):
        acc.append(node)
        return
    if isinstance(node, list):
        for item in node:
            _walk_requirement_nodes(item, acc)
        return
    if isinstance(node, dict):
        # rattler if/then/else conditional deps — evaluate for linux targets.
        if "if" in node or "then" in node or "else" in node:
            applies = _condition_applies_linux(node.get("if"))
            if applies is True:
                _walk_requirement_nodes(node.get("then"), acc)
            elif applies is False:
                _walk_requirement_nodes(node.get("else"), acc)
            else:
                # Ambiguous: keep both branches so linux deps are not dropped.
                _walk_requirement_nodes(node.get("then"), acc)
                _walk_requirement_nodes(node.get("else"), acc)
            return
        for key, val in node.items():
            if key in {"if", "then", "else"}:
                continue
            _walk_requirement_nodes(val, acc)


def extract_deps_from_recipe(recipe_path: Path) -> set[str]:
    """Parse recipe.yaml and return concrete package deps from build/host/run/test.

    Uses a lightweight line/structure parse so `${{ }}` jinja does not break
    YAML loading. Falls back to PyYAML when the file is plain enough.
    """
    text = recipe_path.read_text(encoding="utf-8")
    deps: set[str] = set()

    # --- primary: structural walk via PyYAML after neutralizing jinja ---
    neutralized = JINJA_RE.sub("__JINJA__", text)
    # quote bare __JINJA__ in list items if needed — PyYAML usually fine
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(neutralized)
    except Exception:
        data = None

    if isinstance(data, dict):
        req_blocks: list[Any] = []

        def collect_requirements(obj: Any) -> None:
            if isinstance(obj, dict):
                if "requirements" in obj:
                    req_blocks.append(obj["requirements"])
                for v in obj.values():
                    collect_requirements(v)
            elif isinstance(obj, list):
                for v in obj:
                    collect_requirements(v)

        collect_requirements(data)

        # tests may use requirements.run etc.; already covered by walk above.
        # Also look at top-level tests[*].requirements explicitly is included.

        interesting_keys = {"build", "host", "run", "run_constrained", "test"}
        raw: list[str] = []
        for block in req_blocks:
            if not isinstance(block, dict):
                _walk_requirement_nodes(block, raw)
                continue
            for key, val in block.items():
                if key in interesting_keys or key == "run":
                    _walk_requirement_nodes(val, raw)
                # skip run_exports / ignore_run_exports — not install deps to fetch

        # tests section sometimes nests requirements under tests: - requirements:
        tests = data.get("tests")
        if isinstance(tests, list):
            for t in tests:
                if isinstance(t, dict) and "requirements" in t:
                    treq = t["requirements"]
                    if isinstance(treq, dict):
                        for key in ("build", "host", "run"):
                            if key in treq:
                                _walk_requirement_nodes(treq[key], raw)
                    else:
                        _walk_requirement_nodes(treq, raw)

        for spec in raw:
            if not isinstance(spec, str):
                continue
            # Fully-jinja specs become only the placeholder — skip them.
            stripped = spec.strip().lstrip("- ").strip()
            if stripped in {"__JINJA__", ""}:
                continue
            # Remove placeholder tokens left inside mixed strings, then parse.
            orig_guess = spec.replace("__JINJA__", " ").strip()
            name = _dep_name_from_spec(orig_guess)
            if name:
                deps.add(name)

    # --- fallback line scan for robustness ---
    if not deps:
        in_interesting = False
        interesting_indent = -1
        section_re = re.compile(
            r"^(\s*)(build|host|run|run_constrained)\s*:\s*(?:#.*)?$"
        )
        for line in text.splitlines():
            m = section_re.match(line)
            if m:
                # only count under requirements/tests, heuristic: indent >= 2
                in_interesting = True
                interesting_indent = len(m.group(1))
                continue
            if in_interesting:
                if line.strip() == "":
                    continue
                indent = len(line) - len(line.lstrip(" "))
                if indent <= interesting_indent and not line.lstrip().startswith("-"):
                    in_interesting = False
                    continue
                if line.lstrip().startswith("-"):
                    name = _dep_name_from_spec(line.lstrip()[1:])
                    if name:
                        deps.add(name)

    return deps


def package_name_from_recipe(recipe_path: Path) -> str | None:
    """Best-effort read of package.name from recipe.yaml."""
    text = recipe_path.read_text(encoding="utf-8")
    # package:\n  name: foo  or name: ${{ name }}
    m = re.search(
        r"(?m)^package:\s*\n(?:  .*\n)*?  name:\s*(\S+)",
        text,
    )
    if not m:
        m = re.search(r"(?m)^  name:\s*(\S+)", text)
    if not m:
        return None
    raw = m.group(1).strip().strip("\"'")
    if raw.startswith("${{"):
        # try context name
        cm = re.search(r"(?m)^  name:\s*[\"']?([A-Za-z0-9_.-]+)[\"']?\s*$", text)
        # context block
        cm = re.search(
            r"(?m)^context:\s*\n(?:  .*\n)*?  name:\s*[\"']?([A-Za-z0-9_.-]+)",
            text,
        )
        if cm:
            return cm.group(1)
        return None
    if PACKAGE_NAME_RE.match(raw):
        return raw
    return None


# ---------------------------------------------------------------------------
# process helpers
# ---------------------------------------------------------------------------


def run(
    cmd: list[str] | str,
    *,
    cwd: Path | None = None,
    check: bool = True,
    env: dict[str, str] | None = None,
    shell: bool = False,
) -> subprocess.CompletedProcess[str]:
    printable = cmd if isinstance(cmd, str) else " ".join(shlex.quote(c) for c in cmd)
    print(f"+ {printable}", flush=True)
    merged = os.environ.copy()
    if env:
        merged.update(env)
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=False,
        text=True,
        env=merged,
        shell=shell,
    )
    if check and proc.returncode != 0:
        raise ImportError_(
            f"Command failed with exit code {proc.returncode}: {printable}"
        )
    return proc


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Core recursive prepare
# ---------------------------------------------------------------------------


@dataclass
class PrepareState:
    root: Path
    scns: ChannelIndex
    # feedstock name -> reason it was prepared in this run
    prepared: dict[str, str] = field(default_factory=dict)
    # package names known to be on scns (including ones we will build locally)
    satisfied: set[str] = field(default_factory=set)
    visiting: set[str] = field(default_factory=set)
    order: list[str] = field(default_factory=list)  # feedstock prep order

    def todo_dir(self, feedstock: str) -> Path:
        return self.root / "todo" / feedstock


def prep_feedstock(state: PrepareState, feedstock: str) -> Path:
    """Run prep.sh --strict <feedstock>; return path to todo/<feedstock>."""
    script = state.root / "scripts" / "prep.sh"
    todo = state.todo_dir(feedstock)
    try:
        run(["bash", str(script), "--strict", feedstock], cwd=state.root)
    except ImportError_:
        # prep.sh --strict may leave a partial todo/<fs> (e.g. meta.yaml only).
        # Remove it so a retry starts clean and we do not commit junk.
        if todo.is_dir() and not (todo / "recipe.yaml").is_file():
            import shutil

            shutil.rmtree(todo, ignore_errors=True)
        raise
    recipe = todo / "recipe.yaml"
    if not recipe.is_file():
        raise ImportError_(
            f"prep.sh --strict {feedstock} finished but {recipe} is missing. "
            f"crm conversion likely failed; see prep.sh output above."
        )
    return todo


def ensure_package(state: PrepareState, pkg: str, *, via: str) -> None:
    """Make sure package `pkg` is on scns or will be built from a todo recipe."""
    if pkg in state.satisfied or state.scns.has(pkg):
        state.satisfied.add(pkg)
        return

    if pkg in state.visiting:
        # Cyclic dependency among packages we are importing: allowed as long as
        # all nodes end up as local recipes; mark satisfied by local build set.
        print(
            f"Note: cyclic dependency involving {pkg!r} (via {via}); "
            f"will rely on local todo/ recipes.",
            flush=True,
        )
        return

    exists, detail = on_conda_forge(pkg)
    if not exists:
        raise ImportError_(
            f"Dependency {pkg!r} (required by {via}) is not on scns and not on "
            f"conda-forge. Reason: {detail}"
        )

    state.visiting.add(pkg)
    try:
        feedstock = resolve_feedstock(pkg)
        print(
            f"Resolving {pkg!r} via feedstock {feedstock!r} ({detail})",
            flush=True,
        )

        # If this feedstock was already prepared, its outputs will be built.
        if feedstock not in state.prepared:
            # Skip prep only if the *package* is already on scns (checked above)
            # or feedstock recipe already in todo from this/previous step.
            todo = state.todo_dir(feedstock)
            if not (todo / "recipe.yaml").is_file():
                prep_feedstock(state, feedstock)
            else:
                print(
                    f"Reusing existing todo/{feedstock}/recipe.yaml",
                    flush=True,
                )
            state.prepared[feedstock] = f"needed for package {pkg} (via {via})"
            state.order.append(feedstock)

            # Recurse into this recipe's dependencies.
            recipe_path = state.todo_dir(feedstock) / "recipe.yaml"
            deps = extract_deps_from_recipe(recipe_path)
            print(
                f"Dependencies for {feedstock}: {', '.join(sorted(deps)) or '(none)'}",
                flush=True,
            )
            for dep in sorted(deps):
                ensure_package(state, dep, via=feedstock)

        # The requested package will be produced by the feedstock build (or
        # already present). Treat as satisfied for further dependency checks.
        state.satisfied.add(pkg)
        # Also mark the feedstock package name if distinct.
        state.satisfied.add(feedstock)
        pname = package_name_from_recipe(state.todo_dir(feedstock) / "recipe.yaml")
        if pname:
            state.satisfied.add(pname)
    finally:
        state.visiting.discard(pkg)


def verify_all_deps_resolvable(state: PrepareState) -> None:
    """Final pass: every dep is on scns or in the prepared local set."""
    local_names: set[str] = set(state.prepared)
    for fs in state.prepared:
        recipe = state.todo_dir(fs) / "recipe.yaml"
        if recipe.is_file():
            pname = package_name_from_recipe(recipe)
            if pname:
                local_names.add(pname)
            # multi-output: collect output package names roughly
            text = recipe.read_text(encoding="utf-8")
            for m in re.finditer(
                r"(?m)^\s+-\s+package:\s*\n\s+name:\s*(\S+)", text
            ):
                raw = m.group(1).strip().strip("\"'")
                if PACKAGE_NAME_RE.match(raw):
                    local_names.add(raw)
            for m in re.finditer(r"(?m)^\s+-\s+name:\s*(\S+)", text):
                raw = m.group(1).strip().strip("\"'")
                if PACKAGE_NAME_RE.match(raw) and not raw.startswith("${{"):
                    local_names.add(raw)

    missing: list[str] = []
    for fs in state.prepared:
        recipe = state.todo_dir(fs) / "recipe.yaml"
        deps = extract_deps_from_recipe(recipe)
        for dep in sorted(deps):
            if dep in local_names or dep in state.satisfied or state.scns.has(dep):
                continue
            # last chance conda-forge check for clearer error
            exists, detail = on_conda_forge(dep)
            if not exists:
                missing.append(
                    f"{dep} (required by {fs}): not on scns, not local, "
                    f"not on conda-forge ({detail})"
                )
            else:
                missing.append(
                    f"{dep} (required by {fs}): on conda-forge but was not "
                    f"prepared into todo/ — internal resolver bug or skipped dep"
                )
    if missing:
        raise ImportError_(
            "Unresolved dependencies after prep:\n  - " + "\n  - ".join(missing)
        )


# ---------------------------------------------------------------------------
# Build & upload inside pixi container
# ---------------------------------------------------------------------------


def container_build_and_upload(
    root: Path,
    feedstocks: list[str],
    *,
    target_platform: str,
    upload: bool,
    prefix_token: str | None,
    scns_channel: str = SCNS_CHANNEL,
) -> None:
    if not feedstocks:
        raise ImportError_("No recipes were prepared to build.")

    start_img = root / "scripts" / "start_img.sh"
    logs_dir = root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_file = logs_dir / f"build-{target_platform}.log"
    output_dir = root / "output"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Stage only the recipes prepared by this import so --recipe-dir does not
    # pick up unrelated packages already sitting in todo/.
    stage_dir = root / "todo" / ".import-stage"
    log_rel = str(log_file.relative_to(root))
    stage_rel = str(stage_dir.relative_to(root))

    for fs in feedstocks:
        recipe = root / "todo" / fs / "recipe.yaml"
        if not recipe.is_file():
            raise ImportError_(
                f"Cannot build {fs!r}: missing {recipe}. "
                f"Did prepare step upload the todo/ artifact?"
            )

    build_script_parts = [
        "set -Eeuo pipefail",
        "mkdir -p logs output",
        f"rm -rf {shlex.quote(stage_rel)}",
        f"mkdir -p {shlex.quote(stage_rel)}",
    ]
    for fs in feedstocks:
        # Symlink todo/<fs> into the staging dir (relative from stage → todo).
        build_script_parts.append(
            f"ln -sfn ../{shlex.quote(fs)} {shlex.quote(stage_rel)}/{shlex.quote(fs)}"
        )

    # Match the user-requested rattler-build invocation; add -c ./output so
    # packages produced earlier in the same run satisfy later recipes.
    # --continue-on-failure keeps going across recipes, but we still fail the
    # job when rattler-build's overall exit status is non-zero.
    build_script_parts += [
        f'echo "===== Building staged recipes under {stage_rel} '
        f'for {target_platform} ====="',
        # Disable -e around the pipeline so we can inspect PIPESTATUS[0]
        # (rattler-build) even when --continue-on-failure still exits non-zero.
        "set +e",
        (
            "rattler-build build --continue-on-failure --experimental "
            f"-m ./conda_build_config.yaml --skip-existing=all "
            f"--target-platform={shlex.quote(target_platform)} "
            f"-c {shlex.quote(scns_channel)} "
            f"-c ./output "
            f"--recipe-dir {shlex.quote(stage_rel)} "
            f"--output-dir ./output "
            f"2>&1 | tee {shlex.quote(log_rel)}"
        ),
        "build_rc=${PIPESTATUS[0]}",
        "set -e",
        'if [[ "$build_rc" -ne 0 ]]; then '
        'echo "rattler-build reported failure (exit $build_rc)" >&2; '
        'exit "$build_rc"; fi',
        f'echo "All prepared recipes built successfully for {target_platform}"',
    ]
    build_cmd = "\n".join(build_script_parts)

    run(
        ["bash", str(start_img), "--run", build_cmd],
        cwd=root,
    )

    conda_files = list(output_dir.rglob("*.conda"))
    if not conda_files:
        print(
            "Warning: no .conda artifacts under output/. "
            "All packages may have been skipped as existing.",
            flush=True,
        )

    if not upload:
        print("Upload skipped (--no-upload).", flush=True)
        return

    if not prefix_token:
        raise ImportError_(
            "Build succeeded but PREFIX_DEV_TOKEN / --token is not set; "
            "cannot upload to scns."
        )

    upload_parts = [
        "set -Eeuo pipefail",
        "shopt -s nullglob globstar",
        "files=(output/**/*.conda)",
        'if [[ ${#files[@]} -eq 0 ]]; then echo "No .conda files to upload"; exit 0; fi',
        'for file in "${files[@]}"; do',
        '  echo "Uploading $file"',
        f"  rattler-build upload prefix -c scns -a {shlex.quote(prefix_token)} "
        f'--skip-existing "$file"',
        "done",
    ]
    run(
        ["bash", str(start_img), "--run", "\n".join(upload_parts)],
        cwd=root,
    )


# Non-hidden name so actions/upload-artifact includes it by default
# (hidden/dotfiles are excluded unless include-hidden-files: true).
MANIFEST_NAME = "import-manifest.json"
MANIFEST_NAME_LEGACY = ".import-manifest.json"


def manifest_path(root: Path) -> Path:
    """Return the import manifest path, preferring the non-hidden name."""
    primary = root / "todo" / MANIFEST_NAME
    if primary.is_file():
        return primary
    legacy = root / "todo" / MANIFEST_NAME_LEGACY
    if legacy.is_file():
        return legacy
    return primary


def load_manifest(root: Path) -> dict[str, Any]:
    path = manifest_path(root)
    if not path.is_file():
        todo = root / "todo"
        listing = "(todo/ missing)"
        if todo.is_dir():
            entries = sorted(p.name for p in todo.iterdir())
            listing = ", ".join(entries) if entries else "(empty)"
        raise ImportError_(
            f"Missing {root / 'todo' / MANIFEST_NAME} "
            f"(also checked legacy {MANIFEST_NAME_LEGACY}). "
            f"Run without --build-only first, or ensure the prepare artifact "
            f"was downloaded. todo/ contains: {listing}"
        )
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Import a conda-forge package into todo/, recursively preparing "
            "missing dependencies, then build and upload to scns."
        )
    )
    p.add_argument(
        "package",
        help="Package name (conda-forge output or feedstock name)",
    )
    p.add_argument(
        "--target-platform",
        default=os.environ.get("TARGET_PLATFORM", "linux-64"),
        help="Target platform for rattler-build (default: linux-64)",
    )
    p.add_argument(
        "--no-upload",
        action="store_true",
        help="Prepare and build but do not upload to scns",
    )
    p.add_argument(
        "--token",
        default=os.environ.get("PREFIX_DEV_TOKEN"),
        help="prefix.dev token (default: env PREFIX_DEV_TOKEN)",
    )
    p.add_argument(
        "--prepare-only",
        action="store_true",
        help="Only resolve/prep recipes into todo/; skip build and upload",
    )
    p.add_argument(
        "--build-only",
        action="store_true",
        help=(
            "Skip resolve/prep; build+upload feedstocks listed in "
            "todo/import-manifest.json (used by CI build matrix jobs)"
        ),
    )
    p.add_argument(
        "--scns-channel",
        default=SCNS_CHANNEL,
        help=f"Own channel URL (default: {SCNS_CHANNEL})",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    pkg = args.package.strip()
    if not pkg or not PACKAGE_NAME_RE.match(pkg):
        print(
            f"Error: invalid package name {pkg!r}. "
            f"Allowed: letters, numbers, dots, underscores, hyphens.",
            file=sys.stderr,
        )
        return 1

    if args.prepare_only and args.build_only:
        print("Error: --prepare-only and --build-only are mutually exclusive.", file=sys.stderr)
        return 1

    scns_channel = args.scns_channel.rstrip("/")
    root = repo_root()

    try:
        # ----- build-only path (CI matrix jobs) -----
        if args.build_only:
            feedstocks: list[str] = []
            root_name = pkg
            # Prefer manifest file; fall back to IMPORT_FEEDSTOCKS env
            # (set from prepare job outputs) when the artifact omitted the file.
            try:
                manifest = load_manifest(root)
                feedstocks = list(manifest.get("feedstocks") or [])
                root_name = str(manifest.get("root_package") or pkg)
            except ImportError_ as manifest_err:
                env_fs = os.environ.get("IMPORT_FEEDSTOCKS", "").strip()
                if not env_fs:
                    raise manifest_err
                feedstocks = [f.strip() for f in env_fs.split(",") if f.strip()]
                print(
                    f"Warning: {manifest_err}\n"
                    f"Falling back to IMPORT_FEEDSTOCKS={env_fs!r}",
                    flush=True,
                )
            if not feedstocks:
                raise ImportError_(
                    "Build-only mode needs feedstocks from "
                    f"todo/{MANIFEST_NAME} or IMPORT_FEEDSTOCKS."
                )
            print(
                f"==> Build-only for root {root_name!r} "
                f"on {args.target_platform}: {', '.join(feedstocks)}",
                flush=True,
            )
            container_build_and_upload(
                root,
                feedstocks,
                target_platform=args.target_platform,
                upload=not args.no_upload,
                prefix_token=args.token,
                scns_channel=scns_channel,
            )
            print("==> Done.", flush=True)
            return 0

        # ----- resolve + prep (+ optional local build) -----
        state = PrepareState(root=root, scns=ChannelIndex(channel=scns_channel))

        print(f"==> Checking conda-forge for {pkg!r}", flush=True)
        exists, detail = on_conda_forge(pkg)
        if not exists:
            raise ImportError_(
                f"Package {pkg!r} is not on conda-forge. Reason: {detail}"
            )
        print(f"    found: {detail}", flush=True)

        print(f"==> Checking scns ({scns_channel}) for {pkg!r}", flush=True)
        if state.scns.has(pkg):
            print(
                f"Package {pkg!r} already exists on {scns_channel}. Nothing to do.",
                flush=True,
            )
            return 0
        print("    not on scns; will import.", flush=True)

        print(f"==> Preparing {pkg!r} and missing dependencies", flush=True)
        ensure_package(state, pkg, via="(root)")
        if not state.prepared:
            fs = resolve_feedstock(pkg)
            prep_feedstock(state, fs)
            state.prepared[fs] = "root package"
            state.order.append(fs)
            deps = extract_deps_from_recipe(state.todo_dir(fs) / "recipe.yaml")
            for dep in sorted(deps):
                ensure_package(state, dep, via=fs)

        verify_all_deps_resolvable(state)

        print("==> Prepared feedstocks (build order):", flush=True)
        for fs in state.order:
            print(f"    - {fs}: {state.prepared[fs]}", flush=True)

        manifest = {
            "root_package": pkg,
            "feedstocks": state.order,
            "reasons": state.prepared,
            "target_platform": args.target_platform,
        }
        # Non-hidden path: GitHub upload-artifact drops dotfiles by default.
        out_path = root / "todo" / MANIFEST_NAME
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        # Remove legacy hidden name if present so only one source of truth.
        legacy = root / "todo" / MANIFEST_NAME_LEGACY
        if legacy.is_file():
            legacy.unlink()
        print(f"Wrote {out_path}", flush=True)

        if args.prepare_only:
            print("Prepare-only mode: skipping build/upload.", flush=True)
            return 0

        print(
            f"==> Building in pixi container for {args.target_platform}",
            flush=True,
        )
        container_build_and_upload(
            root,
            state.order,
            target_platform=args.target_platform,
            upload=not args.no_upload,
            prefix_token=args.token,
            scns_channel=scns_channel,
        )
        print("==> Done.", flush=True)
        return 0

    except ImportError_ as e:
        print(f"Error: {e}", file=sys.stderr, flush=True)
        return 1
    except subprocess.CalledProcessError as e:
        print(
            f"Error: command failed with exit {e.returncode}: {e.cmd}",
            file=sys.stderr,
            flush=True,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
