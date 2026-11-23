import 'package:clipboard_client/models/item.dart';
import 'package:clipboard_client/services/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Office 文件名识别（与服务端 office.py 一致）', () {
    for (final n in ['a.docx', 'A.DOCX', 'b.xlsx', 'c.xlsm', 'd.xls', 'e.pptx', 'f.doc', 'g.ppt']) {
      expect(ClipItem.isOfficeName(n), isTrue, reason: n);
      final it = ClipItem(uuid: '1', type: 'file', visibility: 'private', created: 0, size: 10, mine: true, filename: n);
      expect(it.mediaKind, MediaKind.office, reason: n);
    }
    for (final n in ['a.zip', 'a.pdf', 'a.txt', 'docx']) {
      expect(ClipItem.isOfficeName(n), isFalse, reason: n);
    }
  });

  test('OfficePreview.fromJson 解析 docx / xlsx / pptx', () {
    final doc = OfficePreview.fromJson({
      'type': 'docx',
      'title': '测试文档',
      'truncated': false,
      'meta': {'paragraphs': 2, 'tables': 1, 'images': 0},
      'blocks': [
        {'kind': 'heading', 'level': 1, 'text': '标题'},
        {
          'kind': 'paragraph',
          'text': '粗体正文',
          'list': true,
          'indent': 1,
          'runs': [
            {'t': '粗体', 'b': true},
            {'t': '正文'},
          ],
        },
        {
          'kind': 'table',
          'rows': [
            [
              {'text': 'A', 'colspan': 2},
            ],
          ],
        },
      ],
    });
    expect(doc.type, 'docx');
    expect(doc.title, '测试文档');
    expect(doc.blocks.length, 3);
    expect(doc.blocks[1].runs.first.bold, isTrue);
    expect(doc.blocks[2].rows.first.first.colspan, 2);

    final xl = OfficePreview.fromJson({
      'type': 'xlsx',
      'truncated': true,
      'meta': {'sheets': 1, 'total_sheets': 1},
      'sheets': [
        {
          'name': '预算',
          'rows': [
            ['项目', '金额'],
            ['主机', '100'],
          ],
          'total_rows': 600,
          'total_cols': 2,
          'truncated_rows': true,
        },
      ],
    });
    expect(xl.sheets.single.name, '预算');
    expect(xl.sheets.single.truncatedRows, isTrue);
    expect(xl.sheets.single.rows[1][1], '100');

    final ppt = OfficePreview.fromJson({
      'type': 'pptx',
      'meta': {'slides': 1, 'total_slides': 1},
      'slides': [
        {
          'index': 1,
          'title': '封面',
          'blocks': [
            {'kind': 'paragraph', 'text': '要点一', 'indent': 1},
          ],
          'notes': '演讲备注',
        },
      ],
    });
    expect(ppt.slides.single.title, '封面');
    expect(ppt.slides.single.notes, '演讲备注');
    expect(ppt.slides.single.blocks.single.indent, 1);
  });
}
