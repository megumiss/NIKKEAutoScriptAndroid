#!/usr/bin/env python3
"""Collect native dependency licenses into Flutter assets from pinned source trees."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request
import zipfile

from build_ios_adb import ADB_REVISION, CACHE, PROTOBUF_REVISION, ROOT
from build_tsnet import GO_VERSION, MOBILE_VERSION

OUTPUT = ROOT / 'assets/licenses'
LICENSE_NAME = re.compile(r'^(licen[cs]e|copying|notice|patents)([._-].*)?$', re.I)


def capture(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True, encoding='utf-8')


def json_objects(raw):
    decoder = json.JSONDecoder()
    while raw.strip():
        value, end = decoder.raw_decode(raw.lstrip())
        yield value
        raw = raw.lstrip()[end:]


def license_files(root, directories):
    found = set()
    for directory in directories | {root}:
        while directory.is_relative_to(root):
            found.update(path for path in directory.iterdir() if path.is_file() and LICENSE_NAME.match(path.name))
            if directory == root:
                break
            directory = directory.parent
    return sorted(found, key=lambda path: path.relative_to(root).as_posix())


def entry(name, version, source, files, root, **extra):
    if not files:
        raise SystemExit(f'No license text found for {name}')
    notices = []
    for path in files:
        text = path.read_text(encoding='utf-8').strip()
        if text:
            notices.append({'file': path.relative_to(root).as_posix(), 'text': text})
    if not notices:
        raise SystemExit(f'Only empty license markers found for {name}')
    return {'name': name, 'version': version, 'source': source, 'licenses': notices, **extra}


def collect_go():
    env = os.environ | {'GOTOOLCHAIN': GO_VERSION, 'CGO_ENABLED': '1'}
    module_dir = ROOT / 'native/tsnet'
    modules = {}
    for platform in ('android', 'ios'):
        packages = json_objects(capture('go', 'list', '-deps', '-json', '.', cwd=module_dir,
                                       env=env | {'GOOS': platform, 'GOARCH': 'arm64'}))
        for package in packages:
            module = package.get('Module')
            if not module or module.get('Main'):
                continue
            value = modules.setdefault(module['Path'], {
                'root': Path(module['Dir']), 'version': module['Version'], 'directories': set(), 'platforms': set(),
            })
            value['directories'].add(Path(package['Dir']))
            value['platforms'].add(platform)
    # Tool-only modules are not downloaded by go list -deps on a clean runner.
    mobile = json.loads(capture('go', 'mod', 'download', '-json', 'golang.org/x/mobile', cwd=module_dir, env=env))
    assert mobile['Version'] == MOBILE_VERSION
    modules[mobile['Path']] = {'root': Path(mobile['Dir']), 'version': mobile['Version'],
                               'directories': set(), 'platforms': {'android', 'ios'}}
    result = []
    go_root = Path(capture('go', 'env', 'GOROOT', env=env).strip())
    result.append(entry('Go runtime', GO_VERSION, 'https://go.dev', [go_root / 'LICENSE'], go_root))
    result.append(entry('tsnet-forwarder mobile adaptation', 'vendored', 'https://github.com/megumiss/tsnet-forwarder',
                        [module_dir / 'LICENSE'], module_dir))
    for name, value in sorted(modules.items()):
        source = ('https://' + name) if not name.startswith('golang.org/x/') else ('https://go.googlesource.com/' + name.split('/')[-1])
        result.append(entry(name, value['version'], source, license_files(value['root'], value['directories']),
                            value['root'], platforms=sorted(value['platforms'])))
    return result


def collect_ios():
    root = CACHE / 'adb-mobile'
    if capture('git', 'rev-parse', 'HEAD', cwd=root).strip() != ADB_REVISION:
        raise SystemExit('Run build_ios_adb.py --prepare-only to check out the pinned ADB sources')
    protobuf = root / 'external/protobuf'
    if capture('git', 'rev-parse', 'HEAD', cwd=protobuf).strip() != PROTOBUF_REVISION:
        raise SystemExit('The protobuf source revision differs from the build pin')
    groups = [
        ('android-tools', 'android-tools', ['LICENSE']),
        ('AOSP ADB', 'android-tools/vendor/adb', ['NOTICE']),
        ('AOSP libcutils', 'android-tools/vendor/core', ['libcutils/NOTICE']),
        ('AOSP libbase', 'android-tools/vendor/libbase', ['NOTICE']),
        ('AOSP liblog', 'android-tools/vendor/logging', ['liblog/NOTICE']),
        ('BoringSSL', 'android-tools/vendor/boringssl', ['LICENSE']),
        ('fmt', 'android-tools/vendor/fmtlib', ['LICENSE']),
        ('LZ4', 'external/lz4', ['lib/LICENSE']),
        ('Zstandard', 'external/zstd', ['LICENSE', 'COPYING']),
        ('Brotli', 'external/brotli', ['LICENSE']),
        ('Protocol Buffers', 'external/protobuf', ['LICENSE']),
        ('Abseil', 'external/protobuf/third_party/abseil-cpp', ['LICENSE']),
        ('utf8_range', 'external/protobuf', ['third_party/utf8_range/LICENSE']),
    ]
    result = []
    for name, directory, paths in groups:
        folder = root / directory
        version = capture('git', 'rev-parse', 'HEAD', cwd=folder).strip()
        source = capture('git', 'remote', 'get-url', 'origin', cwd=folder).strip()
        result.append(entry(name, version, source, [folder / path for path in paths], folder))
    # These AOSP directories have per-file Apache headers but no separate NOTICE.
    for name, directory, source_file in [
        ('AOSP libziparchive', 'libziparchive', 'zip_archive.cc'),
        ('AOSP libcrypto_utils', 'core', 'libcrypto_utils/android_pubkey.cpp'),
        ('AOSP diagnose_usb', 'core', 'diagnose_usb/diagnose_usb.cpp'),
    ]:
        folder = root / 'android-tools/vendor' / directory
        source_text = (folder / source_file).read_text(encoding='utf-8')
        header = source_text[:source_text.index('*/') + 2]
        result.append({'name': name, 'version': capture('git', 'rev-parse', 'HEAD', cwd=folder).strip(),
                       'source': capture('git', 'remote', 'get-url', 'origin', cwd=folder).strip(),
                       'licenses': [{'file': source_file + ' (copyright header)', 'text': header},
                                    {'file': 'Apache-2.0', 'text': (ROOT / 'LICENSE').read_text(encoding='utf-8').strip()}]})
    result.append({'name': 'adb-mobile porting', 'version': ADB_REVISION,
                   'source': 'https://github.com/wsvn53/adb-mobile',
                   'licenses': [{'file': 'provenance', 'text':
                       'The pinned adb-mobile revision has no top-level LICENSE for its porting glue. '
                       'Modified AOSP files retain their Apache-2.0 headers; those texts are preserved above. '
                       'The parent scrcpy-mobile MIT license does not relicense this submodule. '
                       'Resolve the separate porting-glue license before redistributing that code.'}]})
    return result


def download(url):
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def collect_shared():
    result = []
    for name, version, urls in [
        ('scrcpy server', '4.1', ['https://raw.githubusercontent.com/Genymobile/scrcpy/v4.1/LICENSE']),
        ('Conscrypt Android', '2.7.0', [
            'https://raw.githubusercontent.com/google/conscrypt/2.7.0/LICENSE',
            'https://raw.githubusercontent.com/google/conscrypt/2.7.0/NOTICE']),
        ('Noto Sans SC', 'OFL-1.1', ['https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt']),
    ]:
        result.append({'name': name, 'version': version, 'source': urls[0],
                       'licenses': [{'file': url.rsplit('/', 1)[-1], 'text': download(url).decode('utf-8').strip()}
                                    for url in urls]})
    gradle = Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle')) / 'caches/modules-2/files-2.1'
    for artifact in ('bcpkix-jdk18on', 'bcprov-jdk18on', 'bcutil-jdk18on'):
        url = f'https://repo.maven.apache.org/maven2/org/bouncycastle/{artifact}/1.85/{artifact}-1.85.jar'
        cached = list((gradle / 'org.bouncycastle' / artifact / '1.85').glob('*/*.jar'))
        data = cached[0].read_bytes() if len(cached) == 1 else download(url)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            text = archive.read('META-INF/LICENSE.md').decode('utf-8').strip()
        result.append({'name': artifact, 'version': '1.85', 'source': url,
                       'licenses': [{'file': 'META-INF/LICENSE.md', 'text': text}]})
    return result


def collect(group, check):
    values = {'go': collect_go, 'ios': collect_ios, 'shared': collect_shared}[group]()
    for value in values:
        for notice in value['licenses']:
            notice['sha256'] = hashlib.sha256(notice['text'].encode('utf-8')).hexdigest()
    payload = json.dumps(values, ensure_ascii=False, indent=2) + '\n'
    path = OUTPUT / (group + '.json')
    if check:
        if not path.exists() or path.read_text(encoding='utf-8') != payload:
            raise SystemExit(f'Native licenses are stale: run python tool/collect_native_licenses.py {group}')
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding='utf-8', newline='\n')
    print(f'{group}: {len(values)} native license entries verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('group', choices=['go', 'ios', 'shared'])
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    collect(args.group, args.check)
