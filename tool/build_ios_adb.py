#!/usr/bin/env python3
"""Build the pinned in-process ADB core and link-check every iOS slice."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys

ADB_REVISION = '78c32c2339402519796ba80a6518254efa8a21bf'
PROTOBUF_REVISION = '5fda5abda3dee5f7a102c85860594bff8d8610bd'  # v28.3 (peeled commit)
ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build' / 'native-adb'
BINDING = ROOT / 'native' / 'adb'
OUTPUT = ROOT / 'native' / 'apple' / 'AdbMobile.xcframework'
VENDORS = ('adb', 'core', 'libbase', 'libziparchive', 'logging', 'boringssl', 'fmtlib')
PROTO_FILES = ('app_processes', 'adb_host', 'key_type', 'adb_known_hosts', 'pairing')


def run(*args, cwd=None):
    if args[0] == 'git':
        args = ('git', '-c', 'http.version=HTTP/1.1', '-c', 'http.lowSpeedTime=60',
                '-c', 'http.lowSpeedLimit=1000', *args[1:])
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def cache_path(path):
    resolved = path.resolve()
    if not resolved.is_relative_to(CACHE.resolve()) or resolved == CACHE.resolve():
        raise SystemExit(f'Refusing to reset a checkout outside the native build cache: {path}')
    return resolved


def reset_checkout(path):
    cache_path(path)
    if not (path / '.git').exists():
        return
    # Only the build-owned checkout is reset; never the developer's reference repository.
    modules = path / '.gitmodules'
    if modules.is_file():
        values = subprocess.run(['git', 'config', '--file', str(modules), '--get-regexp', 'path'],
                                text=True, encoding='utf-8', capture_output=True, check=False)
        if values.returncode not in (0, 1):
            raise SystemExit(values.stderr)
        for line in values.stdout.splitlines():
            reset_checkout(path / line.split(None, 1)[1])
    run('git', 'reset', '--hard', cwd=path)
    run('git', 'clean', '-fd', cwd=path)


def checkout_source():
    source = cache_path(CACHE / 'adb-mobile')
    if not (source / '.git').exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run('git', 'clone', '--no-checkout', 'https://github.com/wsvn53/adb-mobile.git', source)
    reset_checkout(source)
    run('git', 'checkout', '--force', '--detach', ADB_REVISION, cwd=source)
    run('git', 'submodule', 'update', '--init', '--force', '--depth', '1', '--jobs', '4', '--',
        'android-tools', 'external/lz4', 'external/zstd', 'external/brotli', 'external/protobuf', cwd=source)
    run('git', 'submodule', 'update', '--init', '--force', '--depth', '1', '--jobs', '4', '--',
        *(f'vendor/{name}' for name in VENDORS), cwd=source / 'android-tools')
    protobuf = source / 'external/protobuf'
    if subprocess.run(['git', 'cat-file', '-e', PROTOBUF_REVISION], cwd=protobuf,
                      capture_output=True).returncode:
        run('git', 'fetch', 'origin', PROTOBUF_REVISION, cwd=protobuf)
    run('git', 'checkout', '--force', '--detach', PROTOBUF_REVISION, cwd=protobuf)
    run('git', 'submodule', 'update', '--init', '--recursive', '--force', '--depth', '1', '--',
        'third_party/abseil-cpp', cwd=protobuf)
    return source


def prepare_vendor(source):
    vendor = source / 'android-tools/vendor'
    for name in VENDORS:
        for patch in sorted((source / 'android-tools/patches' / name).glob('*.patch')):
            apply_source_patch(vendor / name, patch)
    for item in (source / 'porting/adb/client').iterdir():
        if item.is_file():
            shutil.copy2(item, vendor / 'adb/client' / item.name)
    shutil.copytree(source / 'porting/adb/include/sys', vendor / 'libbase/include/sys', dirs_exist_ok=True)
    shutil.copy2(BINDING / 'nkas_embedded.inc', vendor / 'adb/client/nkas_embedded.inc')
    apply_source_patch(vendor / 'adb', BINDING / 'embedded.patch')
    apply_source_patch(source / 'external/protobuf/third_party/abseil-cpp', BINDING / 'abseil-apple.patch')
    shutil.copy2(BINDING / 'CMakeLists.ios.txt', vendor / 'CMakeLists.txt')

    adb_cmake = (vendor / 'CMakeLists.adb.txt').read_text(encoding='utf-8')
    adb_cmake = adb_cmake.split('add_executable(adb', 1)[0]
    # main.cpp already includes socket_spec.cpp and the remaining transport core.
    if adb_cmake.count('\tadb/socket_spec.cpp\n') != 1:
        raise SystemExit('Unexpected upstream socket_spec source list')
    adb_cmake = adb_cmake.replace('\tadb/socket_spec.cpp\n', '')

    def generated(match):
        source_var, header_var, filename = match.groups()
        return (f'set({source_var} "${{NKAS_GENERATED_PROTO_DIR}}/{filename}.pb.cc")\n'
                f'set({header_var} "${{NKAS_GENERATED_PROTO_DIR}}/{filename}.pb.h")')
    adb_cmake, count = re.subn(r'protobuf_generate_cpp\((\w+)\s+(\w+)\s+adb/proto/(\w+)\.proto\)',
                              generated, adb_cmake)
    if count != len(PROTO_FILES):
        raise SystemExit('Unexpected upstream protobuf source list')
    (vendor / 'CMakeLists.adb-ios.txt').write_text(adb_cmake, encoding='utf-8')
    zip_cmake = (vendor / 'CMakeLists.fastboot.txt').read_text(encoding='utf-8').split('add_library(libutil', 1)[0]
    if 'add_library(libzip STATIC' not in zip_cmake or 'libselinux' in zip_cmake:
        raise SystemExit('Unexpected upstream libzip source list')
    (vendor / 'CMakeLists.zip-ios.txt').write_text(zip_cmake, encoding='utf-8')
    return vendor


def apply_source_patch(repository, patch):
    # git apply accepts bare empty context lines with LF, but rejects them after
    # a Windows checkout converts a mail patch to CRLF.
    normalized = CACHE / 'patches' / repository.name / patch.name
    normalized.parent.mkdir(parents=True, exist_ok=True)
    normalized.write_text(patch.read_text(encoding='utf-8'), encoding='utf-8', newline='\n')
    run('git', 'apply', '--check', normalized, cwd=repository)
    run('git', 'apply', '--whitespace=nowarn', normalized, cwd=repository)


def configure(source, build, *options):
    run('cmake', '-G', 'Unix Makefiles', '-S', source, '-B', build,
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', *options)


def compile_target(build, target):
    # Report independent compilation failures together while preserving a failed exit status.
    run('cmake', '--build', build, '--parallel', '4', '--target', target, '--', '-k')


def linked_archives(build):
    commands = list(build.rglob('nkas_adb_link_check.dir/link.txt'))
    if len(commands) != 1:
        raise SystemExit('Expected one CMake link command for the ADB check executable')
    link = commands[0]
    directory = link.parent.parent.parent
    command = shlex.split(link.read_text(encoding='utf-8'))
    archives = []
    for argument in command:
        if argument.endswith('.a'):
            archive = (directory / argument).resolve()
            if not archive.is_relative_to(build.resolve()) or not archive.is_file():
                raise SystemExit(f'Unexpected static archive in iOS link: {archive}')
            if archive not in archives:
                archives.append(archive)
    if not archives:
        raise SystemExit('ADB link check did not link any static archives')
    return directory, command, archives


def merge_and_check(build):
    directory, command, archives = linked_archives(build)
    library = build / 'libadb-full.a'
    run('xcrun', 'libtool', '-static', '-o', library, *archives)
    merged = []
    for argument in command:
        if argument.endswith('.a'):
            if str(library) not in merged:
                merged.append(str(library))
        else:
            merged.append(argument)
    merged[merged.index('-o') + 1] = 'nkas_adb_merged_link_check'
    run(*merged, cwd=directory)
    (build / 'linked-archives.json').write_text(json.dumps(
        [str(path.relative_to(build)) for path in archives], indent=2) + '\n', encoding='utf-8')
    return library


def framework(library, destination, sdk):
    if destination.exists():
        shutil.rmtree(cache_path(destination))
    headers = destination / 'Headers'
    headers.mkdir(parents=True, exist_ok=True)
    shutil.copy2(library, destination / 'AdbMobile')
    shutil.copy2(BINDING / 'AdbMobile.h', headers / 'AdbMobile.h')
    modules = destination / 'Modules'
    modules.mkdir(exist_ok=True)
    (modules / 'module.modulemap').write_text(
        'framework module AdbMobile {\n  umbrella header "AdbMobile.h"\n  export *\n}\n', encoding='utf-8')
    sdk_version = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-version'], text=True).strip()
    with (destination / 'Info.plist').open('wb') as file:
        plistlib.dump({
            'CFBundleIdentifier': 'com.megumiss.nkas.AdbMobile', 'CFBundleName': 'AdbMobile',
            'CFBundleExecutable': 'AdbMobile', 'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '1',
            'CFBundleShortVersionString': '35.0.2', 'MinimumOSVersion': '15.0',
            'CFBundleSupportedPlatforms': ['iPhoneOS' if sdk == 'iphoneos' else 'iPhoneSimulator'],
            'DTSDKName': sdk + sdk_version,
        }, file)


def build(prepare_only=False):
    if not prepare_only:
        if sys.platform != 'darwin':
            raise SystemExit('iOS native compilation requires macOS, Xcode, CMake and Go 1.24.13.')
        for command in ('git', 'cmake', 'xcrun', 'xcodebuild', 'go'):
            if not shutil.which(command):
                raise SystemExit(f'Missing build tool: {command}')
    source = checkout_source()
    vendor = prepare_vendor(source)
    if prepare_only:
        print(f'Pinned ADB sources and embedded patches verified: {vendor}')
        return
    protobuf = source / 'external/protobuf'
    host_build = CACHE / 'host-protobuf'
    configure(protobuf, host_build, '-Dprotobuf_BUILD_TESTS=OFF', '-Dprotobuf_BUILD_SHARED_LIBS=OFF',
              '-Dprotobuf_BUILD_PROTOC_BINARIES=ON', '-Dprotobuf_BUILD_LIBPROTOC=ON',
              '-Dprotobuf_WITH_ZLIB=OFF', '-DCMAKE_CXX_STANDARD=20', '-DABSL_PROPAGATE_CXX_STD=ON')
    compile_target(host_build, 'protoc')
    protoc = host_build / 'protoc'
    if not protoc.is_file():
        raise SystemExit(f'Host protoc was not produced: {protoc}')
    generated = CACHE / 'generated'
    generated.mkdir(exist_ok=True)
    run(protoc, f'--proto_path={vendor / "adb/proto"}', f'--cpp_out={generated}',
        *(str(vendor / 'adb/proto' / (name + '.proto')) for name in PROTO_FILES))

    archives = {}
    for sdk, arch in [('iphoneos', 'arm64'), ('iphonesimulator', 'arm64'), ('iphonesimulator', 'x86_64')]:
        build_dir = CACHE / sdk / arch
        configure(source / 'android-tools', build_dir,
                  '-DCMAKE_SYSTEM_NAME=iOS', f'-DCMAKE_OSX_SYSROOT={sdk}',
                  f'-DCMAKE_OSX_ARCHITECTURES={arch}', '-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0',
                  '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY', '-DBUILD_SHARED_LIBS=OFF',
                  '-DANDROID_TOOLS_PATCH_VENDOR=OFF', f'-DNKAS_ADB_SOURCE={source}',
                  f'-DNKAS_BINDING_DIR={BINDING}', f'-DNKAS_GENERATED_PROTO_DIR={generated}')
        compile_target(build_dir, 'nkas_adb_link_check')
        archives[(sdk, arch)] = merge_and_check(build_dir)

    simulator = CACHE / 'libadb-simulator.a'
    run('xcrun', 'lipo', '-create', archives[('iphonesimulator', 'arm64')],
        archives[('iphonesimulator', 'x86_64')], '-output', simulator)
    device_framework = CACHE / 'device/AdbMobile.framework'
    simulator_framework = CACHE / 'simulator/AdbMobile.framework'
    framework(archives[('iphoneos', 'arm64')], device_framework, 'iphoneos')
    framework(simulator, simulator_framework, 'iphonesimulator')
    if OUTPUT.exists():
        if OUTPUT.resolve().parent != (ROOT / 'native/apple').resolve():
            raise SystemExit('Unexpected XCFramework output path')
        shutil.rmtree(OUTPUT)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    run('xcodebuild', '-create-xcframework', '-framework', device_framework,
        '-framework', simulator_framework, '-output', OUTPUT)
    (OUTPUT / 'SOURCE_REVISION').write_text(ADB_REVISION + '\n', encoding='utf-8')
    print(f'Built and link-checked {OUTPUT}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true', help='Check out pinned sources and apply patches without Xcode')
    build(parser.parse_args().prepare_only)
