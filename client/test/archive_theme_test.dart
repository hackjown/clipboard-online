import 'package:clipboard_client/models/item.dart';
import 'package:clipboard_client/services/api.dart';
import 'package:clipboard_client/services/theme_controller.dart';
import 'package:clipboard_client/widgets/archive_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('压缩包文件名识别（与服务端一致）', () {
    for (final n in ['a.zip', 'A.JAR', 'a.apk', 'a.tar', 'a.tar.gz', 'a.tgz', 'a.tar.bz2', 'a.tar.xz', 'a.7z', 'a.rar']) {
      expect(ClipItem.isArchiveName(n), isTrue, reason: n);
    }
    for (final n in ['a.docx', 'a.gz', 'a.txt', 'zip']) {
      expect(ClipItem.isArchiveName(n), isFalse, reason: n);
    }
  });

  test('目录树：层级、文件夹汇总、zip-slip 名称只当文本', () {
    final root = ArchiveNode.build([
      ArchiveEntry(path: 'docs/', size: 0, isDir: true),
      ArchiveEntry(path: 'docs/a.txt', size: 5, isDir: false),
      ArchiveEntry(path: 'docs/sub/b.bin', size: 100, isDir: false),
      ArchiveEntry(path: '../../etc/passwd', size: 7, isDir: false),
    ]);
    final docs = root.kids['docs/']!;
    expect(docs.isDir, isTrue);
    expect(docs.count, 2);
    expect(docs.size, 105);
    expect(docs.kids['sub/']!.kids['b.bin']!.size, 100);
    // '..' 只是一个普通目录名，不会被解析成上级目录
    expect(root.kids['../']!.kids['../']!.kids['etc/']!.kids['passwd']!.size, 7);
    expect(root.sortedKids().first.isDir, isTrue);
  });

  test('ArchiveListing.fromJson', () {
    final d = ArchiveListing.fromJson({
      'type': 'zip',
      'total': 3,
      'total_size': 10,
      'truncated': true,
      'encrypted': true,
      'entries': [
        {'path': 'a', 'size': 1, 'is_dir': false, 'encrypted': true}
      ],
    });
    expect(d.truncated && d.encrypted, isTrue);
    expect(d.entries.single.encrypted, isTrue);
  });

  test('ThemeController 编码 / 解析', () {
    expect(ThemeController.parse('dark'), ThemeMode.dark);
    expect(ThemeController.parse('light'), ThemeMode.light);
    expect(ThemeController.parse(null), ThemeMode.system);
    expect(ThemeController.parse('xx'), ThemeMode.system);
    for (final m in ThemeMode.values) {
      expect(ThemeController.parse(ThemeController.encode(m)), m);
    }
  });
}
