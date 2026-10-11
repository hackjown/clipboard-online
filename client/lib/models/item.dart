class ClipItem {
  ClipItem({
    required this.uuid,
    required this.type,
    required this.visibility,
    required this.created,
    required this.size,
    required this.mine,
    this.content,
    this.filename,
    this.ext,
    this.isImage = false,
    this.ownerUsername,
    this.expiresAt,
    this.favorite = false,
    this.pinned = false,
    this.tags = const [],
    this.hasShare = false,
    this.shareToken,
    this.looksMd = false,
    this.isUrl = false,
    this.mime,
  });

  final String uuid;
  final String type; // text | file
  final String visibility;
  final double created;
  final int size;
  final bool mine;
  final String? content;
  final String? filename;
  final String? ext;
  final bool isImage;
  final String? ownerUsername;
  final double? expiresAt;
  final bool favorite;
  final bool pinned;
  final List<String> tags;
  final bool hasShare;
  final String? shareToken;
  final bool looksMd;
  final bool isUrl;
  final String? mime;

  bool get isText => type == 'text';
  bool get isFile => type == 'file';
  bool get isPublic => visibility == 'public';

  factory ClipItem.fromJson(Map<String, dynamic> j) => ClipItem(
        uuid: j['uuid'] as String,
        type: j['type'] as String,
        visibility: (j['visibility'] as String?) ?? 'public',
        created: (j['created'] as num?)?.toDouble() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        mine: j['mine'] == true,
        content: j['content'] as String?,
        filename: j['filename'] as String?,
        ext: j['ext'] as String?,
        isImage: j['is_image'] == true,
        ownerUsername: j['owner_username'] as String?,
        expiresAt: (j['expires_at'] as num?)?.toDouble(),
        favorite: j['favorite'] == true,
        pinned: j['pinned'] == true,
        tags: (j['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
        hasShare: j['has_share'] == true,
        shareToken: j['share_token'] as String?,
        looksMd: j['looks_md'] == true,
        isUrl: j['is_url'] == true,
        mime: j['mime'] as String?,
      );
}

class ItemsResult {
  ItemsResult({
    required this.items,
    required this.counts,
    this.tags = const [],
    this.needAuth = false,
  });
  final List<ClipItem> items;
  final Map<String, dynamic> counts;
  final List<String> tags;
  final bool needAuth;
}
