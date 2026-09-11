#!/usr/bin/env python3
"""Expand simulator-style filelists (.f) into make variables.

Filelists are how essentially every verification project describes its
sources, so a build system that only accepts an explicit list of files in a
makefile is not adoptable.  This understands the subset of the syntax that
VCS/Questa/Xcelium all share:

    // comment                     (also # and --)
    -f  other.f                    include another filelist
    -F  other.f                    same, kept distinct only for familiarity
    +incdir+a/b+c/d                include directories
    +define+NAME=VALUE+OTHER       preprocessor defines
    -y dir  /  +libext+.sv+.v      library directories and extensions
    $VAR / ${VAR}                  environment variable expansion
    path/to/file.sv                a source file

Relative paths - sources, -f targets and +incdir+ entries alike - resolve
against the directory of the filelist that names them, which is what makes a
filelist movable.  Absolute paths are left alone.

Output is a makefile fragment:

    FL_SOURCES  := ...
    FL_INCDIRS  := ...
    FL_DEFINES  := ...
    FL_LIBDIRS  := ...
    FL_LIBEXTS  := ...
    FL_DEPS     := ...   # every .f read, so make can re-expand when one changes

Usage:
    expand_filelist.py [-D NAME=VALUE ...] [-o out.mk] file.f [file.f ...]
"""

import argparse
import os
import re
import shlex
import sys

_VAR = re.compile(r"\$(\w+)|\$\{(\w+)\}")


class FilelistError(Exception):
    pass


def substitute(text, variables, where):
    """Expand $VAR and ${VAR} from `variables`, then the environment."""

    def repl(match):
        name = match.group(1) or match.group(2)
        if name in variables:
            return variables[name]
        if name in os.environ:
            return os.environ[name]
        raise FilelistError(f"{where}: undefined variable '${name}'")

    return _VAR.sub(repl, text)


def strip_comment(line):
    """Remove //, # and -- comments, honouring quotes."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        elif line.startswith("//", i) or line.startswith("--", i):
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out).strip()


class Expander:
    def __init__(self, variables):
        self.variables = variables
        self.sources = []
        self.incdirs = []
        self.defines = []
        self.libdirs = []
        self.libexts = []
        self.deps = []
        self._seen = set()

    @staticmethod
    def _add(collection, value):
        # Order matters for sources (compile order) and for incdirs (search
        # order), so keep first-seen position rather than sorting.
        if value not in collection:
            collection.append(value)

    def _resolve(self, path, base):
        return path if os.path.isabs(path) else os.path.normpath(os.path.join(base, path))

    def read(self, filelist):
        filelist = os.path.abspath(filelist)
        if filelist in self._seen:
            # A filelist included twice is normal in a big project; reading it
            # once is right, and it also stops an accidental cycle.
            return
        self._seen.add(filelist)
        self._add(self.deps, filelist)

        if not os.path.isfile(filelist):
            raise FilelistError(f"filelist not found: {filelist}")

        base = os.path.dirname(filelist)
        with open(filelist, encoding="utf-8") as handle:
            for lineno, raw in enumerate(handle, 1):
                line = strip_comment(raw)
                if not line:
                    continue
                where = f"{filelist}:{lineno}"
                line = substitute(line, self.variables, where)
                try:
                    tokens = shlex.split(line)
                except ValueError as exc:
                    raise FilelistError(f"{where}: {exc}") from exc
                self._tokens(tokens, base, where)

    def _tokens(self, tokens, base, where):
        index = 0
        while index < len(tokens):
            token = tokens[index]
            index += 1

            if token in ("-f", "-F", "-file"):
                if index >= len(tokens):
                    raise FilelistError(f"{where}: {token} with no filelist")
                self.read(self._resolve(tokens[index], base))
                index += 1

            elif token.startswith("+incdir+"):
                for entry in token[len("+incdir+"):].split("+"):
                    if entry:
                        self._add(self.incdirs, self._resolve(entry, base))

            elif token.startswith("+define+"):
                for entry in token[len("+define+"):].split("+"):
                    if entry:
                        self._add(self.defines, entry)

            elif token.startswith("+libext+"):
                for entry in token[len("+libext+"):].split("+"):
                    if entry:
                        self._add(self.libexts, entry)

            elif token == "-y":
                if index >= len(tokens):
                    raise FilelistError(f"{where}: -y with no directory")
                self._add(self.libdirs, self._resolve(tokens[index], base))
                index += 1

            elif token in ("-incdir", "-I"):
                if index >= len(tokens):
                    raise FilelistError(f"{where}: {token} with no directory")
                self._add(self.incdirs, self._resolve(tokens[index], base))
                index += 1

            elif token.startswith("-"):
                # Anything else is a tool switch this build system does not
                # interpret. Passing it blindly to Verilator would usually be
                # wrong (most are VCS/Questa-specific), so say so rather than
                # failing obscurely later.
                print(f"warning: {where}: ignoring unrecognised option '{token}'",
                      file=sys.stderr)

            else:
                self._add(self.sources, self._resolve(token, base))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("filelists", nargs="+")
    parser.add_argument("-D", "--define", action="append", default=[],
                        metavar="NAME=VALUE",
                        help="variable available to $NAME expansion in the filelist")
    parser.add_argument("-o", "--output", help="write the makefile fragment here")
    args = parser.parse_args()

    variables = {}
    for item in args.define:
        name, _, value = item.partition("=")
        variables[name] = value

    expander = Expander(variables)
    try:
        for filelist in args.filelists:
            expander.read(filelist)
    except FilelistError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    fragment = "\n".join([
        "# Generated by uvmake/scripts/expand_filelist.py - do not edit.",
        "FL_SOURCES := " + " ".join(expander.sources),
        "FL_INCDIRS := " + " ".join(expander.incdirs),
        "FL_DEFINES := " + " ".join(expander.defines),
        "FL_LIBDIRS := " + " ".join(expander.libdirs),
        "FL_LIBEXTS := " + " ".join(expander.libexts),
        "FL_DEPS    := " + " ".join(expander.deps),
        "",
    ])

    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(fragment)
    else:
        sys.stdout.write(fragment)
    return 0


if __name__ == "__main__":
    sys.exit(main())
