import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ink_theme.dart';

/// 纸面点阵背景（与 Web body 的 radial-gradient 点阵一致）
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return ColoredBox(
      color: t.bg,
      child: CustomPaint(painter: _DotPainter(t.dot), child: child),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 22.0;
    for (double y = 11; y < size.height; y += step) {
      for (double x = 11; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color;
}

/// 2px 墨线 + 硬阴影 的卡片
class InkCard extends StatelessWidget {
  const InkCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 12),
    this.margin = const EdgeInsets.fromLTRB(14, 6, 21, 14),
    this.shadow = 4,
    this.radius = InkTokens.radius,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double shadow;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? t.paper,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.line, width: InkTokens.lineWidth),
        boxShadow: shadow > 0 ? t.hardShadow(shadow) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

enum InkVariant { normal, ink, accent, danger, ghost }

/// 按钮：2px 墨线、11px 圆角、小硬阴影，按下位移 (2,2)
class InkButton extends StatefulWidget {
  const InkButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = InkVariant.normal,
    this.busy = false,
    this.block = false,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final InkVariant variant;
  final bool busy;
  final bool block;
  final bool dense;

  @override
  State<InkButton> createState() => _InkButtonState();
}

class _InkButtonState extends State<InkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final disabled = widget.onPressed == null || widget.busy;
    Color bg, fg;
    switch (widget.variant) {
      case InkVariant.ink:
        bg = t.ink;
        fg = t.paper;
      case InkVariant.accent:
        bg = t.accent;
        fg = InkTokens.onColor;
      case InkVariant.danger:
        bg = t.danger;
        fg = t.dark ? InkTokens.onColor : Colors.white;
      case InkVariant.ghost:
        bg = Colors.transparent;
        fg = t.ink;
      case InkVariant.normal:
        bg = t.paper;
        fg = t.ink;
    }
    final ghost = widget.variant == InkVariant.ghost;
    final content = Row(
      mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 18, color: fg),
        if (widget.busy || widget.icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ],
    );
    final off = _down ? 2.0 : 0.0;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => setState(() => _down = true),
        onTapUp: disabled ? null : (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: Matrix4.translationValues(off, off, 0),
          constraints: BoxConstraints(minHeight: widget.dense ? 36 : 44),
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(InkTokens.radiusSm),
            border: Border.all(color: t.line, width: InkTokens.lineWidth),
            boxShadow: (ghost || _down) ? null : t.hardShadow(2),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// 44x44 图标按钮（12px 圆角 + 墨线 + 小硬阴影）
class InkIconButton extends StatelessWidget {
  const InkIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 44,
    this.plain = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final bool plain; // 无描边无阴影（卡片内小图标）

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final w = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: plain
            ? null
            : BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line, width: InkTokens.lineWidth),
                boxShadow: t.hardShadow(2),
              ),
        child: Icon(icon, size: 22, color: color ?? t.ink),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// 小胶囊标签（lime=文本 / sky=文件 …），深墨文字
class InkChip extends StatelessWidget {
  const InkChip(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.dark ? Colors.transparent : t.line, width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: InkTokens.onColor), const SizedBox(width: 5)],
        Text(label,
            style: const TextStyle(
                color: InkTokens.onColor, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1)),
      ]),
    );
  }
}

/// 分段胶囊（对应 Web .seg）：选中=墨底纸字，计数徽标=朱红
class InkSegment extends StatelessWidget {
  const InkSegment({
    super.key,
    required this.labels,
    required this.counts,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final List<String> counts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: i == index ? t.ink : t.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.line, width: InkTokens.lineWidth),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(labels[i],
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: i == index ? t.paper : t.ink)),
              if (counts[i].isNotEmpty) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: i == index ? t.accent : t.paper2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(counts[i],
                      textAlign: TextAlign.center,
                      style: t.monoStyle(11,
                          w: FontWeight.w700,
                          color: i == index ? InkTokens.onColor : t.muted)
                          .copyWith(height: 1)),
                ),
              ],
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// 品牌标：朱红圆角方块，旋转 -6°
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Transform.rotate(
      angle: -6 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: t.dark ? t.line : t.ink, width: 2),
          boxShadow: t.hardShadow(2),
        ),
        child: Icon(Icons.content_paste_rounded, size: size * 0.55, color: InkTokens.onColor),
      ),
    );
  }
}

/// 品牌：标 + 衬线字
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.big = false, this.suffix});
  final bool big;
  final String? suffix;
  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BrandMark(size: big ? 44 : 34),
      const SizedBox(width: 10),
      Text('剪贴板', style: t.serifStyle(big ? 28 : 21)),
      if (suffix != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: t.ink, borderRadius: BorderRadius.circular(6)),
          child: Text(suffix!, style: t.monoStyle(10.5, w: FontWeight.w700, color: t.paper).copyWith(height: 1)),
        ),
      ],
    ]);
  }
}

Future<T?> showInkSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}
