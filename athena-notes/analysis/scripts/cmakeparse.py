"""A small evaluator for the subset of CMake that Athena's package CMakeLists.txt use.

It is not CMake. It understands what the 1966 package files actually do: `if/elseif/else`
over the project flags (XAOD_STANDALONE, XAOD_ANALYSIS, SIMULATIONBASE, GENERATIONBASE, ...),
`set`/`list(APPEND)`/`file(GLOB)`/`foreach`, `return()`, `find_package`, and the `atlas_add_*`
target functions. Package-local `function`/`macro` definitions are recorded but not executed
(they are test wrappers except in 2 packages, which define `_add_exec` for a few executables).

Used by depgraph.py; `evaluate(pkg, text, files, config)` returns one package's targets.
"""

import fnmatch
import re

TU_EXT = (".cxx", ".cpp", ".cc", ".c", ".C", ".cu", ".f", ".F", ".f90", ".F90", ".hip")

# Keywords of the atlas_add_* functions (union). Anything else upper-case is an argument.
KEYWORDS = {
    "PUBLIC_HEADERS",
    "NO_PUBLIC_HEADERS",
    "INTERFACE",
    "SHARED",
    "STATIC",
    "MODULE",
    "OBJECT",
    "INCLUDE_DIRS",
    "PRIVATE_INCLUDE_DIRS",
    "LINK_LIBRARIES",
    "PRIVATE_LINK_LIBRARIES",
    "DEFINITIONS",
    "PRIVATE_DEFINITIONS",
    "SOURCES",
    "ENVIRONMENT",
    "LOG_IGNORE_PATTERN",
    "LOG_SELECT_PATTERN",
    "SCRIPT",
    "PRE_EXEC_SCRIPT",
    "POST_EXEC_SCRIPT",
    "PROPERTIES",
    "EXTRA_FILES",
    "NAVIGABLES",
    "DATA_LINKS",
    "ELEMENT_LINKS",
    "ELEMENT_LINK_VECTORS",
    "OPTIONS",
    "TYPES_WITH_NAMESPACE",
    "MULT_CHAN_TYPES",
    "FILES",
    "CNV_PFX",
    "DEPENDS",
    "NO_ROOTMAP_MERGE",
    "EXTERNAL_PACKAGES",
    "ROOT_HEADERS",
    "DICTIONARY_NAME",
    "INPUT",
    "OUTPUT_NAME",
    "INCLUDE",
    "EXCLUDE",
    "PRIVATE_WORKING_DIRECTORY",
    "IGNORE_PATTERN",
    "NOEXEC",
    "POST_BUILD_CMD",
    "EXECUTABLE",
    "SELECTION",
    "REFERENCE",
    "WARNINGS_AS_ERRORS",
    "ALT_INCLUDE_DIRS",
    "INSTALL_FOR_HOST",
    "ARG",
    "SKELETON_PREFIX",
    "PROPERTY",
    "DESTINATION",
    "CONVERTER_PREFIX",
    "LINK",
    "COMMENT",
    "TYPES",
    "MT",
    "PRIVATE",
    "CONTAINERS",
    "OBJECTS",
    "TIMEOUT",
    "DEPENDS_ON",
    "SIMULATIONS",
    "TARGET_NAME",
    "OUTPUT",
    "MACRO_NAME",
    "HEADERS",
    "INCLUDE_PATHS",
}

TARGET_CMDS = {
    "atlas_add_library": "library",
    "atlas_add_component": "component",
    "atlas_add_dictionary": "dictionary",
    "atlas_add_executable": "executable",
    "atlas_add_test": "test",
    "atlas_add_tpcnv_library": "tpcnv",
    "atlas_add_poolcnv_library": "poolcnv",
    "atlas_add_sercnv_library": "sercnv",
    "add_library": "cmake_library",
    "atlas_add_root_dictionary": "root_dictionary",
    "atlas_add_xaod_smart_pointer_dicts": "xaod_smart_pointer_dicts",
    "atlas_generate_reflex_dictionary": "reflex_dictionary",
}

# Default configuration: the Athena project as conda-forge would build it (no CUDA/HIP/SYCL).
ATHENA_CONFIG = {
    "vars": {
        "XAOD_STANDALONE": "",
        "XAOD_ANALYSIS": "",
        "SIMULATIONBASE": "",
        "GENERATIONBASE": "",
        "BUILDVP1LIGHT": "",
        "COLUMNAR_ANALYSIS": "",
        "TRIGCONF_STANDALONE": "",
        "APPLE": "",
        "UNIX": "1",
        "CMAKE_CXX_CPPCHECK": "",
        "CMAKE_BUILD_TYPE": "Release",
        "CMAKE_CXX_COMPILER_ID": "GNU",
        "CMAKE_CXX_COMPILER_VERSION": "15.2.0",
        "CMAKE_COMPILER_IS_GNUCXX": "1",
        "CMAKE_CUDA_COMPILER": "",
        "CMAKE_HIP_COMPILER": "",
        "CMAKE_SYCL_COMPILER": "",
        "CMAKE_PROJECT_NAME": "Athena",
        "ATLAS_PROJECT": "Athena",
        "CMAKE_SYSTEM_PROCESSOR": "x86_64",
        "ATLAS_RELEASE_MODE": "",
        "ATLAS_BASE_PROJECT_NAMES": "",
        "ATLAS_BUILD_SIM_CUDA": "",
        "USE_GPU": "",
        "ATLAS_GEANT4_USE_LTO": "1",
        "CMAKE_INTERPROCEDURAL_OPTIMIZATION": "",
        "SHERPA_LCGVERSION": "3.0",
        "CLHEP_VERSION": "2.4.7",
        "CMAKE_DL_LIBS": "dl",
        "ATLAS_ENABLE_CI_TESTS": "",
        "ATLAS_RELEASE_RECOMPILE_DRYRUN": "",
        "ATLAS_PACKAGE_RECOMPILE": "",
        "COLUMNAR_DEFAULT_ACCESS_MODE": "0",
    },
    # *_FOUND defaults to true (the release has every external) except these:
    "not_found": {"ADEPT_FOUND", "CELERITAS_FOUND", "PEPPER_FOUND", "VALGRIND_FOUND"},
    # `if( TARGET x )` for targets that are not Athena's own: which exist.
    "ext_targets": {"Acts::PluginGnn": False, "Acts::PluginDetray": False},
    "exists": False,  # EXISTS / IS_DIRECTORY on host paths
}


def tokenize(text):
    """Yield (command, [args]) from CMake source. args are (value, quoted)."""
    i, n = 0, len(text)
    out = []
    while i < n:
        c = text[i]
        if c == "#":
            if text.startswith("#[[", i) or text.startswith("#[=[", i):
                j = text.find("]]", i)
                i = n if j < 0 else j + 2
            else:
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
            continue
        if c.isspace():
            i += 1
            continue
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, i)
        if not m:
            i += 1
            continue
        name = m.group(0)
        j = m.end()
        while j < n and text[j] in " \t":
            j += 1
        if j >= n or text[j] != "(":
            i = j
            continue
        # parse args
        j += 1
        depth = 1
        args = []
        cur = ""
        while j < n and depth:
            ch = text[j]
            if ch == "#" and not cur:
                k = text.find("\n", j)
                j = n if k < 0 else k + 1
                continue
            if ch == "\\" and j + 1 < n:
                cur += text[j : j + 2]
                j += 2
                continue
            if ch == '"' and not cur:
                k = j + 1
                buf = ""
                while k < n and text[k] != '"':
                    if text[k] == "\\" and k + 1 < n:
                        buf += text[k : k + 2]
                        k += 2
                        continue
                    buf += text[k]
                    k += 1
                args.append((cur + buf, True))
                cur = ""
                j = k + 1
                continue
            if text.startswith("[[", j) or text.startswith("[=[", j):
                end = "]]" if text.startswith("[[", j) else "]=]"
                k = text.find(end, j)
                args.append((text[j + len(end) : k], True))
                j = k + len(end)
                continue
            if ch == "(":
                if cur:
                    args.append((cur, False))
                    cur = ""
                depth += 1
                args.append(("(", False))
                j += 1
                continue
            if ch == ")":
                if cur:
                    args.append((cur, False))
                    cur = ""
                depth -= 1
                if depth:
                    args.append((")", False))
                j += 1
                continue
            if ch.isspace():
                if cur:
                    args.append((cur, False))
                    cur = ""
                j += 1
                continue
            cur += ch
            j += 1
        out.append((name.lower(), args))
        i = j
    return out


VARREF = re.compile(r"\$\{([A-Za-z0-9_\-:.]+)\}")
ENVREF = re.compile(r"\$ENV\{[^}]*\}")


class Ctx:
    def __init__(self, pkg, files, config, all_targets):
        self.pkg = pkg
        self.files = files  # files relative to the package dir
        self.cfg = config
        self.vars = dict(config["vars"])
        self.vars["CMAKE_CURRENT_SOURCE_DIR"] = "@PKG@"
        self.vars["CMAKE_CURRENT_LIST_DIR"] = "@PKG@"
        self.vars["CMAKE_CURRENT_BINARY_DIR"] = "@BIN@"
        self.all_targets = all_targets
        self.targets = []
        self.find_packages = {}
        self.unexpanded = set()
        self.functions = []
        self.wrapper_calls = []
        self.returned = False

    def expand_str(self, s):
        for _ in range(5):

            def rep(m):
                v = m.group(1)
                if v in self.vars:
                    return self.vars[v]
                return "@EXT:" + v + "@"

            s2 = VARREF.sub(rep, s)
            s2 = ENVREF.sub("", s2)
            if s2 == s:
                break
            s = s2
        return s

    def expand(self, args):
        out = []
        for v, q in args:
            e = self.expand_str(v)
            if q:
                out.append(e)
            else:
                out.extend(x for x in e.split(";") if x != "")
        return out

    # ---- conditions
    def truthy(self, w):
        if w.upper() in ("1", "ON", "YES", "TRUE", "Y"):
            return True
        if w.upper() in ("0", "OFF", "NO", "FALSE", "N", "IGNORE", "NOTFOUND", ""):
            return False
        if w.endswith("-NOTFOUND"):
            return False
        if w in self.vars:
            return self.truthy_val(self.vars[w])
        if w.upper().endswith("_FOUND"):
            return w.upper() not in self.cfg["not_found"]
        if w.startswith("@EXT:"):
            return (
                w.upper()[5:-1].endswith("_FOUND")
                and w.upper()[5:-1] not in self.cfg["not_found"]
            )
        return False

    def truthy_val(self, v):
        if v.upper() in ("", "0", "OFF", "NO", "FALSE", "N", "IGNORE", "NOTFOUND"):
            return False
        return True

    def cond(self, raw):
        toks = [(self.expand_str(v) if q else v, q) for v, q in raw]
        pos = [0]

        def peek():
            return toks[pos[0]][0] if pos[0] < len(toks) else None

        def take():
            t = toks[pos[0]]
            pos[0] += 1
            return t

        def value(tok):
            v, q = tok
            if q:
                return self.expand_str(v)
            if v in self.vars:
                return self.vars[v]
            return self.expand_str(v)

        def primary():
            t = peek()
            if t == "(":
                take()
                r = or_expr()
                if peek() == ")":
                    take()
                return r
            if t in ("TARGET", "DEFINED", "EXISTS", "IS_DIRECTORY", "COMMAND"):
                take()
                arg = take()[0]
                arg = self.expand_str(arg)
                if t == "TARGET":
                    if arg in self.cfg["ext_targets"]:
                        return self.cfg["ext_targets"][arg]
                    if "::" in arg:
                        return not any(k in arg for k in ("cuda", "hip", "sycl"))
                    return arg in self.all_targets
                if t == "DEFINED":
                    return arg in self.vars
                if t == "COMMAND":
                    return True
                return self.cfg["exists"] or arg.startswith("@PKG@")
            lhs = take()
            op = peek()
            binops = (
                "STREQUAL",
                "MATCHES",
                "EQUAL",
                "LESS",
                "GREATER",
                "VERSION_LESS",
                "VERSION_GREATER",
                "VERSION_EQUAL",
                "VERSION_GREATER_EQUAL",
                "VERSION_LESS_EQUAL",
                "IN_LIST",
                "STRLESS",
                "STRGREATER",
                "LESS_EQUAL",
                "GREATER_EQUAL",
            )
            if op in binops:
                take()
                rhs = take()
                a = value(lhs)
                b = value(rhs)
                if op == "STREQUAL":
                    return a == b
                if op == "MATCHES":
                    try:
                        return re.search(b, a) is not None
                    except re.error:
                        return False
                if op == "IN_LIST":
                    return a in self.vars.get(rhs[0], "").split(";")
                if op.startswith("VERSION"):

                    def vt(x):
                        return tuple(int(p) if p.isdigit() else 0 for p in x.split("."))

                    va, vb = vt(a), vt(b)
                    return {
                        "VERSION_LESS": va < vb,
                        "VERSION_GREATER": va > vb,
                        "VERSION_EQUAL": va == vb,
                        "VERSION_GREATER_EQUAL": va >= vb,
                        "VERSION_LESS_EQUAL": va <= vb,
                    }[op]
                try:
                    fa, fb = float(a), float(b)
                except ValueError:
                    return False
                return {
                    "EQUAL": fa == fb,
                    "LESS": fa < fb,
                    "GREATER": fa > fb,
                    "LESS_EQUAL": fa <= fb,
                    "GREATER_EQUAL": fa >= fb,
                }.get(op, False)
            v, q = lhs
            if q:
                return self.truthy_val(self.expand_str(v))
            return self.truthy(self.expand_str(v) if "${" in v else v)

        def not_expr():
            if peek() == "NOT":
                take()
                return not not_expr()
            return primary()

        def and_expr():
            r = not_expr()
            while peek() == "AND":
                take()
                r2 = not_expr()
                r = r and r2
            return r

        def or_expr():
            r = and_expr()
            while peek() == "OR":
                take()
                r2 = and_expr()
                r = r or r2
            return r

        try:
            return or_expr()
        except IndexError:
            return False

    # ---- files
    def glob(self, pattern):
        """Expand a (possibly globbing) path relative to the package dir."""
        p = pattern.replace("@PKG@/", "").replace("@PKG@", "")
        if p.startswith("@BIN@") or p.startswith("@EXT:") or p.startswith("/"):
            return []
        p = re.sub(r"/+", "/", p)
        if not any(c in p for c in "*?["):
            return [p] if p in self.files else []
        rx = re.compile(fnmatch.translate(p).replace(".*", "[^/]*"))
        return [f for f in self.files if rx.match(f)]


def split_kw(args):
    """Split an atlas_add_* argument list into {keyword: [values]}, '' for positional."""
    out = {"": []}
    cur = ""
    for a in args:
        if a in KEYWORDS:
            cur = a
            out.setdefault(cur, [])
        else:
            out.setdefault(cur, []).append(a)
    return out


def evaluate(pkg, text, files, config, all_targets):
    ctx = Ctx(pkg, files, config, all_targets)
    cmds = tokenize(text)
    run(ctx, cmds, 0, len(cmds))
    return ctx


def find_block_end(cmds, i, open_names, close_name):
    depth = 0
    for j in range(i, len(cmds)):
        n = cmds[j][0]
        if n in open_names:
            depth += 1
        elif n == close_name:
            depth -= 1
            if depth == 0:
                return j
    return len(cmds) - 1


def run(ctx, cmds, i, end):
    while i < end and not ctx.returned:
        name, raw = cmds[i]
        if name == "if":
            # collect branches
            depth = 0
            branches = []  # (cond_raw or None, start, stop)
            start = i + 1
            cur_cond = raw
            j = i
            k = i + 1
            while k < end:
                n = cmds[k][0]
                if n == "if":
                    depth += 1
                elif n == "endif":
                    if depth == 0:
                        branches.append((cur_cond, start, k))
                        break
                    depth -= 1
                elif n in ("elseif", "else") and depth == 0:
                    branches.append((cur_cond, start, k))
                    cur_cond = cmds[k][1] if n == "elseif" else None
                    start = k + 1
                k += 1
            j = k
            for c, s, e in branches:
                if c is None or ctx.cond(c):
                    run(ctx, cmds, s, e)
                    break
            i = j + 1
            continue
        if name in ("function", "macro"):
            j = find_block_end(
                cmds,
                i,
                ("function", "macro"),
                "endfunction" if name == "function" else "endmacro",
            )
            fname = raw[0][0] if raw else "?"
            ctx.functions.append(fname)
            i = j + 1
            continue
        if name == "foreach":
            j = find_block_end(cmds, i, ("foreach",), "endforeach")
            args = ctx.expand(raw)
            var = args[0] if args else "_"
            items = args[1:]
            if items and items[0] in ("IN",):
                vals = []
                mode = None
                for it in items[1:]:
                    if it in ("LISTS", "ITEMS", "ZIP_LISTS"):
                        mode = it
                        continue
                    if mode == "LISTS":
                        vals.extend(x for x in ctx.vars.get(it, "").split(";") if x)
                    else:
                        vals.append(it)
                items = vals
            elif items and items[0] == "RANGE":
                items = []
            for it in items:
                ctx.vars[var] = it
                run(ctx, cmds, i + 1, j)
            i = j + 1
            continue
        if name == "return":
            ctx.returned = True
            return
        handle(ctx, name, raw)
        i += 1


def handle(ctx, name, raw):
    if name == "set":
        args = ctx.expand(raw)
        if not args:
            return
        vals = [a for a in args[1:] if a not in ("PARENT_SCOPE",)]
        if "CACHE" in vals:
            vals = vals[: vals.index("CACHE")]
        ctx.vars[args[0]] = ";".join(vals)
        return
    if name == "unset":
        args = ctx.expand(raw)
        if args:
            ctx.vars.pop(args[0], None)
        return
    if name == "list":
        args = ctx.expand(raw)
        if len(args) >= 2 and args[0] in ("APPEND", "PREPEND"):
            cur = [x for x in ctx.vars.get(args[1], "").split(";") if x]
            cur = cur + args[2:] if args[0] == "APPEND" else args[2:] + cur
            ctx.vars[args[1]] = ";".join(cur)
        elif len(args) >= 2 and args[0] == "REMOVE_ITEM":
            cur = [x for x in ctx.vars.get(args[1], "").split(";") if x not in args[2:]]
            ctx.vars[args[1]] = ";".join(cur)
        return
    if name == "file":
        args = ctx.expand(raw)
        if args and args[0] in ("GLOB", "GLOB_RECURSE") and len(args) > 2:
            pats = [a for a in args[2:] if a not in ("RELATIVE", "CONFIGURE_DEPENDS")]
            res = []
            for p in pats:
                res.extend("@PKG@/" + f for f in ctx.glob(p))
            ctx.vars[args[1]] = ";".join(res)
        return
    if name == "atlas_os_id":
        args = ctx.expand(raw)
        if len(args) >= 2:
            ctx.vars[args[0]] = "el9"
            ctx.vars[args[1]] = "1"
        return
    if name == "find_package":
        args = ctx.expand(raw)
        if args:
            comps = []
            if "COMPONENTS" in args:
                comps = [
                    a
                    for a in args[args.index("COMPONENTS") + 1 :]
                    if a not in ("QUIET", "REQUIRED", "OPTIONAL_COMPONENTS", "EXACT")
                ]
            ctx.find_packages.setdefault(args[0], set()).update(comps)
        return
    if name in TARGET_CMDS:
        args = ctx.expand(raw)
        if not args:
            return
        kw = split_kw(args[1:])
        t = {"cmd": name, "kind": TARGET_CMDS[name], "name": args[0], "kw": kw}
        ctx.targets.append(t)
        return
    if name in {f.lower() for f in ctx.functions}:
        ctx.wrapper_calls.append(name)
