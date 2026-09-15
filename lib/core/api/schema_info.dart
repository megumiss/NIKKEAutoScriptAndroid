class SchemaInfo {
  const SchemaInfo({required this.menus, required this.tasks});

  factory SchemaInfo.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    final tasks = <String, SchemaTask>{};
    if (rawTasks is Map<String, dynamic>) {
      for (final entry in rawTasks.entries) {
        if (entry.value is Map<String, dynamic>) {
          tasks[entry.key] = SchemaTask.fromJson(
            entry.key,
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }
    final menus = (json['menus'] is List ? json['menus'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(SchemaMenu.fromJson)
        .toList(growable: false);
    return SchemaInfo(menus: menus, tasks: Map.unmodifiable(tasks));
  }

  final List<SchemaMenu> menus;
  final Map<String, SchemaTask> tasks;
}

class SchemaMenu {
  const SchemaMenu({
    required this.key,
    required this.name,
    required this.icon,
    required this.tasks,
  });

  factory SchemaMenu.fromJson(Map<String, dynamic> json) => SchemaMenu(
    key: json['key']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    icon: json['icon']?.toString() ?? '',
    tasks: (json['tasks'] is List ? json['tasks'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(SchemaMenuTask.fromJson)
        .toList(growable: false),
  );

  final String key;
  final String name;

  /// webui 分组图标名（reicon 风格，如 `gift`、`calendar`），由后端 menu.json 下发
  final String icon;
  final List<SchemaMenuTask> tasks;
}

class SchemaMenuTask {
  const SchemaMenuTask({
    required this.key,
    required this.name,
    required this.help,
  });

  factory SchemaMenuTask.fromJson(Map<String, dynamic> json) => SchemaMenuTask(
    key: json['key']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    help: json['help']?.toString() ?? '',
  );

  final String key;
  final String name;
  final String help;
}

class SchemaTask {
  const SchemaTask({
    required this.key,
    required this.name,
    required this.help,
    required this.groups,
  });

  factory SchemaTask.fromJson(String key, Map<String, dynamic> json) =>
      SchemaTask(
        key: key,
        name: json['name']?.toString() ?? key,
        help: json['help']?.toString() ?? '',
        groups: (json['groups'] is List ? json['groups'] as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(SchemaGroup.fromJson)
            .toList(growable: false),
      );

  final String key;
  final String name;
  final String help;
  final List<SchemaGroup> groups;
}

class SchemaGroup {
  const SchemaGroup({
    required this.key,
    required this.name,
    required this.help,
    required this.fields,
  });

  factory SchemaGroup.fromJson(Map<String, dynamic> json) => SchemaGroup(
    key: json['key']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    help: json['help']?.toString() ?? '',
    fields: (json['fields'] is List ? json['fields'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(SchemaField.fromJson)
        .toList(growable: false),
  );

  final String key;
  final String name;
  final String help;
  final List<SchemaField> fields;
}

class SchemaField {
  const SchemaField({
    required this.key,
    required this.title,
    required this.help,
    required this.widget,
    required this.value,
    required this.readonly,
    required this.options,
  });

  factory SchemaField.fromJson(Map<String, dynamic> json) => SchemaField(
    key: json['key']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    help: json['help']?.toString() ?? '',
    widget: json['widget']?.toString() ?? 'input',
    value: json['value'],
    readonly: json['readonly'] == true,
    options: (json['options'] is List ? json['options'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(SchemaOption.fromJson)
        .toList(growable: false),
  );

  final String key;
  final String title;
  final String help;
  final String widget;
  final Object? value;
  final bool readonly;
  final List<SchemaOption> options;
}

class SchemaOption {
  const SchemaOption({required this.value, required this.label});

  factory SchemaOption.fromJson(Map<String, dynamic> json) => SchemaOption(
    value: json['value'],
    label: json['label']?.toString() ?? json['value']?.toString() ?? '',
  );

  final Object? value;
  final String label;
}
