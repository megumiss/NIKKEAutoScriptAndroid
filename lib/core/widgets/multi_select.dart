import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/theme.dart';

Future<Set<String>?> showNkasMultiSelect({
  required BuildContext context,
  required String title,
  required List<FieldSelectOption> options,
  required Set<String> selected,
}) {
  final values = {...selected};
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = ShadTheme.of(context);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: theme.textTheme.h3),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final option in options)
                            CheckboxListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: NkasInputStyle.radius,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                option.label,
                                style: theme.textTheme.p,
                              ),
                              selected: values.contains(option.value),
                              selectedTileColor: theme.colorScheme.accentSoft,
                              value: values.contains(option.value),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  values.add(option.value);
                                } else {
                                  values.remove(option.value);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    icon: LucideIcons.check,
                    label: '完成',
                    onPressed: () => Navigator.pop(context, values),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
