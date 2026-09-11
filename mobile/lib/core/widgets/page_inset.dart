import 'package:flutter/material.dart';

/// 原型媒体查询：屏宽 <=360 时主内容左右 padding 收紧为 14，否则 18
double nkasPageInset(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 360 ? 14 : 18;
