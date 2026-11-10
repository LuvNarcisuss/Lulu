#!/usr/bin/env python3
"""Parse Swift source syntax without compiling, typechecking or running an app."""
import json
import pathlib
import sys
import tree_sitter
import tree_sitter_swift

root = pathlib.Path(__file__).resolve().parents[1]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
files = sorted((root / "LuluApp/Sources").rglob("*.swift"))
for path in files:
    data = path.read_bytes()
    tree = parser.parse(data)
    if not tree.root_node.has_error:
        continue
    nodes = [tree.root_node]
    while nodes:
        node = nodes.pop()
        if node.type == "ERROR" or node.is_missing:
            failures.append({"file": str(path.relative_to(root)), "line": node.start_point.row + 1, "column": node.start_point.column + 1, "kind": node.type, "text": data[node.start_byte:node.end_byte].decode("utf-8")[:180]})
        else:
            nodes.extend(reversed(node.children))
result = {"kind": "Static grammar parse only", "swift_files": len(files), "errors": failures, "not_performed": "Swift compilation, typechecking, linking, launch, simulator, runtime tests and device acceptance"}
print(json.dumps(result, indent=2))
(root / "docs/swift-syntax-audit.json").write_text(json.dumps(result, indent=2) + "\n")
sys.exit(bool(failures))
