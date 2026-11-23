import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/api.dart';
import '../theme/ink_theme.dart';
import 'ink.dart';

/// Office 文档结构化预览：调用服务端 `GET /api/items/<uuid>/office`。
/// 支持 Word (.docx)、Excel (.xlsx / .xlsm / .xls)、PowerPoint (.pptx)。
class OfficeView extends StatefulWidget {
  const OfficeView({super.key, required this.api, required this.item});
  final ClipApi api;
  final ClipItem item;

  @override
  State<OfficeView> createState() => _OfficeViewState();
}

class _OfficeViewState extends State<OfficeView> {
  OfficePreview? _data;
  String? _err;
  int _sheetIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.officePreview(widget.item.uuid);
      if (!mounted) return;
      setState(() {
        _data = d;
        _sheetIdx = 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.status == 404
          ? '服务器暂不支持 Office 在线预览，请更新服务端镜像或用下方「分享 / 保存」打开。'
          : e.message;
      setState(() => _err = msg);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  static String _colName(int idx) {
    var s = '';
    var n = idx;
    while (n >= 0) {
      s = String.fromCharCode(65 + (n % 26)) + s;
      n = (n ~/ 26) - 1;
    }
    return s;
  }

  static Uint8List? _decodeDataUri(String? src) {
    if (src == null || !src.startsWith('data:image/')) return null;
    final i = src.indexOf('base64,');
    if (i < 0) return null;
    try {
      return base64Decode(src.substring(i + 7));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    if (_err != null) {
      return Center(
        child: InkCard(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.article_outlined, size: 56, color: t.ink),
            const SizedBox(height: 10),
            Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: t.danger)),
          ]),
        ),
      );
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    return switch (d.type) {
      'docx' => _buildDocx(context, d),
      'xlsx' || 'xls' || 'csv' => _buildExcel(context, d),
      'pptx' => _buildPptx(context, d),
      _ => Center(child: Text('不支持的 Office 预览类型：${d.type}', style: TextStyle(color: t.danger))),
    };
  }

  Widget _summaryBar(BuildContext context, String text) {
    final t = context.ink;
    return Container(
      width: double.infinity,
      color: t.paper2,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(text, style: t.monoStyle(12.5)),
    );
  }

  Widget _buildDocx(BuildContext context, OfficePreview d) {
    final t = context.ink;
    final m = d.meta;
    final bits = <String>[
      'Word 文档',
      '${m['paragraphs'] ?? 0} 段',
      if ((m['tables'] as num? ?? 0) > 0) '${m['tables']} 个表格',
      if ((m['images'] as num? ?? 0) > 0) '${m['images']} 张图片',
      if ((m['omitted_images'] as num? ?? 0) > 0) '已省略 ${m['omitted_images']} 张图',
      if (d.truncated) '仅显示前部分内容',
    ];
    return Column(children: [
      _summaryBar(context, bits.join(' · ')),
      Expanded(
        child: d.blocks.isEmpty && d.title.isEmpty
            ? Center(child: Text('（空白文档）', style: TextStyle(color: t.muted)))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: InkCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d.title.isNotEmpty) ...[
                        SelectableText(
                          d.title,
                          style: const TextStyle(
                            fontFamilyFallback: InkTokens.serif,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            height: 1.3,
                          ),
                        ),
                        Divider(height: 22, color: t.line.withValues(alpha: 0.35)),
                      ],
                      ..._buildBlocks(context, d.blocks),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }

  List<Widget> _buildBlocks(BuildContext context, List<OfficeBlock> blocks) {
    final t = context.ink;
    final out = <Widget>[];
    for (final b in blocks) {
      if (b.kind == 'heading') {
        final sz = switch (b.level) {
          1 => 20.0,
          2 => 18.0,
          3 => 16.5,
          _ => 15.5,
        };
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 5),
          child: SelectableText(
            b.text,
            style: TextStyle(
              fontFamilyFallback: InkTokens.serif,
              fontSize: sz,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ));
      } else if (b.kind == 'paragraph') {
        final span = b.runs.isEmpty
            ? TextSpan(text: b.text)
            : TextSpan(
                children: [
                  for (final r in b.runs)
                    TextSpan(
                      text: r.text,
                      style: TextStyle(
                        fontWeight: r.bold ? FontWeight.w700 : null,
                        fontStyle: r.italic ? FontStyle.italic : null,
                        decoration: TextDecoration.combine([
                          if (r.underline) TextDecoration.underline,
                          if (r.strike) TextDecoration.lineThrough,
                        ]),
                      ),
                    ),
                ],
              );
        final textWidget = SelectableText.rich(
          span,
          style: TextStyle(fontSize: 14.5, height: 1.65, color: t.ink),
        );
        out.add(Padding(
          padding: EdgeInsets.only(left: b.indent * 16.0, top: 3, bottom: 5),
          child: b.isList
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 1),
                      child: Text('•', style: TextStyle(color: t.accent, fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                    Expanded(child: textWidget),
                  ],
                )
              : textWidget,
        ));
      } else if (b.kind == 'table' && b.rows.isNotEmpty) {
        out.add(_buildBlockTable(context, b));
      } else if (b.kind == 'image') {
        final bytes = _decodeDataUri(b.src);
        if (bytes != null) {
          out.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.line, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ));
        }
      }
    }
    return out;
  }

  Widget _buildBlockTable(BuildContext context, OfficeBlock b) {
    final t = context.ink;
    final maxCols = b.rows.fold<int>(0, (prev, r) => r.length > prev ? r.length : prev);
    if (maxCols == 0) return const SizedBox.shrink();
    final borderColor = t.line.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: borderColor, width: 1.2),
            children: [
              for (var ri = 0; ri < b.rows.length; ri++)
                TableRow(
                  decoration: ri == 0 ? BoxDecoration(color: t.paper2) : null,
                  children: [
                    for (var ci = 0; ci < maxCols; ci++)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260, minWidth: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          child: SelectableText(
                            ci < b.rows[ri].length ? b.rows[ri][ci].text : '',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: ri == 0 ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (b.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('（表格行列过多，仅显示前部分内容）', style: TextStyle(fontSize: 12, color: t.muted)),
          ),
      ]),
    );
  }

  Widget _buildExcel(BuildContext context, OfficePreview d) {
    final t = context.ink;
    if (d.sheets.isEmpty) {
      return Column(children: [
        _summaryBar(context, 'Excel 表格 · 0 个工作表'),
        Expanded(child: Center(child: Text('（空工作簿）', style: TextStyle(color: t.muted)))),
      ]);
    }
    final si = _sheetIdx.clamp(0, d.sheets.length - 1);
    final sh = d.sheets[si];
    final rows = sh.rows;
    final cols = rows.isEmpty ? 0 : rows.first.length;
    final totalSheets = d.meta['total_sheets'] ?? d.sheets.length;
    final bits = <String>[
      'Excel 表格',
      '共 $totalSheets 个工作表',
      '${sh.name}（${sh.totalRows > 0 ? sh.totalRows : rows.length} 行 × ${sh.totalCols > 0 ? sh.totalCols : cols} 列）',
      if (sh.truncatedRows || sh.truncatedCols) '仅显示前 ${rows.length} 行 × $cols 列',
    ];
    final borderColor = t.line.withValues(alpha: 0.25);

    return Column(children: [
      _summaryBar(context, bits.join(' · ')),
      Container(
        width: double.infinity,
        color: t.paper2,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < d.sheets.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _sheetIdx = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == si ? t.ink : t.paper,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: t.line, width: 1.5),
                  ),
                  child: Text(
                    d.sheets[i].name.isEmpty ? 'Sheet${i + 1}' : d.sheets[i].name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: i == si ? t.paper : t.ink,
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text('（空白工作表）', style: TextStyle(color: t.muted)))
            : SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    border: TableBorder.all(color: borderColor, width: 1),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: t.paper2),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Text('', style: t.monoStyle(12, color: t.muted)),
                          ),
                          for (var c = 0; c < cols; c++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Center(
                                child: Text(_colName(c),
                                    style: t.monoStyle(12).copyWith(fontWeight: FontWeight.w700)),
                              ),
                            ),
                        ],
                      ),
                      for (var r = 0; r < rows.length; r++)
                        TableRow(
                          decoration: BoxDecoration(color: r.isOdd ? t.paper2.withValues(alpha: 0.45) : t.paper),
                          children: [
                            Container(
                              color: t.paper2,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              alignment: Alignment.centerRight,
                              child: Text('${r + 1}', style: t.monoStyle(11.5, color: t.muted)),
                            ),
                            for (var c = 0; c < cols; c++)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260, minWidth: 52),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                  child: SelectableText(
                                    c < rows[r].length ? rows[r][c] : '',
                                    style: t.monoStyle(12.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _buildPptx(BuildContext context, OfficePreview d) {
    final t = context.ink;
    final m = d.meta;
    final total = m['total_slides'] ?? d.slides.length;
    final bits = <String>[
      'PowerPoint 演示文稿',
      '共 $total 页',
      if ((m['images'] as num? ?? 0) > 0) '${m['images']} 张图片',
      if (d.truncated) '仅显示前 ${d.slides.length} 页',
    ];
    return Column(children: [
      _summaryBar(context, bits.join(' · ')),
      Expanded(
        child: d.slides.isEmpty
            ? Center(child: Text('（空演示文稿）', style: TextStyle(color: t.muted)))
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: d.slides.length,
                itemBuilder: (context, i) {
                  final sl = d.slides[i];
                  return InkCard(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          color: t.paper2,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: t.ink,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text('${sl.index} / ${d.slides.length}',
                                  style: t.monoStyle(11.5, color: t.paper).copyWith(fontWeight: FontWeight.w800)),
                            ),
                            if (sl.title.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sl.title,
                                  style: const TextStyle(
                                    fontFamilyFallback: InkTokens.serif,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: sl.blocks.isEmpty && sl.title.isEmpty
                              ? Text('（此页无文本内容）', style: TextStyle(color: t.muted))
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _buildBlocks(context, sl.blocks),
                                ),
                        ),
                        if (sl.notes.isNotEmpty)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: t.paper2,
                              border: Border(top: BorderSide(color: t.line.withValues(alpha: 0.3))),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: SelectableText(
                              '演讲者备注：${sl.notes}',
                              style: TextStyle(fontSize: 12.5, height: 1.5, color: t.muted),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
