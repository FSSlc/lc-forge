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
from pathlib import Path, PurePosixPath
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
# Package names with a jinja fragment glued straight onto them
# (gxx_impl_${{ cross_target_platform }}, cross-python_${{ target_platform }}).
# The rendered names always carry a platform suffix (gxx_impl_linux-64, ...),
# so the bare `name_` left after jinja neutralization is never a real package.
# Matches both the raw `${{ ... }}` form and the `__JINJA__` placeholder used
# by extract_deps_from_recipe, and only when the fragment is glued on with no
# version operator (==, >=, space, ...) in between, so legitimate MatchSpecs
# like `pybind11-global ==${{ version }} *_${{ build_number }}` are untouched.
GLUED_JINJA_RE = re.compile(
    r"^[- '\"]*[A-Za-z0-9_.-]*?_\s*(?:\$\{\{[^}]*\}\}|__JINJA__)"
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
    _negative: set[str] = field(default_factory=set, init=False, repr=False)

    def _load_via_conda_search(self, name: str) -> bool:
        """Exact point query via `conda search --json` (prefix.dev auth/HMAC).

        Do **not** trust bare exit codes: some conda versions treat the query as
        a glob and/or return 0 with an empty result. Require an exact key match
        for `name` in the JSON payload.
        """
        cmd = [
            "conda",
            "search",
            "-c",
            self.channel,
            "--override-channels",
            "--json",
            # Anchor as a MatchSpec name only (no glob).
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

        raw = (proc.stdout or "").strip() or (proc.stderr or "").strip()
        if not raw:
            return False
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Fall back to exit code only when JSON is unavailable, but still
            # require stdout to look like a hit table containing the name.
            if proc.returncode != 0:
                return False
            return bool(re.search(rf"(?m)^\s*{re.escape(name)}\s+", proc.stdout or ""))

        if not isinstance(data, dict):
            return False
        if data.get("error") or data.get("exception_name"):
            return False
        # conda search --json → { "pkgname": [ {...}, ... ], ... }
        hits = data.get(name)
        if isinstance(hits, list) and len(hits) > 0:
            return True
        return False

    def _try_bulk_load(self) -> set[str] | None:
        """Best-effort bulk load; returns None if repodata is not directly fetchable."""
        names: set[str] = set()
        loaded_any = False
        # Prefer the public channel URL (HMAC redirect). Direct packages.prefix.dev
        # without a signed URL returns 403.
        for subdir in self.subdirs:
            url = f"{self.channel.rstrip('/')}/{subdir}/repodata.json"
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
        if name in self._negative:
            return False
        if name in self._names:
            return True
        # Point query (cache both positive and negative hits).
        if self._load_via_conda_search(name):
            self._names.add(name)
            return True
        self._negative.add(name)
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
    # Internal cross-compile helper, e.g. `cross-python_${{ target_platform }}`
    # in `if: build_platform != target_platform` branches. After jinja
    # neutralization this collapses to the bare `cross-python_`, which is never
    # a real package; the actual packages are always cross-python_<platform>
    # (cross-python_linux-64, ...). This repo builds natively only, and on the
    # rare cross case rattler-build pulls the real names from conda-forge, so
    # never import it as a feedstock.
    if name == "cross-python_":
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
    # name_${{ ... }} template remnants (raw form; the yaml-walk path also
    # pre-filters the __JINJA__ form before calling this).
    if GLUED_JINJA_RE.match(spec):
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

    # Native-build guards. This repo's CI builds linux-64 on x86_64 and
    # linux-aarch64 on arm64 runners, and local builds are always native, so
    # build_platform == target_platform. Many conda-forge recipes gate
    # cross-python / toolchain setup on `build_platform != target_platform`;
    # those branches are inactive here and must not count as linux deps.
    bare = expr.strip("()").strip()
    if bare in {
        "build_platform != target_platform",
        "target_platform != build_platform",
    }:
        return False
    if bare in {
        "build_platform == target_platform",
        "target_platform == build_platform",
    }:
        return True

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

        # rattler-build v1 uses run_constraints; conda meta.yaml uses
        # run_constrained. Both are real package lists we should resolve.
        interesting_keys = {
            "build",
            "host",
            "run",
            "run_constraints",
            "run_constrained",
            "test",
        }
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
            # name___JINJA__: jinja glued onto the package name, e.g.
            # gxx_impl_${{ cross_target_platform }}. The bare name_ is never a
            # real package, so skip before placeholder removal turns it into a
            # plain (but fake) name.
            if GLUED_JINJA_RE.match(spec):
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
            r"^(\s*)(build|host|run|run_constraints|run_constrained)\s*:"
            r"\s*(?:#.*)?$"
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
    secret: str | None = None,
) -> subprocess.CompletedProcess[str]:
    printable = cmd if isinstance(cmd, str) else " ".join(shlex.quote(c) for c in cmd)
    if secret:
        # The command echo and any error message below would otherwise leak the
        # token into the CI log / local terminal scrollback.
        printable = printable.replace(secret, "***")
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
# AI-assisted fixing (OpenAI-compatible chat/completions)
# ---------------------------------------------------------------------------

# Config env vars. The API key is read only from the environment, lives only in
# the Authorization header, and is never printed or included in error messages.
AI_ENV_VARS = ("AI_API_BASE_URL", "AI_API_KEY", "AI_MODEL_NAME")


def ai_configured() -> bool:
    return all(os.environ.get(v) for v in AI_ENV_VARS)


def _ai_endpoint() -> str:
    base = os.environ["AI_API_BASE_URL"].rstrip("/")
    if base.endswith("/chat/completions"):
        return base
    return f"{base}/chat/completions"


def ai_chat(system: str, user: str, *, json_mode: bool = False) -> str:
    """POST an OpenAI-compatible chat completion and return the message content."""
    if not ai_configured():
        raise ImportError_(
            "AI not configured (AI_API_BASE_URL / AI_API_KEY / AI_MODEL_NAME)"
        )
    payload: dict[str, Any] = {
        "model": os.environ["AI_MODEL_NAME"],
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.0,
        "max_tokens": 8192,
    }
    if json_mode:
        payload["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        _ai_endpoint(),
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {os.environ['AI_API_KEY']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        raise ImportError_(f"AI API HTTP {e.code}: {body}") from e
    except urllib.error.URLError as e:
        raise ImportError_(f"AI API network error: {e}") from e
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as e:
        raise ImportError_(f"AI API unexpected response: {e}") from e


_AI_SYSTEM_META = (
    "You convert conda-forge meta.yaml files into rattler-build recipe.yaml "
    "(v1 schema). Output only valid YAML, no markdown fences, no commentary."
)

_AI_SYSTEM_BUILD = (
    "You fix conda-forge recipes (rattler-build recipe.yaml / build.sh / patches). "
    'Respond with a single JSON object shaped '
    '{"files": {"<feedstock>/<relative-path>": "<full new file content>", ...}, '
    '"note": "..."}. Only include files you actually change. Paths must be '
    "relative, under the feedstock directory, with no '..' and no absolute paths."
)


def ai_fix_meta(meta_text: str, crm_error: str = "") -> str:
    """Return a recipe.yaml (text) converted from a meta.yaml crm failed on."""
    user = (
        "Convert this meta.yaml to a rattler-build recipe.yaml (v1 schema). "
        "Preserve package name, version, source urls and sha256, build script, "
        "build/host/run requirements, and tests. Use `requirements:` with "
        "build/host/run lists and a `tests:` block where possible.\n\n"
        f"crm conversion error (if any):\n{crm_error or '(not captured)'}\n\n"
        f"meta.yaml:\n{meta_text}"
    )
    return ai_chat(_AI_SYSTEM_META, user)


def ai_fix_build(feedstock: str, files_snapshot: str, log_tail: str) -> str:
    """Return JSON text proposing file changes for a failed build."""
    user = (
        f"The rattler-build build of recipe {feedstock!r} failed. "
        f"Every path you return must start with {feedstock}/.\n\n"
        f"Recipe files:\n\n{files_snapshot}\n\n"
        f"Build log (tail):\n\n{log_tail}\n\n"
        "Diagnose the compile/link/test error and return the JSON object with "
        "the files to change."
    )
    return ai_chat(_AI_SYSTEM_BUILD, user, json_mode=True)


def validate_recipe_yaml(text: str) -> bool:
    """Structural sanity check without PyYAML: has a package/name section."""
    if not text or not text.strip():
        return False
    # `package:` followed by an indented `name:` line, or a bare top-level name.
    m = re.search(r"(?m)^package:\s*\n(?:[ \t]+.*\n)*?[ \t]+name:\s*(\S+)", text)
    if m is None:
        m = re.search(r"(?m)^name:\s*(\S+)", text)
    if m is None:
        return False
    raw = m.group(1).strip().strip("\"'")
    if not raw or raw.startswith("${{"):
        return False
    return PACKAGE_NAME_RE.match(raw) is not None


def ai_apply_files(
    root: Path,
    feedstocks: Iterable[str],
    files: dict[str, str],
) -> list[str]:
    """Write AI-proposed files under todo/<feedstock>/…, refusing path traversal."""
    allowed = {fs: (root / "todo" / fs).resolve() for fs in feedstocks}
    applied: list[str] = []
    for raw_path, content in files.items():
        p = PurePosixPath(raw_path)
        if p.is_absolute() or not p.parts or ".." in p.parts:
            raise ImportError_(f"unsafe AI path {raw_path!r}")
        fs = p.parts[0]
        base = allowed.get(fs)
        if base is None:
            raise ImportError_(f"unknown feedstock {fs!r} in AI path {raw_path!r}")
        rel = Path(*p.parts[1:])
        if not rel.parts or ".." in rel.parts:
            raise ImportError_(f"unsafe AI path {raw_path!r}")
        dest = (base / rel).resolve()
        if dest != base and base not in dest.parents:
            raise ImportError_(f"AI path escapes recipe dir: {raw_path!r}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        applied.append(raw_path)
    return applied


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
    # Root package name that must be built even if scns already has it (--force).
    force_packages: set[str] = field(default_factory=set)
    visiting: set[str] = field(default_factory=set)
    order: list[str] = field(default_factory=list)  # feedstock prep order
    # feedstock -> prep error message (clone / crm conversion). The download
    # keeps going past these; they are reported together and AI-fixed when
    # configured, instead of aborting the whole import on the first failure.
    failed_feedstocks: dict[str, str] = field(default_factory=dict)

    def todo_dir(self, feedstock: str) -> Path:
        return self.root / "todo" / feedstock


def prep_feedstock(state: PrepareState, feedstock: str) -> Path:
    """Run prep.sh --strict <feedstock>; return path to todo/<feedstock>.

    On failure the partially cloned recipe dir (meta.yaml etc.) is left in place
    so a human can inspect and fix the crm conversion afterwards.
    """
    script = state.root / "scripts" / "prep.sh"
    todo = state.todo_dir(feedstock)
    run(["bash", str(script), "--strict", feedstock], cwd=state.root)
    recipe = todo / "recipe.yaml"
    if not recipe.is_file():
        raise ImportError_(
            f"prep.sh --strict {feedstock} finished but {recipe} is missing. "
            f"crm conversion likely failed; see prep.sh output above."
        )
    return todo


def ensure_package(state: PrepareState, pkg: str, *, via: str) -> None:
    """Make sure package `pkg` is on scns or will be built from a todo recipe."""
    # Packages listed in force_packages must still be prepared/built even when
    # scns already has them (used for the root package under --force).
    if pkg in state.satisfied:
        return
    if pkg not in state.force_packages and state.scns.has(pkg):
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
            todo = state.todo_dir(feedstock)
            if feedstock in state.failed_feedstocks:
                # This feedstock already failed prep via another output; do not
                # re-run it or duplicate the recorded error.
                return
            # Skip prep only if the *package* is already on scns (checked above)
            # or feedstock recipe already in todo from this/previous step.
            if not (todo / "recipe.yaml").is_file():
                try:
                    prep_feedstock(state, feedstock)
                except ImportError_ as e:
                    # Do not abort the whole download: record this recipe's
                    # failure and keep resolving the remaining dependencies.
                    # prep.sh --strict leaves meta.yaml in place for AI/human
                    # to fix the crm conversion afterwards.
                    state.failed_feedstocks[feedstock] = str(e)
                    return
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


def recipe_package_names(recipe: Path) -> set[str]:
    """Best-effort package name(s) produced by a recipe.yaml (single or multi-output)."""
    names: set[str] = set()
    pname = package_name_from_recipe(recipe)
    if pname:
        names.add(pname)
    text = recipe.read_text(encoding="utf-8")
    for m in re.finditer(r"(?m)^\s+-\s+package:\s*\n\s+name:\s*(\S+)", text):
        raw = m.group(1).strip().strip("\"'")
        if PACKAGE_NAME_RE.match(raw):
            names.add(raw)
    for m in re.finditer(r"(?m)^\s+-\s+name:\s*(\S+)", text):
        raw = m.group(1).strip().strip("\"'")
        if PACKAGE_NAME_RE.match(raw) and not raw.startswith("${{"):
            names.add(raw)
    return names


def ai_fix_prep_failures(state: PrepareState, max_rounds: int = 2) -> None:
    """Attempt to AI-convert failed meta.yaml files; recurse into their deps."""
    if not ai_configured():
        return
    for _ in range(max_rounds):
        changed = False
        for feedstock in sorted(list(state.failed_feedstocks)):
            todo = state.todo_dir(feedstock)
            meta = todo / "meta.yaml"
            if not meta.is_file() or (todo / "recipe.yaml").is_file():
                continue
            print(f"==> AI fix: converting {feedstock}/meta.yaml", flush=True)
            try:
                recipe_text = ai_fix_meta(meta.read_text(encoding="utf-8"))
                if not validate_recipe_yaml(recipe_text):
                    print("    AI output is not valid recipe.yaml; keeping failure", flush=True)
                    continue
                (todo / "recipe.yaml").write_text(recipe_text, encoding="utf-8")
                state.prepared[feedstock] = "AI-fixed recipe.yaml"
                if feedstock not in state.order:
                    state.order.append(feedstock)
                del state.failed_feedstocks[feedstock]
                changed = True
                deps = extract_deps_from_recipe(todo / "recipe.yaml")
                print(
                    f"    AI-fixed {feedstock}; deps: {', '.join(sorted(deps)) or '(none)'}",
                    flush=True,
                )
                for dep in sorted(deps):
                    ensure_package(state, dep, via=feedstock)
            except Exception as e:  # network, API, JSON, traversal, ...
                print(f"    AI fix failed for {feedstock}: {e}", flush=True)
        if not changed:
            break


def verify_all_deps_resolvable(state: PrepareState) -> None:
    """Final pass: every dep is on scns or in the prepared local set."""
    local_names: set[str] = set(state.prepared)
    for fs in state.prepared:
        recipe = state.todo_dir(fs) / "recipe.yaml"
        if recipe.is_file():
            local_names |= recipe_package_names(recipe)

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

# Test-failure markers to scan for in the build log after a "successful" build.
# rattler-build --continue-on-failure still exits 0 when a recipe's test script
# fails, so the exit code alone is not a reliable signal before uploading.
TEST_FAILURE_RES = (
    re.compile(r"× error Script failed with status"),
    re.compile(r"× error Script execution failed"),
)


def fail_if_test_failures(log_file: Path, target_platform: str) -> None:
    """Abort if the build log shows test failures, before anything is uploaded.

    Must run between the build and the upload phase: the workflow's own log
    scan (in .github/workflows/import-recipe.yml) only runs after the upload
    step, so it can flag the failure but cannot stop the upload.
    """
    if not log_file.is_file():
        return
    text = log_file.read_text(errors="replace")
    for pattern in TEST_FAILURE_RES:
        if pattern.search(text):
            raise ImportError_(
                f"Test failures detected in {log_file} for {target_platform} "
                f"(matched {pattern.pattern!r}); aborting before upload."
            )


AI_MAX_FIX_ROUNDS = int(os.environ.get("AI_MAX_FIX_ROUNDS", "2"))

# Cap the recipe snapshot handed to the AI so one huge patch cannot blow up the
# prompt; the request body must stay well below provider limits.
AI_SNAPSHOT_MAX_CHARS = 200_000


def recipe_file_snapshot(root: Path, feedstock: str) -> str:
    """Return every text file of todo/<feedstock> labelled with its relative path."""
    d = root / "todo" / feedstock
    parts: list[str] = []
    total = 0
    for f in sorted(p for p in d.iterdir() if p.is_file()):
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if total + len(text) > AI_SNAPSHOT_MAX_CHARS:
            print(
                f"Warning: recipe snapshot truncated, skipping {feedstock}/{f.name}",
                flush=True,
            )
            break
        parts.append(f"# --- {feedstock}/{f.name} ---\n{text}\n")
        total += len(text)
    return "\n".join(parts)


def ai_fix_build_failures(
    root: Path, feedstock: str, log_file: Path
) -> tuple[list[str], dict[Path, str | None]]:
    """Ask the AI to diagnose one failed build and rewrite this recipe's files.

    Returns the files it changed plus a backup of their previous content (None
    for files that did not exist), so the caller can revert the edit if the
    rebuild still fails. An empty file list means "no usable fix". Errors in the
    AI round trip raise ImportError_ so the caller can report and give up on
    this recipe without losing the original build error.
    """
    if not ai_configured():
        return [], {}
    snapshot = recipe_file_snapshot(root, feedstock)
    log_tail = (
        log_file.read_text(encoding="utf-8", errors="replace")[-40000:]
        if log_file.is_file()
        else ""
    )
    raw = ai_fix_build(feedstock, snapshot, log_tail).strip()
    # Tolerate markdown code fences some OpenAI-compatible providers still emit.
    if raw.startswith("```"):
        lines = raw.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        raw = "\n".join(lines).strip()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        raise ImportError_(
            f"AI build-fix returned invalid JSON: {e}; raw={raw[:200]!r}"
        ) from e
    files = payload.get("files") if isinstance(payload, dict) else None
    if not isinstance(files, dict) or not files:
        return [], {}
    note = payload.get("note") if isinstance(payload, dict) else None
    if note:
        print(f"AI diagnosis for {feedstock}: {note}", flush=True)
    files = {p: c for p, c in files.items() if isinstance(c, str)}
    # Never let the AI hand us a recipe.yaml that is structurally broken; the
    # build would just fail again with a less informative error.
    recipe_key = f"{feedstock}/recipe.yaml"
    if recipe_key in files and not validate_recipe_yaml(files[recipe_key]):
        print(
            f"Warning: AI build-fix produced an invalid recipe.yaml for {feedstock}; "
            f"ignoring that file.",
            file=sys.stderr,
            flush=True,
        )
        files.pop(recipe_key)
    if not files:
        return [], {}
    # Snapshot the pre-AI content of every file we are about to touch so a fix
    # that does not make the build pass can be reverted before it is committed.
    backup: dict[Path, str | None] = {}
    for raw_path in files:
        dest = root / "todo" / Path(*PurePosixPath(raw_path).parts)
        try:
            backup[dest] = (
                dest.read_text(encoding="utf-8") if dest.is_file() else None
            )
        except (OSError, UnicodeDecodeError):
            print(
                f"Warning: cannot back up {raw_path!r} for {feedstock}; "
                f"its AI edit will not be reverted.",
                file=sys.stderr,
                flush=True,
            )
    applied = ai_apply_files(root, [feedstock], files)
    print(
        f"AI build-fix applied {len(applied)} file(s) for {feedstock}: "
        f"{', '.join(applied)}",
        flush=True,
    )
    return applied, backup


def revert_recipe_files(backup: dict[Path, str | None]) -> None:
    """Undo AI edits recorded by ai_fix_build_failures (None means created)."""
    for path, text in backup.items():
        try:
            if text is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(text, encoding="utf-8")
        except OSError as exc:
            print(
                f"Warning: cannot revert {path}: {exc}",
                file=sys.stderr,
                flush=True,
            )


def write_built_feedstocks(
    root: Path, feedstocks: list[str], target_platform: str
) -> None:
    """Record which feedstocks produced a .conda artifact for this target."""
    output_dir = root / "output"
    stems = {f.name for f in output_dir.rglob("*.conda")}
    built: list[str] = []
    for fs in feedstocks:
        recipe = root / "todo" / fs / "recipe.yaml"
        names = recipe_package_names(recipe) if recipe.is_file() else {fs}
        if not names:
            names = {fs}
        if any(any(stem.startswith(n + "-") for stem in stems) for n in names):
            built.append(fs)
    path = output_dir / f".built-feedstocks-{target_platform}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {"target_platform": target_platform, "feedstocks": built}, indent=2
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"Built feedstocks for {target_platform}: {', '.join(built) or '(none)'}",
        flush=True,
    )


# Stage dir used to isolate one recipe per rattler-build invocation, so
# --recipe-dir does not pick up unrelated packages already sitting in todo/.
BUILD_STAGE_REL = "todo/.import-stage"

# rattler-build runs as root inside the pixi container and writes root-owned
# files under the bind-mounted workspace. Always chown back to HOST_UID/HOST_GID
# (injected by start_img.sh) so the GHA runner can read logs/ and zip
# output/**/*.conda for upload-artifact.
FIX_WORKSPACE_OWNER_SNIPPET = r"""
fix_workspace_owner() {
  local uid="${HOST_UID:-}"
  local gid="${HOST_GID:-}"
  if [[ -z "$uid" || -z "$gid" ]]; then
    echo "Warning: HOST_UID/HOST_GID unset; leaving root-owned build outputs" >&2
    return 0
  fi
  # -h: do not follow symlinks out of these trees
  for d in output logs todo/.import-stage; do
    if [[ -e "$d" ]]; then
      chown -Rh "${uid}:${gid}" "$d" || true
    fi
  done
}
trap fix_workspace_owner EXIT
"""


def single_recipe_build_script(
    fs: str,
    log_rel: str,
    *,
    target_platform: str,
    scns_channel: str = SCNS_CHANNEL,
) -> str:
    """Build exactly one recipe; its own log keeps AI diagnosis targeted."""
    stage_rel = BUILD_STAGE_REL
    parts = [
        "set -Eeuo pipefail",
        FIX_WORKSPACE_OWNER_SNIPPET,
        "mkdir -p logs output",
        f"rm -rf {shlex.quote(stage_rel)}",
        f"mkdir -p {shlex.quote(stage_rel)}",
        # Symlink todo/<fs> into the staging dir (relative from stage → todo).
        f"ln -sfn ../{shlex.quote(fs)} {shlex.quote(stage_rel)}/{shlex.quote(fs)}",
        f'echo "===== Building {fs} for {target_platform} ====="',
        # Disable -e around the pipeline so we can inspect PIPESTATUS[0]
        # (rattler-build) even when --continue-on-failure still exits non-zero.
        "set +e",
        (
            "rattler-build build --continue-on-failure --experimental "
            # local only: prepared recipes must actually build even if a stale
            # scns entry exists or channel detection disagreed. Upload still
            # uses --skip-existing against the remote channel.
            f"-m ./conda_build_config.yaml --skip-existing=local "
            f"--target-platform={shlex.quote(target_platform)} "
            # -c ./output lets earlier recipes of this run satisfy later ones.
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
        f'echo "{fs} built successfully for {target_platform}"',
    ]
    return "\n".join(parts)


def build_one_recipe(
    root: Path,
    fs: str,
    *,
    target_platform: str,
    log_file: Path,
    scns_channel: str = SCNS_CHANNEL,
) -> None:
    """Build todo/<fs> alone inside the pixi container, logging to log_file."""
    script = single_recipe_build_script(
        fs,
        str(log_file.relative_to(root)),
        target_platform=target_platform,
        scns_channel=scns_channel,
    )
    run(["bash", str(root / "scripts" / "start_img.sh"), "--run", script], cwd=root)


def upload_output_packages(root: Path, *, prefix_token: str) -> None:
    """Upload every .conda under output/ to scns (channel dedupes)."""
    upload_parts = [
        "set -Eeuo pipefail",
        FIX_WORKSPACE_OWNER_SNIPPET,
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
        ["bash", str(root / "scripts" / "start_img.sh"), "--run", "\n".join(upload_parts)],
        cwd=root,
        secret=prefix_token,
    )


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

    logs_dir = root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    # Aggregate log: one file per target for the CI summary / log scan.
    log_file = logs_dir / f"build-{target_platform}.log"
    log_file.write_text("", encoding="utf-8")
    output_dir = root / "output"
    output_dir.mkdir(parents=True, exist_ok=True)

    for fs in feedstocks:
        recipe = root / "todo" / fs / "recipe.yaml"
        if not recipe.is_file():
            raise ImportError_(
                f"Cannot build {fs!r}: missing {recipe}. "
                f"Did prepare step upload the todo/ artifact?"
            )

    if ai_configured():
        print(
            f"AI build-fix enabled ({os.environ['AI_MODEL_NAME']}), "
            f"up to {AI_MAX_FIX_ROUNDS} build attempt(s) per recipe",
            flush=True,
        )
    else:
        print(
            "AI build-fix disabled: AI_API_BASE_URL / AI_API_KEY / AI_MODEL_NAME "
            "is not set, so build failures are only reported.",
            flush=True,
        )

    failures: dict[str, str] = {}
    try:
        for fs in feedstocks:
            fs_log = logs_dir / f"build-{target_platform}-{fs}.log"
            error = ""
            # Original content of the files the AI touched, so a fix that does
            # not make the build pass is reverted instead of being committed.
            pristine: dict[Path, str | None] = {}
            for attempt in range(1, AI_MAX_FIX_ROUNDS + 1):
                try:
                    build_one_recipe(
                        root,
                        fs,
                        target_platform=target_platform,
                        log_file=fs_log,
                        scns_channel=scns_channel,
                    )
                    # --continue-on-failure can leave the exit status at 0 while a
                    # test script failed; the workflow's own log scan only runs
                    # after upload, so check here.
                    fail_if_test_failures(fs_log, target_platform)
                    error = ""
                    break
                except ImportError_ as exc:
                    error = str(exc)
                    print(
                        f"Build of {fs!r} failed "
                        f"(attempt {attempt}/{AI_MAX_FIX_ROUNDS}): {error}",
                        flush=True,
                    )
                    if attempt >= AI_MAX_FIX_ROUNDS or not ai_configured():
                        break
                    print(f"Asking AI to diagnose the {fs!r} build failure...", flush=True)
                    try:
                        changed, backup = ai_fix_build_failures(root, fs, fs_log)
                    except ImportError_ as ai_exc:
                        print(
                            f"Warning: AI build-fix for {fs!r} failed: {ai_exc}",
                            file=sys.stderr,
                            flush=True,
                        )
                        break
                    if not changed:
                        print(
                            f"AI proposed no usable change for {fs!r}; "
                            f"keeping the original build error.",
                            flush=True,
                        )
                        break
                    for path, text in backup.items():
                        pristine.setdefault(path, text)
                    print(
                        f"AI changed {len(changed)} file(s) for {fs!r}; rebuilding "
                        f"(attempt {attempt + 1}/{AI_MAX_FIX_ROUNDS})",
                        flush=True,
                    )
            if error and pristine:
                revert_recipe_files(pristine)
                print(
                    f"Reverted AI changes for {fs!r}: it still fails to build, so "
                    f"the prepared recipe is left untouched.",
                    flush=True,
                )
            with log_file.open("a", encoding="utf-8") as fh:
                fh.write(f"===== {fs} =====\n")
                if fs_log.is_file():
                    fh.write(fs_log.read_text(encoding="utf-8", errors="replace"))
                fh.write("\n")
            if error:
                failures[fs] = error

        conda_files = list(output_dir.rglob("*.conda"))
        if not conda_files:
            print(
                "Warning: no .conda artifacts under output/. "
                "All packages may have been skipped as existing.",
                flush=True,
            )

        if not upload:
            print("Upload skipped (--no-upload).", flush=True)
        elif not prefix_token:
            raise ImportError_(
                "Build finished but PREFIX_DEV_TOKEN / --token is not set; "
                "cannot upload to scns."
            )
        else:
            upload_output_packages(root, prefix_token=prefix_token)
    finally:
        write_built_feedstocks(root, feedstocks, target_platform)

    # Report every recipe that still failed after the AI rounds; the artifacts
    # that did build were already uploaded so a later run can reuse them.
    if failures:
        details = "\n".join(
            f"  [{i}] {fs}: {msg}"
            for i, (fs, msg) in enumerate(sorted(failures.items()), 1)
        )
        raise ImportError_(
            f"{len(failures)}/{len(feedstocks)} recipe(s) failed to build for "
            f"{target_platform} even after AI fix:\n{details}"
        )


# rattler-build prints this before compiling each recipe of a bulk build.
BULK_RECIPE_MARKER_RE = re.compile(r"Processing recipe at path: .*?/([^/]+)/[^/]*$")


def extract_recipe_log_section(bulk_log: Path, feedstock: str) -> str:
    """Slice the bulk build log down to todo/<feedstock>/'s own output.

    build.yml builds all of todo/ in one rattler-build call, so a bulk log
    interleaves every recipe; handing it to the AI whole would diagnose another
    recipe's error. Sections start at the per-recipe marker.
    """
    if not bulk_log.is_file():
        return ""
    lines = bulk_log.read_text(encoding="utf-8", errors="replace").splitlines()
    section: list[str] = []
    current = ""
    for line in lines:
        match = BULK_RECIPE_MARKER_RE.search(line)
        if match:
            current = match.group(1)
        if current == feedstock:
            section.append(line)
    if section:
        return "\n".join(section) + "\n"
    # No marker (truncated log / parse error before the marker): keep every line
    # that names the feedstock directory instead of returning nothing.
    return "".join(f"{line}\n" for line in lines if f"/{feedstock}/" in line)


def repair_failed_builds(
    root: Path,
    *,
    target_platform: str,
    status_file: Path,
    bulk_log: Path,
    prefix_token: str | None,
    upload: bool,
    scns_channel: str = SCNS_CHANNEL,
) -> list[str]:
    """One bounded AI repair round for the recipes build.yml classified FAILED.

    build.yml's push trigger rebuilds whatever the import left in todo/, so a
    recipe that already exhausted its AI rounds there would fail identically on
    every later push. This gives that path the same AI diagnosis + single-recipe
    rebuild, limited to one fix round: a failed repair is reverted and reported.
    """
    if not status_file.is_file():
        raise ImportError_(f"Missing {status_file}; nothing to repair.")

    statuses: dict[str, str] = {}
    for line in status_file.read_text(encoding="utf-8").splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2 and parts[1].strip():
            statuses[parts[1].strip()] = parts[0].strip()

    failed = [fs for fs, status in statuses.items() if status == "FAILED"]
    if not failed:
        print(f"No FAILED recipe in {status_file}; nothing to repair.", flush=True)
        return []
    if not ai_configured():
        print(
            "AI build-fix disabled: AI_API_BASE_URL / AI_API_KEY / AI_MODEL_NAME "
            f"is not set, so the {len(failed)} failed recipe(s) are only reported.",
            flush=True,
        )
        return []

    print(
        f"AI build-fix enabled ({os.environ['AI_MODEL_NAME']}), "
        f"one repair round for {len(failed)} recipe(s): {', '.join(failed)}",
        flush=True,
    )

    logs_dir = root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    repaired: list[str] = []
    for fs in failed:
        if not (root / "todo" / fs / "recipe.yaml").is_file():
            print(
                f"Warning: todo/{fs}/recipe.yaml is missing; skipping repair.",
                file=sys.stderr,
                flush=True,
            )
            continue

        fs_log = logs_dir / f"build-{target_platform}-{fs}.log"
        fs_log.write_text(extract_recipe_log_section(bulk_log, fs), encoding="utf-8")
        print(f"Asking AI to diagnose the {fs!r} build failure...", flush=True)
        try:
            changed, backup = ai_fix_build_failures(root, fs, fs_log)
        except ImportError_ as exc:
            print(
                f"Warning: AI build-fix for {fs!r} failed: {exc}",
                file=sys.stderr,
                flush=True,
            )
            continue
        if not changed:
            print(
                f"AI proposed no usable change for {fs!r}; "
                f"keeping the original build error.",
                flush=True,
            )
            continue

        print(f"AI changed {len(changed)} file(s) for {fs!r}; rebuilding", flush=True)
        try:
            build_one_recipe(
                root,
                fs,
                target_platform=target_platform,
                log_file=fs_log,
                scns_channel=scns_channel,
            )
            fail_if_test_failures(fs_log, target_platform)
        except ImportError_ as exc:
            revert_recipe_files(backup)
            print(
                f"Rebuild of {fs!r} still failed: {exc}\n"
                f"Reverted AI changes for {fs!r}: the recipe is left untouched.",
                file=sys.stderr,
                flush=True,
            )
            continue

        statuses[fs] = "BUILT"
        repaired.append(fs)
        print(f"Repaired {fs!r}: it now builds for {target_platform}.", flush=True)

    status_file.write_text(
        "".join(f"{statuses[fs]} {fs}\n" for fs in statuses), encoding="utf-8"
    )
    if repaired:
        # The repaired recipes produced new artifacts out of band, so the
        # built-feedstocks record must include them (import-recipe.yml archives
        # only feedstocks that appear in every target's record).
        record = root / "output" / f".built-feedstocks-{target_platform}.json"
        known: list[str] = []
        if record.is_file():
            try:
                known = list(
                    json.loads(record.read_text(encoding="utf-8")).get("feedstocks")
                    or []
                )
            except (OSError, json.JSONDecodeError):
                known = []
        write_built_feedstocks(
            root, sorted(set(known) | set(repaired)), target_platform
        )
    if repaired and upload and prefix_token:
        upload_output_packages(root, prefix_token=prefix_token)
    print(
        f"Repaired {len(repaired)}/{len(failed)} failed recipe(s) for "
        f"{target_platform}: {', '.join(repaired) or '(none)'}",
        flush=True,
    )
    return repaired


# Non-hidden names so actions/upload-artifact includes them by default
# (hidden/dotfiles are excluded unless include-hidden-files: true).
MANIFEST_NAME = "import-manifest.json"
MANIFEST_NAME_LEGACY = ".import-manifest.json"
STATUS_NAME = "import-status.json"


def manifest_path(root: Path) -> Path:
    """Return the import manifest path, preferring the non-hidden name."""
    primary = root / "todo" / MANIFEST_NAME
    if primary.is_file():
        return primary
    legacy = root / "todo" / MANIFEST_NAME_LEGACY
    if legacy.is_file():
        return legacy
    return primary


def status_path(root: Path) -> Path:
    return root / "todo" / STATUS_NAME


def write_status(root: Path, payload: dict[str, Any]) -> Path:
    """Always write a non-hidden status file for the workflow to read."""
    path = status_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {path}: {json.dumps(payload, sort_keys=True)}", flush=True)
    return path


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
        nargs="?",
        default="",
        help="Package name (conda-forge output or feedstock name); omitted with --repair-failed",
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
        "--repair-failed",
        action="store_true",
        help=(
            "Skip resolve/prep/build: for the recipes build.yml classified FAILED "
            "in .build-meta/<target>.txt, run one AI fix round and rebuild each "
            "(used by the .github/workflows/build.yml push retry path)"
        ),
    )
    p.add_argument(
        "--force",
        action="store_true",
        help=(
            "Prepare/build even if the package already exists on scns "
            "(ignore the early 'already on scns' exit)"
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

    if args.prepare_only and args.build_only:
        print("Error: --prepare-only and --build-only are mutually exclusive.", file=sys.stderr)
        return 1
    if args.repair_failed and (args.prepare_only or args.build_only):
        print(
            "Error: --repair-failed cannot be combined with "
            "--prepare-only / --build-only.",
            file=sys.stderr,
        )
        return 1
    if not args.repair_failed and (not pkg or not PACKAGE_NAME_RE.match(pkg)):
        print(
            f"Error: invalid package name {pkg!r}. "
            f"Allowed: letters, numbers, dots, underscores, hyphens.",
            file=sys.stderr,
        )
        return 1

    scns_channel = args.scns_channel.rstrip("/")
    root = repo_root()

    try:
        # ----- repair-only path (build.yml push retry) -----
        if args.repair_failed:
            meta_dir = root / ".build-meta"
            repair_failed_builds(
                root,
                target_platform=args.target_platform,
                status_file=meta_dir / f"{args.target_platform}.txt",
                bulk_log=meta_dir / f"rattler-{args.target_platform}.log",
                prefix_token=args.token,
                upload=not args.no_upload,
                scns_channel=scns_channel,
            )
            return 0

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
        on_scns = state.scns.has(pkg)
        print(f"    scns.has({pkg!r}) = {on_scns}", flush=True)
        if on_scns and not args.force:
            write_status(
                root,
                {
                    "root_package": pkg,
                    "already_on_scns": True,
                    "should_build": False,
                    "feedstocks": [],
                    "reason": f"already exists on {scns_channel}",
                },
            )
            print(
                f"Package {pkg!r} already exists on {scns_channel}. Nothing to do. "
                f"(Pass --force to prepare/build anyway.)",
                flush=True,
            )
            return 0
        if on_scns and args.force:
            print(
                f"    --force: ignoring existing scns package, will import/build.",
                flush=True,
            )
        else:
            print("    not on scns; will import and build.", flush=True)

        print(f"==> Preparing {pkg!r} and missing dependencies", flush=True)
        if args.force:
            state.force_packages.add(pkg)
        ensure_package(state, pkg, via="(root)")

        # Root feedstock always ends up in the build list unless its prep failed.
        root_fs = resolve_feedstock(pkg)
        if root_fs not in state.failed_feedstocks:
            if not state.prepared:
                # ensure_package may have short-circuited (e.g. scns.has flipped);
                # force prep of the root feedstock so we have something to build.
                print(
                    f"Root package was not recorded during ensure_package; "
                    f"forcing prep of feedstock {root_fs!r}",
                    flush=True,
                )
                prep_feedstock(state, root_fs)
                state.prepared[root_fs] = "root package"
                if root_fs not in state.order:
                    state.order.append(root_fs)
                deps = extract_deps_from_recipe(state.todo_dir(root_fs) / "recipe.yaml")
                for dep in sorted(deps):
                    ensure_package(state, dep, via=root_fs)
            if root_fs not in state.order:
                if root_fs not in state.prepared:
                    if not (state.todo_dir(root_fs) / "recipe.yaml").is_file():
                        prep_feedstock(state, root_fs)
                    state.prepared[root_fs] = "root package (forced into build list)"
                state.order.insert(0, root_fs)

        # Try to AI-fix failed meta.yaml conversions, then recurse their deps.
        ai_fix_prep_failures(state)

        print("==> Prepared feedstocks (build order):", flush=True)
        for fs in state.order:
            print(f"    - {fs}: {state.prepared.get(fs, '')}", flush=True)

        if state.failed_feedstocks:
            print(
                f"==> {len(state.failed_feedstocks)} recipe(s) failed to prepare "
                f"even after AI fix (crm conversion or feedstock clone). "
                f"They are skipped; fix them manually or re-run.",
                file=sys.stderr,
                flush=True,
            )
            for i, (fs, msg) in enumerate(sorted(state.failed_feedstocks.items()), 1):
                print(f"  [{i}] {fs}: {msg}", file=sys.stderr, flush=True)

        if not state.order:
            raise ImportError_(
                f"Nothing to build for {pkg!r}: no feedstock was prepared "
                f"(root feedstock {root_fs!r} failed prep)."
            )

        if not state.failed_feedstocks:
            verify_all_deps_resolvable(state)

        manifest = {
            "root_package": pkg,
            "feedstocks": state.order,
            "reasons": state.prepared,
            "failed_feedstocks": sorted(state.failed_feedstocks),
            "target_platform": args.target_platform,
            "should_build": True,
            "already_on_scns": False,
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

        write_status(
            root,
            {
                "root_package": pkg,
                "already_on_scns": False,
                "should_build": bool(state.order),
                "feedstocks": state.order,
                "failed_feedstocks": sorted(state.failed_feedstocks),
                "reason": (
                    f"prepared {len(state.order)} feedstock(s) for build; "
                    f"{len(state.failed_feedstocks)} failed"
                    if state.failed_feedstocks
                    else f"prepared {len(state.order)} feedstock(s) for build"
                ),
            },
        )

        if args.prepare_only:
            print(
                "Prepare-only mode: skipping build/upload. "
                f"CI build job should build: {', '.join(state.order)}",
                flush=True,
            )
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
