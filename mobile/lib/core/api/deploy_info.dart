class DeployInfo {
  const DeployInfo({required this.groups});

  factory DeployInfo.fromJson(Map<String, dynamic> json) => DeployInfo(
    groups: (json['groups'] is List ? json['groups'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(DeployGroup.fromJson)
        .toList(growable: false),
  );

  final List<DeployGroup> groups;
}

class DeployGroup {
  const DeployGroup({
    required this.key,
    required this.name,
    required this.fields,
  });

  factory DeployGroup.fromJson(Map<String, dynamic> json) => DeployGroup(
    key: json['key']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    fields: (json['fields'] is List ? json['fields'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(DeployField.fromJson)
        .toList(growable: false),
  );

  final String key;
  final String name;
  final List<DeployField> fields;
}

class DeployField {
  const DeployField({
    required this.key,
    required this.title,
    required this.help,
    required this.hints,
    required this.widget,
    required this.value,
    required this.defaultValue,
    required this.options,
    required this.wide,
  });

  factory DeployField.fromJson(Map<String, dynamic> json) => DeployField(
    key: json['key']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    help: json['help']?.toString() ?? '',
    hints: (json['hints'] is List ? json['hints'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(DeployHint.fromJson)
        .toList(growable: false),
    widget: json['widget']?.toString() ?? 'text',
    value: json['value'],
    defaultValue: json['default'],
    options: (json['options'] is List ? json['options'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(DeployOption.fromJson)
        .toList(growable: false),
    wide: json['wide'] == true,
  );

  final String key;
  final String title;
  final String help;
  final List<DeployHint> hints;
  final String widget;
  final Object? value;
  final Object? defaultValue;
  final List<DeployOption> options;
  final bool wide;

  List<String> get selectedValues {
    final raw = value;
    if (raw is List) return raw.map((item) => item.toString()).toList();
    return const [];
  }

  DeployField copyWithValue(Object? next) => DeployField(
    key: key,
    title: title,
    help: help,
    hints: hints,
    widget: widget,
    value: next,
    defaultValue: defaultValue,
    options: options,
    wide: wide,
  );
}

class DeployHint {
  const DeployHint({required this.tag, required this.text});

  factory DeployHint.fromJson(Map<String, dynamic> json) => DeployHint(
    tag: json['tag']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
  );

  final String tag;
  final String text;
}

class DeployOption {
  const DeployOption({required this.value, required this.label});

  factory DeployOption.fromJson(Map<String, dynamic> json) => DeployOption(
    value: json['value']?.toString() ?? '',
    label: json['label']?.toString() ?? json['value']?.toString() ?? '',
  );

  final String value;
  final String label;
}
