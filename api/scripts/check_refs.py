"""Local sanity checks for the OpenAPI contracts (complements Spectral in CI).

Checks: YAML parses; every $ref resolves (local and cross-file); operationIds are unique
across all files; path template parameters are declared; every schema is a valid
JSON Schema 2020-12 document.
Usage: python3 api/scripts/check_refs.py
"""
import re
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

API_DIR = Path(__file__).resolve().parent.parent
docs = {p.name: yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted(API_DIR.glob("*.yaml"))}
errors: list[str] = []


def resolve(file: str, pointer: str):
    node = docs[file]
    for part in pointer.lstrip("/").split("/"):
        part = part.replace("~1", "/").replace("~0", "~")
        node = node[part]
    return node


def walk(node, file: str, path: str):
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str):
            target_file, _, pointer = ref.partition("#")
            target_file = target_file or file
            try:
                resolve(target_file, pointer)
            except (KeyError, TypeError):
                errors.append(f"{file}:{path}: unresolved $ref {ref}")
        for key, value in node.items():
            walk(value, file, f"{path}/{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            walk(value, file, f"{path}/{i}")


def param_name(param: dict, file: str):
    if "$ref" in param:
        target_file, _, pointer = param["$ref"].partition("#")
        param = resolve(target_file or file, pointer)
    return param.get("name")


operation_ids: dict[str, str] = {}
for name, doc in docs.items():
    walk(doc, name, "")
    for route, item in (doc.get("paths") or {}).items():
        declared = {param_name(p, name) for p in item.get("parameters", [])}
        for method, op in item.items():
            if method == "parameters":
                continue
            names = set(declared)
            names.update(param_name(p, name) for p in op.get("parameters", []))
            for param in re.findall(r"{(\w+)}", route):
                if param not in names:
                    errors.append(f"{name}: {method.upper()} {route}: path parameter '{param}' not declared")
            op_id = op.get("operationId")
            if not op_id:
                errors.append(f"{name}: {method.upper()} {route}: missing operationId")
            elif op_id in operation_ids:
                errors.append(f"{name}: duplicate operationId {op_id} (also in {operation_ids[op_id]})")
            else:
                operation_ids[op_id] = name
            for code, response in op.get("responses", {}).items():
                if "$ref" not in response and "description" not in response:
                    errors.append(f"{name}: {method.upper()} {route} {code}: response without description")
    for schema_name, schema in (doc.get("components", {}).get("schemas") or {}).items():
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as exc:  # noqa: BLE001 - report any schema error
            errors.append(f"{name}: schema {schema_name}: {exc}")

print(f"Checked {len(docs)} files, {len(operation_ids)} operations")
for error in errors:
    print("ERROR", error)
sys.exit(1 if errors else 0)
