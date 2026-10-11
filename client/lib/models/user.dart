class ClipUser {
  ClipUser({required this.id, required this.username, this.createdAt});
  final String id;
  final String username;
  final double? createdAt;

  factory ClipUser.fromJson(Map<String, dynamic> j) => ClipUser(
        id: j['id'] as String,
        username: j['username'] as String,
        createdAt: (j['created_at'] as num?)?.toDouble(),
      );
}
