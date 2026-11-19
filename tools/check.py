#!/usr/bin/env python3
"""仓库门禁：静态检查 + 可选 Godot 冒烟。

用法：
    python tools/check.py            # 静态检查（不启动 Godot）
    python tools/check.py --godot    # 静态检查 + 冒烟测试 + 场景冒烟
    python tools/check.py --godot --godot-bin "D:\\Godot\\xxx_console.exe"

退出码：0 全过；1 有失败项。规则来源见 docs/代码规约.md §10。
"""

from __future__ import annotations

import argparse
import json
import os
import py_compile
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
DATA = GAME / "data"
# 最后才回落到开发机路径；优先 GODOT_BIN 与 PATH，避免别人 clone 后门禁直接失败
DEFAULT_GODOT = Path(r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe")

MAX_GD_LINE = 100
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".md", ".py", ".cfg", ".godot"}
SKIP_DIRS = {".git", ".godot", "_backup", "__pycache__", "build"}


class Checker:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.passed = 0

    def ok(self, name: str) -> None:
        self.passed += 1
        print(f"  [ok]   {name}")

    def fail(self, name: str, detail: str) -> None:
        self.failures.append(f"{name}: {detail}")
        print(f"  [FAIL] {name}: {detail}")

    def warn(self, name: str, detail: str) -> None:
        self.warnings.append(f"{name}: {detail}")
        print(f"  [warn] {name}: {detail}")


def iter_files(root: Path, suffixes: set[str]):
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in suffixes:
            yield path


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def check_python(c: Checker) -> None:
    print("Python 语法")
    files = list((ROOT / "tools").rglob("*.py"))
    bad = 0
    for path in files:
        try:
            py_compile.compile(str(path), doraise=True)
            c.ok(rel(path))
        except py_compile.PyCompileError as exc:
            bad += 1
            c.fail(rel(path), str(exc).splitlines()[0])
    if not files:
        c.warn("tools", "没有找到 .py 文件")
    print(f"  共 {len(files)} 个文件，失败 {bad} 个\n")


def check_json(c: Checker) -> None:
    print("JSON 规范（DATA-1/2/3）")
    for path in sorted(DATA.glob("*.json")):
        text = path.read_text(encoding="utf-8")
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            c.fail(rel(path), f"解析失败 line {exc.lineno}")
            continue
        canonical = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if "\t" in text:
            c.fail(rel(path), "包含 Tab，应为 2 空格")
        elif text != canonical:
            c.fail(rel(path), "不是规范化的 2 空格 JSON（用 json.dumps 重写）")
        else:
            c.ok(rel(path))


def check_text_hygiene(c: Checker) -> None:
    print("文本卫生（GEN-1/2、SC-1、ENC-1）")
    bad = 0
    for path in iter_files(ROOT, TEXT_SUFFIXES):
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            bad += 1
            c.fail(rel(path), "含 UTF-8 BOM")
            continue
        if b"\r\n" in raw:
            bad += 1
            c.fail(rel(path), "含 CRLF，应为 LF")
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            bad += 1
            c.fail(rel(path), "不是 UTF-8")
            continue
        if not text.endswith("\n"):
            bad += 1
            c.fail(rel(path), "文件末尾缺少换行")
            continue
        if text.endswith("\n\n"):
            bad += 1
            c.fail(rel(path), "文件末尾有多余空行")
            continue
        trailing = [
            i + 1 for i, line in enumerate(text.splitlines()) if line != line.rstrip()
        ]
        if trailing:
            bad += 1
            c.fail(rel(path), f"行尾空白：{trailing[:5]}")
    if bad == 0:
        c.ok("全部文本文件：UTF-8 / LF / 末尾单换行 / 无行尾空白")
    print()


def check_gdscript(c: Checker) -> None:
    print("GDScript 静态检查（GD-1/2、GEN-3）")
    bad = 0
    for path in sorted(GAME.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            if len(line) > MAX_GD_LINE:
                bad += 1
                c.fail(f"{rel(path)}:{lineno}", f"行长 {len(line)} > {MAX_GD_LINE}")
            if line.startswith(" "):
                bad += 1
                c.fail(f"{rel(path)}:{lineno}", "用空格缩进，应使用 Tab")
        if re.search(r"(^|[^&])&&|\|\|(?!\w)", text):
            bad += 1
            c.fail(rel(path), "使用 && 或 ||，应使用 and / or")
    if bad == 0:
        c.ok(f"{len(list(GAME.rglob('*.gd')))} 个脚本：Tab 缩进 / 行宽 <= {MAX_GD_LINE} / 无 && ||")
    print()


def run_godot(binary: Path, args: list[str], env: dict[str, str], timeout: int) -> tuple[int, str]:
    result = subprocess.run(
        [str(binary), *args],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    return result.returncode, (result.stdout or "") + (result.stderr or "")


def check_godot(c: Checker, binary: Path) -> None:
    print(f"Godot 冒烟（{binary}）")
    env = os.environ.copy()
    env["SALVATION_SAVE_DIR"] = str(ROOT / "_backup" / "test-save")

    code, out = run_godot(
        binary,
        ["--headless", "--path", "game", "res://tests/smoke_test.tscn"],
        env,
        240,
    )
    tail = "\n".join(out.strip().splitlines()[-6:])
    if code == 0 and "0 失败" in out:
        c.ok("冒烟测试通过（基线 106 条）")
    else:
        c.fail("冒烟测试", f"退出码 {code}\n{tail}")

    for scene, frames in (("res://scenes/levels/level.tscn", 300), ("res://scenes/ui/title.tscn", 120)):
        code, out = run_godot(
            binary,
            ["--headless", "--path", "game", scene, "--quit-after", str(frames)],
            env,
            240,
        )
        errors = [line for line in out.splitlines() if "SCRIPT ERROR" in line]
        if code == 0 and not errors:
            c.ok(f"{scene} 跑 {frames} 帧无脚本错误")
        else:
            c.fail(scene, f"退出码 {code}，脚本错误 {len(errors)} 条")
    print()


def resolve_godot(explicit: Path | None) -> Path:
    """按 参数 → GODOT_BIN → PATH → 开发机默认路径 的顺序找 Godot。"""
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(explicit)
    env = os.environ.get("GODOT_BIN", "").strip()
    if env:
        candidates.append(Path(env))
    for name in ("godot", "godot4", "godot.exe", "godot4.exe"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
            break
    candidates.append(DEFAULT_GODOT)
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return explicit or Path(env or DEFAULT_GODOT)


def main() -> int:
    if sys.platform == "win32":
        # 控制台默认 GBK，中文输出在 Windows Terminal / 管道里统一成 UTF-8
        for stream in (sys.stdout, sys.stderr):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except (AttributeError, OSError):
                pass

    parser = argparse.ArgumentParser(description="仓库门禁检查")
    parser.add_argument("--godot", action="store_true", help="同时运行 Godot 冒烟测试")
    parser.add_argument("--godot-bin", type=Path, default=None, help="Godot 可执行文件路径")
    parser.add_argument("--fast", action="store_true", help="只跑静态检查（等价于不加 --godot）")
    args = parser.parse_args()

    print(f"仓库：{ROOT}\n")
    c = Checker()
    check_python(c)
    check_json(c)
    check_text_hygiene(c)
    check_gdscript(c)

    if args.godot and not args.fast:
        binary = resolve_godot(args.godot_bin)
        if not binary.exists():
            c.fail("Godot", f"找不到 {binary}；用 --godot-bin 或环境变量 GODOT_BIN 指定")
        else:
            check_godot(c, binary)

    print("=" * 60)
    print(f"通过 {c.passed} 项，失败 {len(c.failures)} 项，警告 {len(c.warnings)} 项")
    for item in c.failures:
        print(f"  FAIL  {item}")
    for item in c.warnings:
        print(f"  warn  {item}")
    return 0 if not c.failures else 1


if __name__ == "__main__":
    sys.exit(main())
