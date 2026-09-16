"""Catch Swift scope errors that a Windows host cannot compile away.

The last CI run failed with "Cannot find 'streamTimeout' in scope": a property
of NkasIosAdbClient was referenced from NkasIosAdbStream, a different type in
the same file. `flutter analyze` only reads Dart, and a grep for call sites
does not see it either, so check the structural condition directly.

Method: split each file into top-level type chunks, collect the members each
chunk declares, then flag any bare (undotted) member-style identifier used
inside one chunk that only a *different* chunk declares. A bare use of another
type's member cannot compile -- it needs `someInstance.member`.

Only identifiers that are known members of a sibling type are reported, so
framework symbols, enum cases and locals stay quiet.
"""

import re
from pathlib import Path

SWIFT_FILES = sorted(Path('ios/Runner').glob('*.swift'))

DECL = re.compile(
    r'^(?:public |internal |private |fileprivate |final |static |override |'
    r'@\w+ )*(class|struct|enum|protocol|extension)\s+(\w+)',
)
MEMBER = re.compile(
    r'^\s*(?:@\w+ )*(?:public |internal |private |fileprivate |static |final |'
    r'override |@discardableResult )*(?:let|var|func)\s+(\w+)',
    re.MULTILINE,
)
CASE = re.compile(r'^\s*case\s+(\w+)', re.MULTILINE)

# Function parameters, including the `_ name:` and `name:` external forms, plus
# the two-label form `external internal:`.
PARAM = re.compile(r'[(,]\s*(?:_\s+)?([a-z][A-Za-z0-9_]*)\s*:')
# Local bindings introduced by let/var/for/case inside a body.
LOCAL = re.compile(r'\b(?:let|var|for|case)\s+(?:\w+\s*:\s*)?([a-z][A-Za-z0-9_]*)')
# Closure parameter lists: `{ data, _, _, error in` and `{ [weak self] value in`.
CLOSURE = re.compile(r'\{\s*(?:\[[^\]]*\]\s*)?([a-z_][\w\s,]*?)\s+in\b')

# Identifiers a bare-identifier scan would otherwise pick up spuriously.
NOISE = {
    'self', 'let', 'var', 'func', 'init', 'if', 'else', 'guard', 'return',
    'throws', 'rethrows', 'try', 'catch', 'do', 'while', 'for', 'in', 'case',
    'switch', 'default', 'break', 'continue', 'defer', 'where', 'is', 'as',
    'nil', 'true', 'false', 'super', 'some', 'any', 'each', 'repeat', 'print',
    'FileManager', 'DispatchQueue', 'Bundle', 'Data', 'String', 'Int', 'UUID',
}

USE = re.compile(r'(?<![\w.])([a-z][A-Za-z0-9_]*)(?=\s*[.(=)])')


def strip_literals(line: str) -> str:
    line = re.sub(r'//.*', '', line)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', line)


def chunks(text: str):
    """Split into (start_line_index, kind, type_name, body) top-level chunks."""
    lines = text.splitlines()
    result = []
    start = depth = 0
    pending = None
    for number, raw in enumerate(lines):
        code = strip_literals(raw)
        if depth == 0 and pending is None:
            if match := DECL.match(code):
                pending = (number, match.group(1), match.group(2))
        depth += code.count('{') - code.count('}')
        if pending is not None and depth == 0:
            result.append((
                pending[0], pending[1], pending[2],
                '\n'.join(lines[pending[0]:number + 1]),
            ))
            pending = None
    return result


def main() -> int:
    problems = []

    if not SWIFT_FILES:
        print('未找到 ios/Runner 下的 Swift 文件，请在仓库根目录执行。')
        return 1

    for path in SWIFT_FILES:
        raw = path.read_text(encoding='utf-8')
        text = '\n'.join(strip_literals(line) for line in raw.splitlines())
        # Extensions are skipped entirely: an extension's members are not
        # reliably attributable to the extension when the extended type is a
        # framework type, so treating them as a sibling's members would only
        # produce false positives (Data.index, for example).
        parts = [part for part in chunks(text) if part[1] != 'extension']
        if not parts:
            continue

        declared = {
            name: set(MEMBER.findall(body)) | set(CASE.findall(body))
            for _, _, name, body in parts
        }

        for start, _, name, body in parts:
            own = declared[name]
            # Parameters, locals and closure parameters are all in scope for a
            # bare use, so they must not be mistaken for a sibling's member.
            local_names = (
                set(PARAM.findall(body))
                | set(LOCAL.findall(body))
                | set(CLOSURE.findall(body))
            )
            for match in CLOSURE.finditer(body):
                for token in re.split(r'[\s,]+', match.group(1)):
                    if token and token != '_':
                        local_names.add(token.strip('[]'))
            elsewhere = set().union(
                *(members for other, members in declared.items() if other != name)
            )
            for used in sorted(set(USE.findall(body))):
                # A member of a sibling type can only be reached through a dot,
                # so any bare use of it is the error we are looking for.
                if used in own or used in NOISE or used in declared:
                    continue
                if used in local_names or used not in elsewhere:
                    continue
                for offset, snippet in enumerate(body.splitlines()):
                    if USE.search(snippet) and re.search(
                        rf'(?<![\w.]){re.escape(used)}(?=\s*[.(=)])', snippet
                    ):
                        problems.append(
                            f'{path}:{start + offset + 1}: 类型 {name} 裸用了 {used}，'
                            f'它是同文件另一个类型的成员，必须显式传入'
                        )

    if problems:
        print('发现跨类型的作用域误用：')
        for problem in sorted(set(problems)):
            # GitHub renders `::error file=...,line=...::` as an inline
            # annotation on the diff, so CI points at the offending line.
            line = problem.rsplit(':', 2)
            if len(line) == 3 and line[1].isdigit():
                print(f'::error file={line[0]},line={line[1]}::{problem}')
            print('  ' + problem)
        return 1
    print(f'已检查 {len(SWIFT_FILES)} 个 Swift 文件，未发现跨类型的作用域误用。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
