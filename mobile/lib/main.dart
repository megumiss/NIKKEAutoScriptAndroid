import 'package:flutter/material.dart';
import 'package:nkas_mobile/app/app.dart';
import 'package:nkas_mobile/core/platform/native_licenses.dart';

void main() {
  registerNativeLicenses();
  runApp(const NkasMobileApp());
}
