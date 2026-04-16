#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
REGISTRY_FILES = {
    "agents": ROOT / "registry/agents.yaml",
    "bases": ROOT / "registry/bases.yaml",
}
REQUIRED_DIRECTORIES = [
    ROOT / "agents/_template",
    ROOT / "shared/scripts",
    ROOT / "scripts",
]
AGENT_REQUIRED_FILES = [
    "agent.yaml",
    "Dockerfile",
    "install.sh",
    "entrypoint.sh",
    "healthcheck.sh",
    "tests/smoke.sh",
    "README.md",
]
AGENT_EXECUTABLES = [
    "install.sh",
    "entrypoint.sh",
    "healthcheck.sh",
    "tests/smoke.sh",
]
BASE_REQUIRED_FILES = [
    "base.yaml",
    "Dockerfile",
    "README.md",
]
PLACEHOLDER_TOKENS = ("change-me", "replace-me")


class ParseError(RuntimeError):
    pass


def strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def parse_scalar(value: str) -> Any:
    value = strip_quotes(value)
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return value


def next_relevant_line(lines: list[str], start_index: int) -> tuple[int, str] | None:
    for index in range(start_index + 1, len(lines)):
        raw = lines[index]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        return indent, stripped
    return None


def parse_simple_yaml(text: str) -> Any:
    lines = text.splitlines()
    root: dict[str, Any] = {}
    stack: list[tuple[int, Any]] = [(-1, root)]

    for index, raw in enumerate(lines):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent % 2 != 0:
            raise ParseError(f"Unsupported indentation on line {index + 1}: {raw!r}")

        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()

        container = stack[-1][1]
        upcoming = next_relevant_line(lines, index)

        if stripped.startswith("- "):
            if not isinstance(container, list):
                raise ParseError(f"List item without list container on line {index + 1}: {raw!r}")
            item = stripped[2:].strip()
            if not item:
                raise ParseError(f"Empty list item on line {index + 1}: {raw!r}")

            if item.endswith(":"):
                key = item[:-1].strip()
                child: Any = {}
                if upcoming and upcoming[0] > indent and upcoming[1].startswith("- "):
                    child = []
                entry: dict[str, Any] = {key: child}
                container.append(entry)
                stack.append((indent, entry))
                stack.append((indent + 1, child))
                continue

            if ":" in item:
                key, value = item.split(":", 1)
                key = key.strip()
                value = value.strip()
                entry = {key: parse_scalar(value)}
                container.append(entry)
                stack.append((indent, entry))
                continue

            container.append(parse_scalar(item))
            continue

        if ":" not in stripped:
            raise ParseError(f"Unsupported YAML content on line {index + 1}: {raw!r}")

        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()

        if not isinstance(container, dict):
            raise ParseError(f"Mapping entry without mapping container on line {index + 1}: {raw!r}")

        if value == "":
            child = {}
            if upcoming and upcoming[0] > indent and upcoming[1].startswith("- "):
                child = []
            container[key] = child
            stack.append((indent, child))
            continue

        container[key] = parse_scalar(value)

    return root


def read_yaml(path: Path) -> Any:
    try:
        return parse_simple_yaml(path.read_text())
    except FileNotFoundError as exc:
        raise SystemExit(f"Missing file: {path.relative_to(ROOT)}") from exc
    except ParseError as exc:
        raise SystemExit(f"Failed to parse {path.relative_to(ROOT)}: {exc}") from exc


def ensure_dict(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SystemExit(f"Expected mapping for {context}")
    return value


def ensure_list(value: Any, context: str) -> list[Any]:
    if not isinstance(value, list):
        raise SystemExit(f"Expected list for {context}")
    return value


def load_registry(kind: str) -> list[dict[str, Any]]:
    path = REGISTRY_FILES[kind]
    data = ensure_dict(read_yaml(path), path.name)
    items = ensure_list(data.get(kind), f"{path.name}:{kind}")
    normalized: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            raise SystemExit(f"Each entry in {path.name}:{kind} must be a mapping")
        normalized.append(
            {
                "name": str(item.get("name", "")).strip(),
                "path": str(item.get("path", "")).strip(),
                "enabled": bool(item.get("enabled", True)),
            }
        )
    return normalized


def write_registry(kind: str, entries: list[dict[str, Any]]) -> None:
    path = REGISTRY_FILES[kind]
    lines = [f"{kind}:"]
    for entry in entries:
        lines.append(f"  - name: {entry['name']}")
        lines.append(f"    path: {entry['path']}")
        lines.append(f"    enabled: {'true' if entry['enabled'] else 'false'}")
    path.write_text("\n".join(lines) + "\n")


def set_registry_enabled(kind: str, name: str, enabled: bool) -> dict[str, Any]:
    entries = load_registry(kind)
    for entry in entries:
        if entry["name"] == name:
            entry["enabled"] = enabled
            write_registry(kind, entries)
            return entry
    raise SystemExit(f"Unknown {kind[:-1]} in registry/{kind}.yaml: {name}")


def load_agent_meta(agent_name: str) -> dict[str, Any]:
    registry_entry = next((item for item in load_registry("agents") if item["name"] == agent_name), None)
    if not registry_entry:
        raise SystemExit(f"Unknown agent in registry/agents.yaml: {agent_name}")

    meta_path = ROOT / registry_entry["path"] / "agent.yaml"
    data = ensure_dict(read_yaml(meta_path), str(meta_path.relative_to(ROOT)))
    image = ensure_dict(data.get("image", {}), f"{meta_path.name}:image")
    build = ensure_dict(data.get("build", {}), f"{meta_path.name}:build") if data.get("build") is not None else {}
    build_args = ensure_dict(build.get("args", {}), f"{meta_path.name}:build.args") if build.get("args") is not None else {}

    return {
        "registry": registry_entry,
        "meta_path": str(meta_path.relative_to(ROOT)),
        "name": str(data.get("name", "")).strip(),
        "base": str(data.get("base", "")).strip(),
        "image_repository": str(image.get("repository", "")).strip(),
        "image_tag": str(image.get("tag", "")).strip(),
        "build_args": {str(k): "" if v is None else str(v) for k, v in build_args.items()},
        "raw": data,
    }


def load_base_meta(base_name: str) -> dict[str, Any]:
    registry_entry = next((item for item in load_registry("bases") if item["name"] == base_name), None)
    if not registry_entry:
        raise SystemExit(f"Unknown base in registry/bases.yaml: {base_name}")

    meta_path = ROOT / registry_entry["path"] / "base.yaml"
    data = ensure_dict(read_yaml(meta_path), str(meta_path.relative_to(ROOT)))
    image = ensure_dict(data.get("image", {}), f"{meta_path.name}:image")
    return {
        "registry": registry_entry,
        "meta_path": str(meta_path.relative_to(ROOT)),
        "name": str(data.get("name", "")).strip(),
        "image_repository": str(image.get("repository", "")).strip(),
        "image_tag": str(image.get("tag", "")).strip(),
        "raw": data,
    }


def shell_lines_for_agent(agent_name: str) -> list[str]:
    meta = load_agent_meta(agent_name)
    lines = [
        f"META\tREGISTRY_PATH\t{meta['registry']['path']}",
        f"META\tENABLED\t{str(meta['registry']['enabled']).lower()}",
        f"META\tNAME\t{meta['name']}",
        f"META\tBASE_NAME\t{meta['base']}",
        f"META\tREPOSITORY\t{meta['image_repository']}",
        f"META\tDEFAULT_TAG\t{meta['image_tag']}",
    ]
    for key, value in meta["build_args"].items():
        lines.append(f"BUILD_ARG\t{key}\t{value}")
    return lines


def shell_lines_for_base(base_name: str) -> list[str]:
    meta = load_base_meta(base_name)
    return [
        f"META\tREGISTRY_PATH\t{meta['registry']['path']}",
        f"META\tENABLED\t{str(meta['registry']['enabled']).lower()}",
        f"META\tNAME\t{meta['name']}",
        f"META\tREPOSITORY\t{meta['image_repository']}",
        f"META\tDEFAULT_TAG\t{meta['image_tag']}",
    ]


def matrix_for(kind: str, enabled_only: bool) -> dict[str, list[dict[str, Any]]]:
    entries = load_registry(kind)
    if enabled_only:
        entries = [entry for entry in entries if entry["enabled"]]

    if kind == "agents":
        include = []
        for entry in entries:
            meta = load_agent_meta(entry["name"])
            include.append(
                {
                    "name": entry["name"],
                    "path": entry["path"],
                    "enabled": entry["enabled"],
                    "base": meta["base"],
                    "image": f"{meta['image_repository']}:{meta['image_tag']}",
                }
            )
        return {"include": include}

    include = []
    for entry in entries:
        meta = load_base_meta(entry["name"])
        include.append(
            {
                "name": entry["name"],
                "path": entry["path"],
                "enabled": entry["enabled"],
                "image": f"{meta['image_repository']}:{meta['image_tag']}",
            }
        )
    return {"include": include}


def find_placeholders(path: Path) -> list[str]:
    hits: list[str] = []
    for relative in AGENT_REQUIRED_FILES:
        file_path = path / relative
        if not file_path.exists() or not file_path.is_file():
            continue
        try:
            text = file_path.read_text()
        except UnicodeDecodeError:
            continue
        for token in PLACEHOLDER_TOKENS:
            if token in text:
                hits.append(f"{file_path.relative_to(ROOT)} contains placeholder token '{token}'")
    return hits


def is_executable(path: Path) -> bool:
    mode = path.stat().st_mode
    return bool(mode & stat.S_IXUSR)


def validate_repo() -> list[str]:
    errors: list[str] = []

    for registry_file in REGISTRY_FILES.values():
        if not registry_file.exists():
            errors.append(f"Missing registry file: {registry_file.relative_to(ROOT)}")

    for directory in REQUIRED_DIRECTORIES:
        if not directory.exists():
            errors.append(f"Missing required directory: {directory.relative_to(ROOT)}")

    if errors:
        return errors

    agent_entries = load_registry("agents")
    base_entries = load_registry("bases")

    def validate_registry_entries(kind: str, entries: list[dict[str, Any]], expected_prefix: str) -> None:
        seen_names: set[str] = set()
        seen_paths: set[str] = set()
        for entry in entries:
            name = entry["name"]
            path = entry["path"]
            if not name:
                errors.append(f"registry/{kind}.yaml has an entry with empty name")
            if not path:
                errors.append(f"registry/{kind}.yaml entry '{name or '<unknown>'}' has empty path")
            if name in seen_names:
                errors.append(f"registry/{kind}.yaml has duplicate name: {name}")
            if path in seen_paths:
                errors.append(f"registry/{kind}.yaml has duplicate path: {path}")
            seen_names.add(name)
            seen_paths.add(path)
            expected_path = f"{expected_prefix}/{name}"
            if name and path and path != expected_path:
                errors.append(
                    f"registry/{kind}.yaml entry '{name}' should use conventional path '{expected_path}', found '{path}'"
                )

    validate_registry_entries("agents", agent_entries, "agents")
    validate_registry_entries("bases", base_entries, "base")

    for entry in base_entries:
        base_dir = ROOT / entry["path"]
        if not base_dir.exists():
            errors.append(f"Missing base path: {entry['path']}")
            continue
        for relative in BASE_REQUIRED_FILES:
            file_path = base_dir / relative
            if not file_path.exists():
                errors.append(f"Base '{entry['name']}' is missing required file: {file_path.relative_to(ROOT)}")
        meta_path = base_dir / "base.yaml"
        if meta_path.exists():
            meta = ensure_dict(read_yaml(meta_path), str(meta_path.relative_to(ROOT)))
            if str(meta.get("name", "")).strip() != entry["name"]:
                errors.append(
                    f"Base metadata name mismatch for {entry['name']}: base.yaml says '{meta.get('name', '')}'"
                )
            image = meta.get("image")
            if not isinstance(image, dict) or not image.get("repository") or not image.get("tag"):
                errors.append(f"Base '{entry['name']}' must define image.repository and image.tag in {meta_path.relative_to(ROOT)}")

    base_names = {entry["name"] for entry in base_entries}

    for entry in agent_entries:
        agent_dir = ROOT / entry["path"]
        if not agent_dir.exists():
            errors.append(f"Missing agent path: {entry['path']}")
            continue

        for relative in AGENT_REQUIRED_FILES:
            file_path = agent_dir / relative
            if not file_path.exists():
                errors.append(f"Agent '{entry['name']}' is missing required file: {file_path.relative_to(ROOT)}")

        for relative in AGENT_EXECUTABLES:
            file_path = agent_dir / relative
            if file_path.exists() and not is_executable(file_path):
                errors.append(f"Agent '{entry['name']}' file must be executable: {file_path.relative_to(ROOT)}")

        meta_path = agent_dir / "agent.yaml"
        if meta_path.exists():
            meta = ensure_dict(read_yaml(meta_path), str(meta_path.relative_to(ROOT)))
            if str(meta.get("name", "")).strip() != entry["name"]:
                errors.append(
                    f"Agent metadata name mismatch for {entry['name']}: agent.yaml says '{meta.get('name', '')}'"
                )
            base_name = str(meta.get("base", "")).strip()
            if not base_name:
                errors.append(f"Agent '{entry['name']}' must define base in {meta_path.relative_to(ROOT)}")
            elif base_name not in base_names:
                errors.append(f"Agent '{entry['name']}' references unknown base '{base_name}'")
            image = meta.get("image")
            if not isinstance(image, dict) or not image.get("repository") or not image.get("tag"):
                errors.append(f"Agent '{entry['name']}' must define image.repository and image.tag in {meta_path.relative_to(ROOT)}")
            build = meta.get("build")
            if build is not None and not isinstance(build, dict):
                errors.append(f"Agent '{entry['name']}' has invalid build section in {meta_path.relative_to(ROOT)}")
            elif isinstance(build, dict):
                build_args = build.get("args")
                if build_args is not None and not isinstance(build_args, dict):
                    errors.append(f"Agent '{entry['name']}' build.args must be a mapping in {meta_path.relative_to(ROOT)}")

        if entry["name"] != "_template":
            errors.extend(find_placeholders(agent_dir))

    return errors


def print_shell(lines: list[str]) -> None:
    sys.stdout.write("\n".join(lines))
    if lines:
        sys.stdout.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Repository metadata helper for Agent Hub Template")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List registry entries")
    list_parser.add_argument("kind", choices=("agents", "bases"))
    list_parser.add_argument("--enabled-only", action="store_true")
    list_parser.add_argument("--format", choices=("json", "names"), default="json")

    show_agent = subparsers.add_parser("show-agent", help="Show merged agent metadata")
    show_agent.add_argument("name")
    show_agent.add_argument("--format", choices=("json", "shell"), default="json")

    show_base = subparsers.add_parser("show-base", help="Show merged base metadata")
    show_base.add_argument("name")
    show_base.add_argument("--format", choices=("json", "shell"), default="json")

    matrix = subparsers.add_parser("matrix", help="Generate build matrix JSON")
    matrix.add_argument("kind", choices=("agents", "bases"))
    matrix.add_argument("--enabled-only", action="store_true")

    set_enabled = subparsers.add_parser("set-enabled", help="Enable or disable a registry entry")
    set_enabled.add_argument("kind", choices=("agents", "bases"))
    set_enabled.add_argument("name")
    set_enabled.add_argument("state", choices=("true", "false", "enabled", "disabled"))

    subparsers.add_parser("validate", help="Validate repo structure and metadata")

    args = parser.parse_args()

    if args.command == "list":
        entries = load_registry(args.kind)
        if args.enabled_only:
            entries = [entry for entry in entries if entry["enabled"]]
        if args.format == "names":
            sys.stdout.write("\n".join(entry["name"] for entry in entries))
            if entries:
                sys.stdout.write("\n")
            return
        print(json.dumps(entries))
        return

    if args.command == "show-agent":
        meta = load_agent_meta(args.name)
        if args.format == "shell":
            print_shell(shell_lines_for_agent(args.name))
            return
        print(json.dumps(meta))
        return

    if args.command == "show-base":
        meta = load_base_meta(args.name)
        if args.format == "shell":
            print_shell(shell_lines_for_base(args.name))
            return
        print(json.dumps(meta))
        return

    if args.command == "matrix":
        print(json.dumps(matrix_for(args.kind, args.enabled_only)))
        return

    if args.command == "set-enabled":
        enabled = args.state in {"true", "enabled"}
        entry = set_registry_enabled(args.kind, args.name, enabled)
        print(json.dumps(entry))
        return

    if args.command == "validate":
        errors = validate_repo()
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            raise SystemExit(1)
        print("Registry, metadata, and required files look valid.")
        return


if __name__ == "__main__":
    main()
