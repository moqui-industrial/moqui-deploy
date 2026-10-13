"""MCP server that runs the Python scripts of the agent skills.

Tools: list_skill_scripts, run_skill_script, write_file, read_file, list_files, and run_python only when RUN_PYTHON_ENABLED=true.
The skills are mounted read-only under SKILLS_DIR, a script is named by skill and file name and never by a path, the
interpreter is started without a shell, with a clean environment, limits on time, memory, processes and output, in a
workspace directory that is the only place anything can be written.
"""
import os
import re
import resource
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

SKILLS_DIR = Path(os.environ.get("SKILLS_DIR", "/skills")).resolve()
WORKSPACE = Path(os.environ.get("WORKSPACE_DIR", "/workspace")).resolve()
TIMEOUT_SECONDS = int(os.environ.get("RUN_TIMEOUT_SECONDS", "120"))
MAX_OUTPUT_BYTES = int(os.environ.get("MAX_OUTPUT_BYTES", str(200 * 1024)))
MAX_FILE_BYTES = int(os.environ.get("MAX_FILE_BYTES", str(2 * 1024 * 1024)))
MEMORY_BYTES = int(os.environ.get("RUN_MEMORY_BYTES", str(1024 * 1024 * 1024)))
RUN_PYTHON_ENABLED = os.environ.get("RUN_PYTHON_ENABLED", "false").lower() == "true"
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
slots = threading.BoundedSemaphore(int(os.environ.get("RUN_PARALLEL", "2")))

mcp = FastMCP(
    "skills-python",
    host="0.0.0.0",
    port=8000,
    streamable_http_path="/mcp",
    stateless_http=True,
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=["moqui-python-skills:*", "localhost:*", "127.0.0.1:*"],
        allowed_origins=[],
    ),
)


def _under(root: Path, relative: str) -> Path:
    """The path of a file named relative to root; anything that leaves root, or goes through a link, is refused."""
    if not relative or relative.startswith("/") or "\x00" in relative:
        raise ValueError("a relative path is required")
    candidate = (root / relative)
    if any(part == ".." for part in Path(relative).parts):
        raise ValueError("'..' is not allowed in a path")
    resolved = candidate.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError("the path leaves its directory")
    return resolved


def _skill_dir(skill: str) -> Path:
    if not NAME.match(skill or ""):
        raise ValueError("not a skill name")
    directory = (SKILLS_DIR / skill)
    if not (directory / "SKILL.md").is_file():
        raise ValueError(f"no skill named {skill}")
    return directory.resolve()


def _limits():
    resource.setrlimit(resource.RLIMIT_AS, (MEMORY_BYTES, MEMORY_BYTES))
    resource.setrlimit(resource.RLIMIT_CPU, (TIMEOUT_SECONDS + 5, TIMEOUT_SECONDS + 5))
    resource.setrlimit(resource.RLIMIT_NPROC, (64, 64))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_FILE_BYTES * 8, MAX_FILE_BYTES * 8))
    os.setsid()


def _cut(data: bytes) -> str:
    text = data[:MAX_OUTPUT_BYTES].decode("utf-8", "replace")
    return text + ("\n[output cut at %d bytes]" % MAX_OUTPUT_BYTES if len(data) > MAX_OUTPUT_BYTES else "")


def _run(argv, cwd: Path) -> dict:
    if not slots.acquire(timeout=30):
        return {"error": "too many scripts running; try again"}
    try:
        env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": str(cwd), "TMPDIR": str(cwd), "LANG": "C.UTF-8",
               "PYTHONDONTWRITEBYTECODE": "1", "SKILLS_DIR": str(SKILLS_DIR), "WORKSPACE_DIR": str(WORKSPACE)}
        try:
            done = subprocess.run(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                                  timeout=TIMEOUT_SECONDS, preexec_fn=_limits, shell=False)
            return {"exitCode": done.returncode, "stdout": _cut(done.stdout), "stderr": _cut(done.stderr)}
        except subprocess.TimeoutExpired as e:
            return {"exitCode": None, "timedOut": True, "stdout": _cut(e.stdout or b""), "stderr": _cut(e.stderr or b"")}
    finally:
        slots.release()


def _files_after(directory: Path) -> list:
    out = []
    for path in sorted(directory.rglob("*")):
        if path.is_file() and not path.is_symlink():
            out.append({"path": str(path.relative_to(WORKSPACE)), "bytes": path.stat().st_size})
        if len(out) >= 200:
            break
    return out


@mcp.tool()
def list_skill_scripts(skill: str = "") -> dict:
    """Lists the skills and the Python scripts each one has (scripts/*.py). Pass a skill name to see only that one."""
    names = [skill] if skill else sorted(p.name for p in SKILLS_DIR.iterdir() if (p / "SKILL.md").is_file())
    result = {}
    for name in names:
        directory = _skill_dir(name)
        scripts = sorted(str(p.relative_to(directory)) for p in (directory / "scripts").glob("*.py")) if (directory / "scripts").is_dir() else []
        result[name] = scripts
    return {"skills": result, "workspace": str(WORKSPACE)}


@mcp.tool()
def run_skill_script(skill: str, script: str, args: list[str] | None = None, workdir: str = "") -> dict:
    """Runs scripts/<script> of a skill with the Python interpreter and returns exit code, stdout and stderr.

    script is the file name inside the scripts directory of the skill (for example init_session.py). args are passed as
    separate arguments, no shell is involved. The script runs in the workspace directory (or the sub-directory workdir of
    it) and can write only there; paths given to it must be inside the workspace. No network is available. The files that
    exist in the workspace afterwards are listed in the answer."""
    directory = _skill_dir(skill)
    if not NAME.match(script or "") or not script.endswith(".py"):
        raise ValueError("script must be the name of a .py file in the scripts directory of the skill")
    path = _under(directory / "scripts", script)
    if not path.is_file():
        raise ValueError(f"{skill} has no script {script}; list_skill_scripts shows them")
    cwd = _under(WORKSPACE, workdir) if workdir else WORKSPACE
    cwd.mkdir(parents=True, exist_ok=True)
    cleaned = [str(a) for a in (args or [])]
    if len(cleaned) > 64 or any(len(a) > 4096 for a in cleaned):
        raise ValueError("too many or too long arguments")
    result = _run([sys.executable, "-E", "-s", str(path), *cleaned], cwd)
    result["files"] = _files_after(WORKSPACE)
    return result


@mcp.tool()
def write_file(path: str, content: str) -> dict:
    """Writes a text file in the workspace (the input of a script). path is relative to the workspace."""
    data = content.encode("utf-8")
    if len(data) > MAX_FILE_BYTES:
        raise ValueError("the file is too large")
    target = _under(WORKSPACE, path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return {"path": str(target.relative_to(WORKSPACE)), "bytes": len(data)}


@mcp.tool()
def read_file(path: str) -> dict:
    """Reads a text file of the workspace (the output of a script), up to the size limit."""
    target = _under(WORKSPACE, path)
    if not target.is_file():
        raise ValueError("no such file")
    data = target.read_bytes()
    return {"path": path, "bytes": len(data), "content": data[:MAX_FILE_BYTES].decode("utf-8", "replace"),
            "cut": len(data) > MAX_FILE_BYTES}


@mcp.tool()
def list_files(path: str = "") -> dict:
    """Lists the files of the workspace, or of one of its directories."""
    base = _under(WORKSPACE, path) if path else WORKSPACE
    if not base.is_dir():
        raise ValueError("no such directory")
    return {"files": _files_after(base)}


if RUN_PYTHON_ENABLED:
    @mcp.tool()
    def run_python(code: str) -> dict:
        """Runs a piece of Python code in the workspace, under the same limits as a script. Enabled by the deployment only."""
        if len(code) > MAX_FILE_BYTES:
            raise ValueError("the code is too long")
        with tempfile.NamedTemporaryFile("w", suffix=".py", dir=WORKSPACE, delete=False) as f:
            f.write(code)
            name = f.name
        try:
            return _run([sys.executable, "-E", "-s", name], WORKSPACE)
        finally:
            os.unlink(name)


if __name__ == "__main__":
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    mcp.run(transport="streamable-http")
