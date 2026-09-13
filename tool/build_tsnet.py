#!/usr/bin/env python3
"""Build the pinned, application-scoped tsnet bindings for Android or iOS."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
GO_VERSION = 'go1.23.12'
MOBILE_VERSION = 'v0.0.0-20240806205939-81131f6468ab'
NDK_VERSION = '28.2.13676358'
ANDROID_ABIS = {'armeabi-v7a', 'arm64-v8a', 'x86_64'}


def run(*args, env, cwd=None):
    subprocess.run([str(arg) for arg in args], env=env, cwd=cwd, check=True)


def build(target):
    env = os.environ.copy()
    env['GOTOOLCHAIN'] = GO_VERSION
    go = shutil.which('go')
    if not go:
        raise SystemExit(f'Install Go 1.23.12 and add its bin directory to PATH.')
    version = subprocess.check_output([go, 'version'], env=env, text=True)
    if version.split()[2] != GO_VERSION:
        raise SystemExit(f'Expected {GO_VERSION}, found {version.strip()}')
    if target == 'ios' and sys.platform != 'darwin':
        raise SystemExit('iOS bindings require macOS and Xcode.')
    if target == 'android':
        sdk = env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT')
        if not sdk:
            raise SystemExit('Set ANDROID_HOME to the Android SDK directory.')
        ndk = Path(sdk) / 'ndk' / NDK_VERSION
        if not (ndk / 'source.properties').is_file():
            raise SystemExit(f'Install Android NDK {NDK_VERSION} in {sdk}.')
        env.update(ANDROID_HOME=sdk, ANDROID_NDK_HOME=str(ndk))
    tools = ROOT / 'build' / 'native-tools' / 'bin'
    tools.mkdir(parents=True, exist_ok=True)
    env['GOBIN'] = str(tools)
    env['PATH'] = str(tools) + os.pathsep + env.get('PATH', '')
    run(go, 'install', f'golang.org/x/mobile/cmd/gomobile@{MOBILE_VERSION}', env=env)
    run(go, 'install', f'golang.org/x/mobile/cmd/gobind@{MOBILE_VERSION}', env=env)
    gomobile = tools / ('gomobile.exe' if sys.platform == 'win32' else 'gomobile')
    module = ROOT / 'native' / 'tsnet'
    run(go, 'mod', 'download', env=env, cwd=module)
    if target == 'android':
        output = ROOT / 'native' / 'android' / 'nkas-tsnet.aar'
        options = ['-target=android/arm,android/arm64,android/amd64', '-androidapi=26',
                   '-javapkg=com.megumiss.nkas.tsnet']
    else:
        output = ROOT / 'native' / 'apple' / 'NkasTsnet.xcframework'
        options = ['-target=ios,iossimulator', '-iosversion=15.0', '-prefix=Nkas']
    output.parent.mkdir(parents=True, exist_ok=True)
    run(gomobile, 'bind', *options, '-trimpath', '-ldflags=-s -w', '-o', output, '.', env=env, cwd=module)
    if target == 'android':
        with zipfile.ZipFile(output) as archive:
            abis = {name.split('/')[1] for name in archive.namelist()
                    if name.startswith('jni/') and name.endswith('.so')}
        if abis != ANDROID_ABIS:
            raise SystemExit(f'Unexpected native ABIs: {sorted(abis)}')
    print(f'Built {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=['android', 'ios'])
    build(parser.parse_args().target)
