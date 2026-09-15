import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/api/update_info.dart';

UpdateInfo info({
  Object? state,
  String? localSha,
  List<List<Object?>>? history,
}) {
  return UpdateInfo.fromJson({
    'state': state,
    'error': null,
    'local': localSha == null
        ? null
        : [localSha, 'tester', '2026-09-10 10:00:00 +0800', 'local'],
    'upstream': null,
    'history': history ?? const [],
  });
}

void main() {
  test('backend state 1 means an update is available', () {
    final value = info(state: 1, localSha: 'abc123');
    expect(value.updateAvailable, isTrue);
    expect(value.stateLabel, '有新版本');
  });

  test('stale state with local commit behind in history means an update', () {
    // 后端未检查（state 0），但提交记录里本地提交不是最新一条
    final value = info(
      state: 0,
      localSha: 'def456',
      history: [
        ['abc123', 'tester', '2026-09-10', '修复调度重启问题'],
        ['def456', 'tester', '2026-09-08', '新增活动日历入口'],
      ],
    );
    expect(value.updateAvailable, isTrue);
    expect(value.stateLabel, '有新版本');
  });

  test('local commit at the top of history is up to date', () {
    final value = info(
      state: 0,
      localSha: 'abc123',
      history: [
        ['abc123', 'tester', '2026-09-10', '修复调度重启问题'],
        ['def456', 'tester', '2026-09-08', '新增活动日历入口'],
      ],
    );
    expect(value.updateAvailable, isFalse);
    expect(value.stateLabel, '已是最新');
  });

  test('local commit missing from history falls back to backend state', () {
    final value = info(
      state: 0,
      localSha: 'fff000',
      history: [
        ['abc123', 'tester', '2026-09-10', '修复调度重启问题'],
      ],
    );
    expect(value.updateAvailable, isFalse);
    expect(value.stateLabel, '已是最新');
  });

  test('failed state keeps the failure label', () {
    final value = info(
      state: 'failed',
      localSha: 'def456',
      history: [
        ['abc123', 'tester', '2026-09-10', '修复调度重启问题'],
        ['def456', 'tester', '2026-09-08', '新增活动日历入口'],
      ],
    );
    expect(value.updateAvailable, isTrue);
    expect(value.stateLabel, '更新失败');
  });
}
