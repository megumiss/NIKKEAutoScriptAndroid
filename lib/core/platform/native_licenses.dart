import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final group in ['go', 'ios', 'shared']) {
      final data =
          jsonDecode(await rootBundle.loadString('assets/licenses/$group.json'))
              as List<dynamic>;
      for (final entry in data.cast<Map<String, dynamic>>()) {
        final notices = (entry['licenses'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((notice) => '${notice['file']}\n\n${notice['text']}')
            .join('\n\n');
        yield LicenseEntryWithLineBreaks([
          '${entry['name']} ${entry['version']}',
        ], '${entry['source']}\n\n$notices');
      }
    }
  });
}
