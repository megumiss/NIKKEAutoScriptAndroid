#!/usr/bin/env python3
"""Verify bundled scrcpy, native licenses and generated native artifacts."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

from build_ios_adb import ADB_REVISION, ROOT
from build_tsnet import ANDROID_ABIS

SCRCPY_HASH = 'deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae'
EXPECTED_IOS = {('ios', '', 'arm64'), ('ios', 'simulator', 'arm64'), ('ios', 'simulator', 'x86_64')}


def check(condition, message):
    if not condition:
        raise SystemExit(message)


def verify_server(data, path):
    check(hashlib.sha256(data).hexdigest() == SCRCPY_HASH, f'scrcpy 4.1 SHA-256 mismatch: {path}')


def verify_sources():
    verify_server((ROOT / 'ios/Runner/scrcpy-server-v4.1').read_bytes(), 'iOS resource')
    names = set()
    for group in ('go', 'ios', 'shared'):
        path = ROOT / 'assets/licenses' / (group + '.json')
        entries = json.loads(path.read_text(encoding='utf-8'))
        check(bool(entries), f'Empty license group: {group}')
        for entry in entries:
            names.add(entry['name'])
            check(entry['version'] and entry['source'] and entry['licenses'], f'Incomplete license entry: {entry["name"]}')
            for notice in entry['licenses']:
                check(hashlib.sha256(notice['text'].encode('utf-8')).hexdigest() == notice['sha256'],
                      f'License text hash mismatch: {entry["name"]}/{notice["file"]}')
    expected = {'tailscale.com', 'Go runtime', 'tsnet-forwarder mobile adaptation', 'AOSP ADB',
                'BoringSSL', 'GoogleTest headers', 'Abseil', 'Protocol Buffers', 'utf8_range',
                'LZ4', 'Zstandard', 'Brotli',
                'scrcpy server', 'Conscrypt Android', 'bcpkix-jdk18on', 'bcprov-jdk18on', 'bcutil-jdk18on'}
    check(expected <= names, f'Missing native notices: {sorted(expected - names)}')
    print(f'Bundled scrcpy and {len(names)} native license entries verified')


def verify_android():
    path = ROOT / 'native/android/nkas-tsnet.aar'
    with zipfile.ZipFile(path) as archive:
        libraries = [name for name in archive.namelist() if name.startswith('jni/') and name.endswith('.so')]
        abis = {name.split('/')[1] for name in libraries}
        check(abis == ANDROID_ABIS, f'Unexpected AAR ABIs: {abis}')
        check(all(archive.getinfo(name).file_size > 0 for name in libraries), 'Empty AAR native library')
        check('classes.jar' in archive.namelist(), 'AAR has no Java bindings')
    resource = ROOT / 'android/app/src/main/assets/bin/scrcpy-server-v4.1'
    verify_server(resource.read_bytes(), resource)
    print(f'Android AAR verified: {", ".join(sorted(abis))}')


def verify_xcframework(path):
    with (path / 'Info.plist').open('rb') as file:
        metadata = plistlib.load(file)
    actual = set()
    for library in metadata['AvailableLibraries']:
        framework = path / library['LibraryIdentifier'] / library['LibraryPath']
        binary = framework / framework.stem
        check(binary.is_file(), f'XCFramework binary missing: {binary}')
        declared = set(library['SupportedArchitectures'])
        if sys.platform == 'darwin':
            archs = set(subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split())
            check(archs == declared, f'XCFramework architecture manifest mismatch: {binary}')
        actual.update((library['SupportedPlatform'], library.get('SupportedPlatformVariant', ''), arch) for arch in declared)
    check(actual == EXPECTED_IOS, f'Unexpected XCFramework slices: {path}: {actual}')


def verify_ios():
    for name in ('AdbMobile', 'NkasTsnet'):
        verify_xcframework(ROOT / 'native/apple' / (name + '.xcframework'))
    revision = (ROOT / 'native/apple/AdbMobile.xcframework/SOURCE_REVISION').read_text(encoding='utf-8').strip()
    check(revision == ADB_REVISION, 'ADB XCFramework revision is stale')
    print('iOS frameworks verified: device arm64; simulator arm64 and x86_64')


def verify_apk(path):
    with zipfile.ZipFile(path) as archive:
        verify_server(archive.read('assets/bin/scrcpy-server-v4.1'), path)
        abis = {name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('/libgojni.so')}
        check(abis == ANDROID_ABIS, f'APK tsnet ABIs differ from AAR: {abis}')
        for group in ('go', 'ios', 'shared'):
            source = ROOT / 'assets/licenses' / (group + '.json')
            check(archive.read(f'assets/flutter_assets/assets/licenses/{group}.json') == source.read_bytes(),
                  f'APK is missing current native licenses: {group}')
    print('APK native binaries, scrcpy resource and license assets verified')


def verify_app(path):
    verify_server((path / 'scrcpy-server-v4.1').read_bytes(), path)
    for group in ('go', 'ios', 'shared'):
        source = ROOT / 'assets/licenses' / (group + '.json')
        bundled = path / f'Frameworks/App.framework/flutter_assets/assets/licenses/{group}.json'
        check(bundled.read_bytes() == source.read_bytes(), f'iOS app is missing current native licenses: {group}')
    print('iOS app scrcpy resource and license assets verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android', action='store_true')
    parser.add_argument('--ios', action='store_true')
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    verify_sources()
    if args.android:
        verify_android()
    if args.ios:
        verify_ios()
    if args.apk:
        verify_apk(args.apk)
    if args.app:
        verify_app(args.app)
