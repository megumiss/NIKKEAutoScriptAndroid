import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// NKAS Mobile 设计系统实现，规范见 mobile/DESIGN.md。
/// 核心语言：单一 accent、双主题对等、小半径紧凑节奏；
/// 列表/卡片用 1px 描边不加阴影，阴影只留给 Hero、主按钮和底部导航。
abstract final class NkasColors {
  // light
  static const lightBg = Color(0xFFF6F9FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF5F8FA);
  static const lightText = Color(0xFF172331);
  static const lightMuted = Color(0xFF70808E);
  static const lightTrack = Color(0xFFE1E9EF);
  // 与 WebUI 同源：主蓝负责交互，浅蓝负责 hover/选中和强调区域软底。
  static const lightAccent = Color(0xFF0099FF);
  static const lightAccentSoft = Color(0xFFE0F3FF);
  static const lightAccentForeground = Color(0xFFFFFFFF);
  static const lightAccentHighlight = Color(0xFF40B0FF);
  static const lightDanger = Color(0xFFC94D42);

  // dark
  static const darkBg = Color(0xFF17232B);
  static const darkSurface = Color(0xFF202E37);
  static const darkSurface2 = Color(0xFF293943);
  static const darkText = Color(0xFFE7F0F4);
  static const darkMuted = Color(0xFF9FB1BC);
  static const darkTrack = Color(0xFF344752);
  static const darkAccent = Color(0xFF40B0FF);
  static const darkAccentSoft = Color(0xFF173E55);
  static const darkAccentForeground = Color(0xFFFFFFFF);
  static const darkAccentHighlight = Color(0xFF40B0FF);
  static const darkDanger = Color(0xFFFF8E82);

  // NKAS 语义状态色
  static const lightSuccess = Color(0xFF159A72);
  static const lightWarning = Color(0xFFBD7A18);
  static const darkSuccess = Color(0xFF35C995);
  static const darkWarning = Color(0xFFFFC178);

  // 次级按钮（原型 .np-secondary）：半透明白底 + 细蓝灰边框
  static const lightSecondaryButtonBg = Color(0xADFFFFFF);
  static const lightSecondaryButtonBorder = Color(0x2E3D8DB7);
  static const lightSecondaryButtonText = Color(0xFF226483);
  static const darkSecondaryButtonBg = Color(0x14FFFFFF);
  static const darkSecondaryButtonBorder = Color(0x3D40B0FF);
  static const darkSecondaryButtonText = Color(0xFF9CC8E2);

  // 连接状态 pill（原型 .np-connection）
  static const lightConnectionBg = Color(0xFFE8F8F2);
  static const lightConnectionText = Color(0xFF168262);
  static const lightConnectionDot = Color(0xFF1BAD7C);
  static const darkConnectionBg = Color(0xFF173C30);
  static const darkConnectionText = Color(0xFF35C995);
  static const darkConnectionDot = Color(0xFF35C995);

  // 日志区（原型 .np-log-body / .np-log-line / .np-log-level）
  static const lightLogBodyBg = Color(0xFFF2F4F5);
  static const lightLogTime = Color(0xFF91A0AA);
  static const lightLogText = Color(0xFF536671);
  static const lightLogSource = Color(0xFF7168A5);
  static const lightLogInfoText = Color(0xFF0879BF);
  static const lightLogWarnBadgeBg = Color(0xFFFFE9BE);
  static const lightLogWarnLineBg = Color(0xFFFFF3D9);
  static const lightLogErrorBadgeBg = Color(0xFFFFD9D5);
  static const lightLogErrorLineBg = Color(0xFFFFEBE8);
  static const darkLogBodyBg = Color(0xFF1B2830);
  static const darkLogTime = Color(0xFF7E909C);
  static const darkLogText = Color(0xFF9FB1BC);
  static const darkLogSource = Color(0xFF9D92C7);
  static const darkLogInfoText = Color(0xFF40B0FF);
  static const darkLogWarnBadgeBg = Color(0x40BD7A18);
  static const darkLogWarnLineBg = Color(0x1FBD7A18);
  static const darkLogErrorBadgeBg = Color(0x40C94D42);
  static const darkLogErrorLineBg = Color(0x1FC94D42);

  // 头像与配置图标（原型 .np-avatar / .np-config-icon）
  static const lightAvatarBg = Color(0xFFE8F5FC);
  static const lightAvatarText = Color(0xFF187EAF);
  static const lightConfigIconBg = Color(0xFFEAF5FB);
  static const lightConfigIconText = Color(0xFF0879BF);
  static const darkAvatarBg = Color(0xFF173E55);
  static const darkAvatarText = Color(0xFF40B0FF);
  static const darkConfigIconBg = Color(0xFF173E55);
  static const darkConfigIconText = Color(0xFF40B0FF);

  // 活动日历 banner 分类底色（原型 .np-event-banner，无渐变）
  static const lightEventBannerDefault = Color(0xFFDFF3FF);
  static const lightEventBannerRaid = Color(0xFFE9E4FF);
  static const lightEventBannerArena = Color(0xFFFFF0CF);
  static const darkEventBannerDefault = Color(0xFF173E55);
  static const darkEventBannerRaid = Color(0xFF2B2840);
  static const darkEventBannerArena = Color(0xFF3B3320);

  // 底部导航（原型 .np-nav）：92% 白底 + 细边框；阴影色 rgba(38,66,84,...)
  static const lightNavBg = Color(0xEBFFFFFF);
  static const lightNavBorder = Color(0xE6CDDAE3);
  static const darkNavBg = Color(0xEB202E37);
  static const darkNavBorder = Color(0xE6344752);
  static const navShadow = Color(0xFF264254);

  // Hero 内部（原型 .np-eyebrow / .np-meta）
  static const lightHeroEyebrow = Color(0xFF39718F);
  static const lightHeroMeta = Color(0xFF507084);
  static const lightHeroMetaIcon = Color(0xFF4E91B8);
  static const darkHeroEyebrow = Color(0xFF8FAEC0);
  static const darkHeroMeta = Color(0xFF9FB1BC);
  static const darkHeroMetaIcon = Color(0xFF6FA8C9);

  // 主题无关的固定色：活动分类徽标底、画面预览
  static const eventBadgeBg = Color(0xC4172331);
  static const screenBg = Color(0xFF172B36);
  static const screenText = Color(0xFF9FB1BC);
}

/// colorScheme.custom 扩展 key
abstract final class NkasCustomKeys {
  static const accentSoft = 'accentSoft';
  static const accentHighlight = 'accentHighlight';
  static const success = 'success';
  static const warning = 'warning';
  static const secondaryButtonBg = 'secondaryButtonBg';
  static const secondaryButtonBorder = 'secondaryButtonBorder';
  static const secondaryButtonText = 'secondaryButtonText';
  static const connectionBg = 'connectionBg';
  static const connectionText = 'connectionText';
  static const connectionDot = 'connectionDot';
  static const logBodyBg = 'logBodyBg';
  static const logTime = 'logTime';
  static const logText = 'logText';
  static const logSource = 'logSource';
  static const logInfoText = 'logInfoText';
  static const logWarnBadgeBg = 'logWarnBadgeBg';
  static const logWarnLineBg = 'logWarnLineBg';
  static const logErrorBadgeBg = 'logErrorBadgeBg';
  static const logErrorLineBg = 'logErrorLineBg';
  static const avatarBg = 'avatarBg';
  static const avatarText = 'avatarText';
  static const configIconBg = 'configIconBg';
  static const configIconText = 'configIconText';
  static const eventBannerDefault = 'eventBannerDefault';
  static const eventBannerRaid = 'eventBannerRaid';
  static const eventBannerArena = 'eventBannerArena';
  static const navBg = 'navBg';
  static const navBorder = 'navBorder';
  static const heroEyebrow = 'heroEyebrow';
  static const heroMeta = 'heroMeta';
  static const heroMetaIcon = 'heroMetaIcon';
}

/// 语义色类型安全访问；组件一律经这里取色，禁止裸写 hex
extension NkasColorSchemeX on ShadColorScheme {
  Color get accentSoft => custom[NkasCustomKeys.accentSoft]!;
  Color get accentHighlight => custom[NkasCustomKeys.accentHighlight]!;
  Color get success => custom[NkasCustomKeys.success]!;
  Color get warning => custom[NkasCustomKeys.warning]!;
  Color get secondaryButtonBg => custom[NkasCustomKeys.secondaryButtonBg]!;
  Color get secondaryButtonBorder =>
      custom[NkasCustomKeys.secondaryButtonBorder]!;
  Color get secondaryButtonText => custom[NkasCustomKeys.secondaryButtonText]!;
  Color get connectionBg => custom[NkasCustomKeys.connectionBg]!;
  Color get connectionText => custom[NkasCustomKeys.connectionText]!;
  Color get connectionDot => custom[NkasCustomKeys.connectionDot]!;
  Color get logBodyBg => custom[NkasCustomKeys.logBodyBg]!;
  Color get logTime => custom[NkasCustomKeys.logTime]!;
  Color get logText => custom[NkasCustomKeys.logText]!;
  Color get logSource => custom[NkasCustomKeys.logSource]!;
  Color get logInfoText => custom[NkasCustomKeys.logInfoText]!;
  Color get logWarnBadgeBg => custom[NkasCustomKeys.logWarnBadgeBg]!;
  Color get logWarnLineBg => custom[NkasCustomKeys.logWarnLineBg]!;
  Color get logErrorBadgeBg => custom[NkasCustomKeys.logErrorBadgeBg]!;
  Color get logErrorLineBg => custom[NkasCustomKeys.logErrorLineBg]!;
  Color get avatarBg => custom[NkasCustomKeys.avatarBg]!;
  Color get avatarText => custom[NkasCustomKeys.avatarText]!;
  Color get configIconBg => custom[NkasCustomKeys.configIconBg]!;
  Color get configIconText => custom[NkasCustomKeys.configIconText]!;
  Color get eventBannerDefault => custom[NkasCustomKeys.eventBannerDefault]!;
  Color get eventBannerRaid => custom[NkasCustomKeys.eventBannerRaid]!;
  Color get eventBannerArena => custom[NkasCustomKeys.eventBannerArena]!;
  Color get navBg => custom[NkasCustomKeys.navBg]!;
  Color get navBorder => custom[NkasCustomKeys.navBorder]!;
  Color get heroEyebrow => custom[NkasCustomKeys.heroEyebrow]!;
  Color get heroMeta => custom[NkasCustomKeys.heroMeta]!;
  Color get heroMetaIcon => custom[NkasCustomKeys.heroMetaIcon]!;
}

/// 操作按钮的视觉高度与触控范围分别设置。
abstract final class NkasActionStyle {
  static const minTapSize = 48.0;
  static const secondaryHeight = 38.0;
  static const compactHeight = 34.0;
  static const chipHeight = 30.0;

  static const compactButton = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(minTapSize, compactHeight)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

/// 文本、数字、日期和选择控件共用的尺寸与边界。
abstract final class NkasInputStyle {
  static const radius = BorderRadius.all(Radius.circular(10));
  static const minHeight = 48.0;
  static const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

  static InputDecorationThemeData decoration(ShadColorScheme scheme) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecorationThemeData(
      filled: true,
      fillColor: scheme.input,
      isDense: true,
      contentPadding: padding,
      constraints: const BoxConstraints(minHeight: minHeight),
      border: border(scheme.border),
      enabledBorder: border(scheme.border),
      focusedBorder: border(scheme.ring, 1.5),
      disabledBorder: border(scheme.border.withValues(alpha: .6)),
      errorBorder: border(scheme.destructive),
      focusedErrorBorder: border(scheme.destructive, 1.5),
      hintStyle: TextStyle(
        color: scheme.mutedForeground,
        fontSize: 13,
        height: 1.4,
      ),
      helperStyle: TextStyle(
        color: scheme.mutedForeground,
        fontSize: 12,
        height: 1.5,
      ),
      errorStyle: TextStyle(
        color: scheme.destructive,
        fontSize: 12,
        height: 1.5,
      ),
      helperMaxLines: 5,
      errorMaxLines: 5,
      prefixIconColor: scheme.mutedForeground,
      suffixIconColor: scheme.mutedForeground,
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}

/// Material 提供输入法、表单校验和原生选择器，视觉仍使用 NKAS Tokens。
ThemeData nkasMaterialTheme(BuildContext context, ThemeData base) {
  final scheme = base.brightness == Brightness.dark
      ? nkasColorSchemeDark
      : nkasColorSchemeLight;
  const controlShape = RoundedRectangleBorder(
    borderRadius: NkasInputStyle.radius,
  );
  const dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(18)),
  );
  final actionStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    shape: const WidgetStatePropertyAll(controlShape),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
  return base.copyWith(
    inputDecorationTheme: NkasInputStyle.decoration(scheme),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.card,
      surfaceTintColor: Colors.transparent,
      shape: dialogShape,
      titleTextStyle: _t(
        size: 16,
        height: 22,
        weight: FontWeight.w700,
        color: scheme.foreground,
      ),
      contentTextStyle: _t(
        size: 13,
        height: 19,
        weight: FontWeight.w400,
        color: scheme.foreground,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.popover,
      surfaceTintColor: Colors.transparent,
      shape: controlShape.copyWith(side: BorderSide(color: scheme.border)),
      textStyle: TextStyle(color: scheme.foreground, fontSize: 13, height: 1.5),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: scheme.mutedForeground, width: 1.5),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    textButtonTheme: TextButtonThemeData(style: actionStyle),
    filledButtonTheme: FilledButtonThemeData(style: actionStyle),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: scheme.card,
      surfaceTintColor: Colors.transparent,
      shape: dialogShape,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: scheme.card,
      shape: dialogShape,
      inputDecorationTheme: NkasInputStyle.decoration(scheme),
    ),
  );
}

/// 阴影只用于浮起元素：Hero（brand）、主按钮（accent）、底部导航（raised）。
/// 列表/卡片无阴影，只留 1px 描边。dark 主题各档透明度减半。
abstract final class NkasShadows {
  /// 列表/卡片：无阴影（原型 .np-list/.np-log-card/.np-setting-surface 均只有描边）
  static List<BoxShadow> card(Brightness b) => const [];

  /// 底部导航：0 8px 22px rgba(38,66,84,.12) + 0 2px 5px rgba(38,66,84,.06)
  static List<BoxShadow> raised(Brightness b) {
    final k = b == Brightness.dark ? .5 : 1.0;
    return [
      BoxShadow(
        color: NkasColors.navShadow.withValues(alpha: .12 * k),
        blurRadius: 22,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: NkasColors.navShadow.withValues(alpha: .06 * k),
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// 主按钮：0 5px 12px rgba(0,153,255,.22)
  static List<BoxShadow> accent(Color accentColor, Brightness b) => [
    BoxShadow(
      color: accentColor.withValues(alpha: b == Brightness.dark ? .11 : .22),
      blurRadius: 12,
      offset: const Offset(0, 5),
    ),
  ];

  /// Hero：0 10px 24px rgba(0,153,255,.10)
  static List<BoxShadow> brand(Color accentColor, Brightness b) => [
    BoxShadow(
      color: accentColor.withValues(alpha: b == Brightness.dark ? .05 : .10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

const nkasColorSchemeLight = ShadColorScheme(
  background: NkasColors.lightBg,
  foreground: NkasColors.lightText,
  card: NkasColors.lightSurface,
  cardForeground: NkasColors.lightText,
  popover: NkasColors.lightSurface,
  popoverForeground: NkasColors.lightText,
  primary: NkasColors.lightAccent,
  primaryForeground: NkasColors.lightAccentForeground,
  secondary: NkasColors.lightSurface2,
  secondaryForeground: NkasColors.lightText,
  muted: NkasColors.lightSurface2,
  mutedForeground: NkasColors.lightMuted,
  accent: NkasColors.lightSurface2,
  accentForeground: NkasColors.lightText,
  destructive: NkasColors.lightDanger,
  destructiveForeground: Color(0xFFFFFFFF),
  border: NkasColors.lightTrack,
  input: NkasColors.lightSurface2,
  ring: NkasColors.lightAccent,
  selection: Color(0x420099FF),
  custom: {
    NkasCustomKeys.accentSoft: NkasColors.lightAccentSoft,
    NkasCustomKeys.accentHighlight: NkasColors.lightAccentHighlight,
    NkasCustomKeys.success: NkasColors.lightSuccess,
    NkasCustomKeys.warning: NkasColors.lightWarning,
    NkasCustomKeys.secondaryButtonBg: NkasColors.lightSecondaryButtonBg,
    NkasCustomKeys.secondaryButtonBorder: NkasColors.lightSecondaryButtonBorder,
    NkasCustomKeys.secondaryButtonText: NkasColors.lightSecondaryButtonText,
    NkasCustomKeys.connectionBg: NkasColors.lightConnectionBg,
    NkasCustomKeys.connectionText: NkasColors.lightConnectionText,
    NkasCustomKeys.connectionDot: NkasColors.lightConnectionDot,
    NkasCustomKeys.logBodyBg: NkasColors.lightLogBodyBg,
    NkasCustomKeys.logTime: NkasColors.lightLogTime,
    NkasCustomKeys.logText: NkasColors.lightLogText,
    NkasCustomKeys.logSource: NkasColors.lightLogSource,
    NkasCustomKeys.logInfoText: NkasColors.lightLogInfoText,
    NkasCustomKeys.logWarnBadgeBg: NkasColors.lightLogWarnBadgeBg,
    NkasCustomKeys.logWarnLineBg: NkasColors.lightLogWarnLineBg,
    NkasCustomKeys.logErrorBadgeBg: NkasColors.lightLogErrorBadgeBg,
    NkasCustomKeys.logErrorLineBg: NkasColors.lightLogErrorLineBg,
    NkasCustomKeys.avatarBg: NkasColors.lightAvatarBg,
    NkasCustomKeys.avatarText: NkasColors.lightAvatarText,
    NkasCustomKeys.configIconBg: NkasColors.lightConfigIconBg,
    NkasCustomKeys.configIconText: NkasColors.lightConfigIconText,
    NkasCustomKeys.eventBannerDefault: NkasColors.lightEventBannerDefault,
    NkasCustomKeys.eventBannerRaid: NkasColors.lightEventBannerRaid,
    NkasCustomKeys.eventBannerArena: NkasColors.lightEventBannerArena,
    NkasCustomKeys.navBg: NkasColors.lightNavBg,
    NkasCustomKeys.navBorder: NkasColors.lightNavBorder,
    NkasCustomKeys.heroEyebrow: NkasColors.lightHeroEyebrow,
    NkasCustomKeys.heroMeta: NkasColors.lightHeroMeta,
    NkasCustomKeys.heroMetaIcon: NkasColors.lightHeroMetaIcon,
  },
);

const nkasColorSchemeDark = ShadColorScheme(
  background: NkasColors.darkBg,
  foreground: NkasColors.darkText,
  card: NkasColors.darkSurface,
  cardForeground: NkasColors.darkText,
  popover: NkasColors.darkSurface,
  popoverForeground: NkasColors.darkText,
  primary: NkasColors.darkAccent,
  primaryForeground: NkasColors.darkAccentForeground,
  secondary: NkasColors.darkSurface2,
  secondaryForeground: NkasColors.darkText,
  muted: NkasColors.darkSurface2,
  mutedForeground: NkasColors.darkMuted,
  accent: NkasColors.darkSurface2,
  accentForeground: NkasColors.darkText,
  destructive: NkasColors.darkDanger,
  destructiveForeground: Color(0xFFFFFFFF),
  border: NkasColors.darkTrack,
  input: NkasColors.darkSurface2,
  ring: NkasColors.darkAccent,
  selection: Color(0x520099FF),
  custom: {
    NkasCustomKeys.accentSoft: NkasColors.darkAccentSoft,
    NkasCustomKeys.accentHighlight: NkasColors.darkAccentHighlight,
    NkasCustomKeys.success: NkasColors.darkSuccess,
    NkasCustomKeys.warning: NkasColors.darkWarning,
    NkasCustomKeys.secondaryButtonBg: NkasColors.darkSecondaryButtonBg,
    NkasCustomKeys.secondaryButtonBorder: NkasColors.darkSecondaryButtonBorder,
    NkasCustomKeys.secondaryButtonText: NkasColors.darkSecondaryButtonText,
    NkasCustomKeys.connectionBg: NkasColors.darkConnectionBg,
    NkasCustomKeys.connectionText: NkasColors.darkConnectionText,
    NkasCustomKeys.connectionDot: NkasColors.darkConnectionDot,
    NkasCustomKeys.logBodyBg: NkasColors.darkLogBodyBg,
    NkasCustomKeys.logTime: NkasColors.darkLogTime,
    NkasCustomKeys.logText: NkasColors.darkLogText,
    NkasCustomKeys.logSource: NkasColors.darkLogSource,
    NkasCustomKeys.logInfoText: NkasColors.darkLogInfoText,
    NkasCustomKeys.logWarnBadgeBg: NkasColors.darkLogWarnBadgeBg,
    NkasCustomKeys.logWarnLineBg: NkasColors.darkLogWarnLineBg,
    NkasCustomKeys.logErrorBadgeBg: NkasColors.darkLogErrorBadgeBg,
    NkasCustomKeys.logErrorLineBg: NkasColors.darkLogErrorLineBg,
    NkasCustomKeys.avatarBg: NkasColors.darkAvatarBg,
    NkasCustomKeys.avatarText: NkasColors.darkAvatarText,
    NkasCustomKeys.configIconBg: NkasColors.darkConfigIconBg,
    NkasCustomKeys.configIconText: NkasColors.darkConfigIconText,
    NkasCustomKeys.eventBannerDefault: NkasColors.darkEventBannerDefault,
    NkasCustomKeys.eventBannerRaid: NkasColors.darkEventBannerRaid,
    NkasCustomKeys.eventBannerArena: NkasColors.darkEventBannerArena,
    NkasCustomKeys.navBg: NkasColors.darkNavBg,
    NkasCustomKeys.navBorder: NkasColors.darkNavBorder,
    NkasCustomKeys.heroEyebrow: NkasColors.darkHeroEyebrow,
    NkasCustomKeys.heroMeta: NkasColors.darkHeroMeta,
    NkasCustomKeys.heroMetaIcon: NkasColors.darkHeroMetaIcon,
  },
);

/// 全局系统字体栈：拉丁/中文均随平台默认（Android Roboto+Noto CJK、iOS SF+苹方、
/// Windows 雅黑）。不打包 UI 字体——界面以中文为主，系统字体在各平台观感最一致；
/// 中文界面统一使用平台系统字体，具体取舍见 DESIGN.md。
/// 日志时间戳等宽场景用 shadcn_ui 自带的 GeistMono（kDefaultFontFamilyMono）。
/// canMerge: false 完全接管：merge 语义下 null fontFamily 会保留默认主题的 Geist。
/// 注意：shadcn_ui 的 ShadTextTheme 只携带排版不带颜色（颜色由组件各自 copyWith），
/// 直接在 Text(style:) 里用会回落到前景色；所以这里把颜色烘进样式。
TextStyle _t({
  required double size,
  required double height,
  required FontWeight weight,
  required Color color,
  double letterSpacing = 0,
}) => TextStyle(
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  color: color,
);

ShadTextTheme _nkasTextTheme(ShadColorScheme scheme) {
  final ink = scheme.foreground;
  final muted = scheme.mutedForeground;
  return ShadTextTheme.custom(
    canMerge: false,
    // 仅占位：所有 style 的 fontFamily 均为 null = 系统默认字体
    family: 'NotoSansSC',
    h1Large: _t(size: 48, height: 48, weight: FontWeight.w800, color: ink),
    h1: _t(size: 36, height: 40, weight: FontWeight.w800, color: ink),
    // 页面标题 24/30 w700
    h2: _t(size: 24, height: 30, weight: FontWeight.w700, color: ink),
    // 区块标题 16/21 w700
    h3: _t(size: 16, height: 21, weight: FontWeight.w700, color: ink),
    h4: _t(size: 14, height: 18, weight: FontWeight.w700, color: ink),
    // Body 13/19
    p: _t(size: 13, height: 19, weight: FontWeight.w400, color: ink),
    blockquote: _t(size: 13, height: 19, weight: FontWeight.w400, color: ink),
    table: _t(size: 13, height: 19, weight: FontWeight.w400, color: ink),
    list: _t(size: 13, height: 19, weight: FontWeight.w400, color: ink),
    lead: _t(size: 20, height: 28, weight: FontWeight.w400, color: ink),
    large: _t(size: 18, height: 24, weight: FontWeight.w600, color: ink),
    // Caption 12/15
    small: _t(size: 12, height: 15, weight: FontWeight.w400, color: muted),
    muted: _t(size: 12, height: 15, weight: FontWeight.w400, color: muted),
    custom: {
      // Field label 10.5/13 w500 +0.6 大写
      'fieldLabel': _t(
        size: 10.5,
        height: 13,
        weight: FontWeight.w500,
        letterSpacing: .6,
        color: muted,
      ),
      // Stat value 24/28 w600
      'statValue': _t(
        size: 24,
        height: 28,
        weight: FontWeight.w600,
        color: ink,
      ),
      // Hero 状态标题 21/25 w700（原型 .np-state）
      'heroState': _t(
        size: 21,
        height: 25,
        weight: FontWeight.w700,
        color: ink,
      ),
    },
  );
}

/// 全局圆角 15px（标准卡片档；chips/内层元素 12，hero/浮层 18，导航 pill）。
/// 卡片用 1px 描边替代阴影；focus 态用 accent 描边（可访问性保留）。
ShadThemeData nkasThemeData(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? nkasColorSchemeDark : nkasColorSchemeLight;
  final r16 = const BorderRadius.all(Radius.circular(16));

  ShadBorder plain() => ShadBorder(radius: r16);
  ShadBorder focused() => ShadBorder(
    radius: r16,
    top: ShadBorderSide(color: scheme.ring, width: 1.6),
    right: ShadBorderSide(color: scheme.ring, width: 1.6),
    bottom: ShadBorderSide(color: scheme.ring, width: 1.6),
    left: ShadBorderSide(color: scheme.ring, width: 1.6),
  );

  return ShadThemeData(
    brightness: brightness,
    colorScheme: scheme,
    radius: const BorderRadius.all(Radius.circular(15)),
    disableSecondaryBorder: true,
    textTheme: _nkasTextTheme(scheme),
    primaryButtonTheme: ShadButtonTheme(
      decoration: ShadDecoration(
        border: plain(),
        focusedBorder: focused(),
        shadows: NkasShadows.accent(scheme.primary, brightness),
      ),
    ),
    destructiveButtonTheme: ShadButtonTheme(
      decoration: ShadDecoration(
        border: plain(),
        focusedBorder: focused(),
        shadows: NkasShadows.accent(scheme.destructive, brightness),
      ),
    ),
    // outline 语义改为「次级填充按钮」：surface2 底，无描边
    outlineButtonTheme: ShadButtonTheme(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.secondaryForeground,
      hoverBackgroundColor: scheme.secondary,
      decoration: ShadDecoration(border: plain(), focusedBorder: focused()),
    ),
    secondaryButtonTheme: ShadButtonTheme(
      decoration: ShadDecoration(border: plain(), focusedBorder: focused()),
    ),
    ghostButtonTheme: ShadButtonTheme(
      decoration: ShadDecoration(border: plain(), focusedBorder: focused()),
    ),
    // Alert / Card：surface + 描边，无阴影
    primaryAlertTheme: ShadAlertTheme(
      decoration: ShadDecoration(
        color: scheme.card,
        border: ShadBorder.all(
          color: scheme.border,
          radius: const BorderRadius.all(Radius.circular(15)),
          padding: const EdgeInsets.all(16),
        ),
      ),
    ),
    destructiveAlertTheme: ShadAlertTheme(
      decoration: ShadDecoration(
        color: scheme.card,
        border: ShadBorder.all(
          color: scheme.border,
          radius: const BorderRadius.all(Radius.circular(15)),
          padding: const EdgeInsets.all(16),
        ),
      ),
    ),
    cardTheme: ShadCardTheme(
      backgroundColor: scheme.card,
      radius: const BorderRadius.all(Radius.circular(15)),
      border: ShadBorder.all(
        color: scheme.border,
        radius: const BorderRadius.all(Radius.circular(15)),
      ),
    ),
  );
}
