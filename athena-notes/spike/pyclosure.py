"""Athena packages reachable through module-level python imports (the ones that run as soon
as a module is imported, i.e. not inside functions), starting from some packages.

usage: pyclosure.py <athena source dir> <package path> [...]
Prints the packages (by path) that provide the imported python packages.
"""

import ast
import os
import sys

src = sys.argv[1]
# python package name -> athena package path, from atlas_install_python_modules layouts:
# <pkg path>/python/*.py is installed as python/<pkg name>/.
provider = {}
for root, dirs, files in os.walk(src):
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    if "CMakeLists.txt" in files and os.path.isdir(os.path.join(root, "python")):
        provider.setdefault(os.path.basename(root), os.path.relpath(root, src))


def toplevel_imports(path):
    try:
        tree = ast.parse(open(path, encoding="utf-8", errors="replace").read())
    except SyntaxError:
        return set()
    out = set()
    # module level, and inside module-level if/try blocks, but not in functions/classes
    stack = list(tree.body)
    while stack:
        node = stack.pop()
        if isinstance(node, ast.Import):
            out.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            out.add(node.module.split(".")[0])
        elif isinstance(node, (ast.If, ast.Try)):
            stack.extend(node.body)
            stack.extend(getattr(node, "orelse", []))
            stack.extend(getattr(node, "finalbody", []))
            for h in getattr(node, "handlers", []):
                stack.extend(h.body)
    return out


todo = list(sys.argv[2:])
seen = set()
while todo:
    pkg = todo.pop()
    if pkg in seen:
        continue
    seen.add(pkg)
    for sub in ("python", "share", "bin"):
        d = os.path.join(src, pkg, sub)
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for f in files:
                if f.endswith(".py"):
                    for mod in toplevel_imports(os.path.join(root, f)):
                        if mod in provider and provider[mod] not in seen:
                            todo.append(provider[mod])
for p in sorted(seen):
    print(p)
