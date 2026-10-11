import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../models/item.dart';
import '../services/api.dart';
import '../services/file_transfer.dart';
import '../services/media_cache.dart';
import '../theme/ink_theme.dart';
import '../widgets/archive_view.dart';
import '../widgets/ink.dart';

/// 详情 / 预览：图片（可缩放）、视频、音频、文本；其它类型提供打开 / 分享。
class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.api, required this.item});
  final ClipApi api;
  final ClipItem item;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late final FileTransferService _xfer = FileTransferService(widget.api);
  late final MediaCache _cache = MediaCache(widget.api);
  final DownloadCancel _cancel = DownloadCancel();
  double? _progress; // null=未知；0..1
  bool _downloading = false;
  String _progressText = '';
  VideoPlayerController? _vc;
  PdfControllerPinch? _pdf;
  String? _text;
  String? _err;
  bool _busy = false;

  ClipItem get it => widget.item;
  String get _url => widget.api.downloadUrl(it.filename ?? '');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      switch (it.mediaKind) {
        case MediaKind.video:
        case MediaKind.audio:
          // 先用带认证的 Dart HTTP 客户端下载到本地缓存，再用本地文件播放（避开 AVPlayer 的 ATS / 认证头问题）
          setState(() => _downloading = true);
          final f = await _cache.fetch(
            uuid: it.uuid,
            filename: it.filename ?? 'media',
            url: _url,
            expectedSize: it.size,
            cancel: _cancel,
            onProgress: (got, total) {
              if (!mounted) return;
              setState(() {
                _progress = total > 0 ? got / total : null;
                _progressText = total > 0
                    ? '${(got / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB'
                    : '${(got / 1048576).toStringAsFixed(1)} MB';
              });
            },
          );
          if (!mounted) return;
          final c = VideoPlayerController.file(f);
          _vc = c;
          await c.initialize();
          c.addListener(() {
            if (mounted) setState(() {});
          });
          if (mounted) setState(() => _downloading = false);
          if (it.mediaKind == MediaKind.video) await c.play();
        case MediaKind.pdf:
          // 与视频同一套：带认证下载到本机缓存（进度 / 复用 / 可取消），再用本地文件渲染
          setState(() => _downloading = true);
          final pf = await _cache.fetch(
            uuid: it.uuid,
            filename: it.filename ?? 'document.pdf',
            url: _url,
            expectedSize: it.size,
            cancel: _cancel,
            onProgress: (got, total) {
              if (!mounted) return;
              setState(() {
                _progress = total > 0 ? got / total : null;
                _progressText = total > 0
                    ? '${(got / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB'
                    : '${(got / 1048576).toStringAsFixed(1)} MB';
              });
            },
          );
          if (!mounted) return;
          _pdf = PdfControllerPinch(document: PdfDocument.openFile(pf.path));
          if (mounted) setState(() => _downloading = false);
        case MediaKind.text:
          if (it.isText) {
            _text = it.content ?? '';
          } else {
            final r = await http.get(Uri.parse(_url), headers: widget.api.authHeaders);
            if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
            final bytes = r.bodyBytes.length > 400 * 1024 ? r.bodyBytes.sublist(0, 400 * 1024) : r.bodyBytes;
            _text = _decode(bytes);
          }
        default:
          break;
      }
    } catch (e) {
      if (e is! DownloadCancelled) _err = '加载失败：$e';
      _downloading = false;
    }
    if (mounted) setState(() {});
  }

  String _decode(List<int> b) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(b);
    } catch (_) {
      return String.fromCharCodes(b);
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    _vc?.dispose();
    _pdf?.dispose();
    super.dispose();
  }

  Future<File> _download() => _xfer.downloadToCache(filename: it.filename!, remoteUrl: _url);

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      if (it.isText && it.filename == null) {
        await _xfer.shareText(it.content ?? '');
      } else {
        await _xfer.shareFile(await _download());
      }
    } catch (e) {
      _toast('分享失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 保存：macOS → 下载文件夹并在访达中显示；iOS/Android → 系统分享面板（存储到文件 / 相册）
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final f = await _download();
      if (!kIsWeb && Platform.isMacOS) {
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          final dest = File(p.join(dir.path, p.basename(it.filename!)));
          await f.copy(dest.path);
          await _xfer.revealOrOpen(dest);
          _toast('已保存到「下载」');
        }
      } else {
        await _xfer.shareFile(f);
      }
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final kind = it.mediaKind;
    return Scaffold(
      appBar: AppBar(
        title: Text(it.isFile ? (it.filename ?? '预览') : '文本', overflow: TextOverflow.ellipsis),
      ),
      body: PaperBackground(
        child: Column(children: [
          Expanded(child: _body(context, kind)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(child: InkButton(label: '分享', icon: Icons.ios_share, onPressed: _busy ? null : _share, busy: _busy)),
                if (it.isFile) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkButton(
                      label: (!kIsWeb && Platform.isMacOS) ? '保存到下载' : '保存',
                      icon: Icons.download_outlined,
                      variant: InkVariant.ink,
                      onPressed: _busy ? null : _save,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
      backgroundColor: t.bg,
    );
  }

  Widget _loading(BuildContext context) {
    final t = context.ink;
    return Center(
      child: InkCard(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_downloading ? '正在下载到本机缓存…' : '正在准备播放…', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: _progress, color: t.accent, backgroundColor: t.ink.withValues(alpha: 0.15), minHeight: 8),
          const SizedBox(height: 8),
          Text(_progress != null ? '${(_progress! * 100).toStringAsFixed(0)}%  $_progressText' : _progressText,
              style: t.monoStyle(12, color: t.muted)),
          const SizedBox(height: 14),
          if (_downloading)
            InkButton(
              label: '取消',
              dense: true,
              onPressed: () {
                _cancel.cancel();
                Navigator.of(context).maybePop();
              },
            ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, MediaKind kind) {
    final t = context.ink;
    if (_err != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, style: TextStyle(color: t.danger))));
    }
    switch (kind) {
      case MediaKind.image:
        return _ImageViewer(url: _url, headers: widget.api.authHeaders);
      case MediaKind.video:
        final c = _vc;
        if (c == null || !c.value.isInitialized) return _loading(context);
        return Column(children: [
          Expanded(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            ),
          ),
          _PlayerBar(controller: c),
        ]);
      case MediaKind.audio:
        final c = _vc;
        if (c == null || !c.value.isInitialized) return _loading(context);
        return Center(
          child: InkCard(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.graphic_eq_rounded, size: 72, color: t.accent),
              const SizedBox(height: 8),
              Text(it.filename ?? '', style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              _PlayerBar(controller: c),
            ]),
          ),
        );
      case MediaKind.text:
        if (_text == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: InkCard(
            margin: EdgeInsets.zero,
            color: t.paper2,
            child: SelectableText(_text!, style: t.monoStyle(13.5)),
          ),
        );
      case MediaKind.archive:
        return ArchiveView(api: widget.api, item: it);
      case MediaKind.pdf:
        final pc = _pdf;
        if (pc == null) return _loading(context);
        return Column(children: [
          Expanded(
            child: PdfViewPinch(
              controller: pc,
              backgroundDecoration: BoxDecoration(color: t.paper2),
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('PDF 无法渲染：$error\n可用下方「分享 / 保存」交给其它应用打开。',
                        textAlign: TextAlign.center, style: TextStyle(color: t.danger)),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: t.paper,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: PdfPageNumber(
                controller: pc,
                builder: (_, state, page, pages) => Text(
                  state == PdfLoadingState.success ? '第 $page / ${pages ?? '?'} 页 · 双指缩放 / 滚动' : '',
                  style: t.monoStyle(12.5),
                ),
              ),
            ),
          ),
        ]);
      case MediaKind.other:
        return Center(
          child: InkCard(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(kind == MediaKind.pdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
                  size: 64, color: t.ink),
              const SizedBox(height: 10),
              Text(it.filename ?? '', style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('暂不支持内置预览，可用「分享 / 保存」交给其它应用打开。',
                  textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
            ]),
          ),
        );
    }
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 6,
        child: Center(
          child: Image.network(
            url,
            headers: headers,
            fit: BoxFit.contain,
            loadingBuilder: (c, w, prog) =>
                prog == null ? w : const Center(child: CircularProgressIndicator()),
            errorBuilder: (c, e, s) =>
                const Center(child: Text('图片加载失败', style: TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.controller});
  final VideoPlayerController controller;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final v = controller.value;
    final total = v.duration.inMilliseconds.clamp(1, 1 << 31);
    final pos = v.position.inMilliseconds.clamp(0, total);
    return Container(
      color: t.paper,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        InkIconButton(
          icon: v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: () => v.isPlaying ? controller.pause() : controller.play(),
        ),
        Expanded(
          child: Slider(
            value: pos.toDouble(),
            max: total.toDouble(),
            activeColor: t.accent,
            inactiveColor: t.ink.withValues(alpha: 0.2),
            onChanged: (x) => controller.seekTo(Duration(milliseconds: x.round())),
          ),
        ),
        Text('${_fmt(v.position)} / ${_fmt(v.duration)}', style: t.monoStyle(11.5)),
      ]),
    );
  }
}
