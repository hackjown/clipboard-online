import 'package:flutter/material.dart';

/// 「纸与墨」软粗野主义设计令牌 —— 与 Web 端 app.css 一致
@immutable
class InkTokens extends ThemeExtension<InkTokens> {
  const InkTokens({
    required this.bg,
    required this.paper,
    required this.paper2,
    required this.ink,
    required this.muted,
    required this.dot,
    required this.accent,
    required this.lime,
    required this.sky,
    required this.sun,
    required this.pink,
    required this.danger,
    required this.ok,
    required this.line,
    required this.shadow,
    required this.dark,
  });

  final Color bg, paper, paper2, ink, muted, dot;
  final Color accent, lime, sky, sun, pink, danger, ok;
  final Color line; // 描边色
  final Color shadow; // 硬阴影色
  final bool dark;

  static const lineWidth = 2.0;
  static const radius = 16.0;
  static const radiusSm = 11.0;

  static const light = InkTokens(
    bg: Color(0xFFECE6D9),
    paper: Color(0xFFFAF6EC),
    paper2: Color(0xFFF3EDDF),
    ink: Color(0xFF17140F),
    muted: Color(0xFF6B6458),
    dot: Color(0x2117140F),
    accent: Color(0xFFFF4F2B),
    lime: Color(0xFFCDF26B),
    sky: Color(0xFFA9CDFF),
    sun: Color(0xFFFFD84A),
    pink: Color(0xFFFFB7C9),
    danger: Color(0xFFD4281A),
    ok: Color(0xFF1F8A4C),
    line: Color(0xFF17140F),
    shadow: Color(0xFF17140F),
    dark: false,
  );

  static const darkTokens = InkTokens(
    bg: Color(0xFF100F0D),
    paper: Color(0xFF1B1916),
    paper2: Color(0xFF24211D),
    ink: Color(0xFFF4EEDF),
    muted: Color(0xFFA39B8B),
    dot: Color(0x17F4EEDF),
    accent: Color(0xFFFF6A47),
    lime: Color(0xFFC4EC63),
    sky: Color(0xFF8FBCF5),
    sun: Color(0xFFF5CF3D),
    pink: Color(0xFFF6A6BB),
    danger: Color(0xFFFF6B5C),
    ok: Color(0xFF5FD68C),
    line: Color(0xDBF4EEDF),
    shadow: Color(0x33F4EEDF),
    dark: true,
  );

  /// 彩色底（accent/lime/sky/sun）上的文字始终用深墨色
  static const onColor = Color(0xFF17140F);

  static const serif = <String>[
    'Source Han Serif SC',
    'Noto Serif CJK SC',
    'Songti SC',
    'STSong',
    'Noto Serif SC',
    'SimSun',
    'Iowan Old Style',
    'Georgia',
    'serif',
  ];
  static const mono = <String>[
    'SF Mono',
    'Menlo',
    'JetBrains Mono',
    'Roboto Mono',
    'Consolas',
    'Droid Sans Mono',
    'Noto Sans Mono CJK SC',
    'monospace',
  ];

  TextStyle serifStyle(double size, {FontWeight w = FontWeight.w900, Color? color}) => TextStyle(
        fontFamily: 'Songti SC',
        fontFamilyFallback: serif,
        fontSize: size,
        fontWeight: w,
        height: 1.2,
        letterSpacing: -0.2,
        color: color ?? ink,
      );

  TextStyle monoStyle(double size, {FontWeight w = FontWeight.w500, Color? color}) => TextStyle(
        fontFamily: 'Menlo',
        fontFamilyFallback: mono,
        fontSize: size,
        fontWeight: w,
        height: 1.6,
        color: color ?? ink,
      );

  List<BoxShadow> hardShadow([double d = 4]) =>
      [BoxShadow(color: shadow, offset: Offset(d, d), blurRadius: 0)];

  @override
  InkTokens copyWith() => this;

  @override
  InkTokens lerp(ThemeExtension<InkTokens>? other, double t) => t < 0.5 ? this : (other as InkTokens? ?? this);
}

extension InkContext on BuildContext {
  InkTokens get ink => Theme.of(this).extension<InkTokens>() ?? InkTokens.light;
}

ThemeData buildInkTheme(Brightness b) {
  final t = b == Brightness.dark ? InkTokens.darkTokens : InkTokens.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: t.ink,
    onPrimary: t.paper,
    secondary: t.accent,
    onSecondary: InkTokens.onColor,
    tertiary: t.lime,
    onTertiary: InkTokens.onColor,
    error: t.danger,
    onError: b == Brightness.dark ? InkTokens.onColor : Colors.white,
    surface: t.paper,
    onSurface: t.ink,
    surfaceContainerHighest: t.paper2,
    outline: t.line,
    outlineVariant: t.line.withValues(alpha: 0.4),
    primaryContainer: t.lime,
    onPrimaryContainer: InkTokens.onColor,
    secondaryContainer: t.sky,
    onSecondaryContainer: InkTokens.onColor,
    tertiaryContainer: t.sun,
    onTertiaryContainer: InkTokens.onColor,
    errorContainer: t.pink,
    onErrorContainer: InkTokens.onColor,
  );
  OutlineInputBorder border([Color? c, double w = 2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c ?? t.line, width: w),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.paper,
    dividerColor: t.line.withValues(alpha: 0.25),
    extensions: [t],
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink).copyWith(
          headlineLarge: t.serifStyle(34),
          headlineMedium: t.serifStyle(28),
          titleLarge: t.serifStyle(24),
          titleMedium: const TextStyle(fontWeight: FontWeight.w700),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.paper,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: t.line, width: InkTokens.lineWidth)),
      titleTextStyle: t.serifStyle(21),
      iconTheme: IconThemeData(color: t.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.paper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(t.accent, 2.5),
      errorBorder: border(t.danger),
      labelStyle: TextStyle(color: t.muted),
      hintStyle: TextStyle(color: t.muted),
      helperStyle: t.monoStyle(11.5, color: t.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: TextStyle(color: t.paper, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(InkTokens.radiusSm)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InkTokens.radius),
        side: BorderSide(color: t.line, width: InkTokens.lineWidth),
      ),
      titleTextStyle: t.serifStyle(22),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.ink.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: t.line, width: InkTokens.lineWidth),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: t.ink, textColor: t.ink),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.paper,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkTokens.radiusSm),
          side: BorderSide(color: t.line, width: InkTokens.lineWidth),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    chipTheme: ChipThemeData(
      backgroundColor: t.paper2,
      side: BorderSide(color: t.line, width: 1.5),
      labelStyle: TextStyle(color: t.ink, fontWeight: FontWeight.w700, fontSize: 12),
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: t.line, width: 2)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.ink : t.paper),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.paper : t.ink),
      ),
    ),
  );
}
