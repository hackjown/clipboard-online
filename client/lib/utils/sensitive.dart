/// 与 Web 端一致的敏感内容启发规则
bool isSensitive(String text) {
  if (text.isEmpty) return false;
  final t = text;
  if (RegExp(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----').hasMatch(t)) return true;
  if (RegExp(r'\bAKIA[0-9A-Z]{16}\b').hasMatch(t)) return true;
  if (RegExp(r'\bsk-[A-Za-z0-9]{20,}\b').hasMatch(t)) return true;
  if (RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b').hasMatch(t)) {
    return true;
  }
  if (RegExp(r'(?:password|passwd|pwd|secret|api[_-]?key)\s*[=:]\s*\S+', caseSensitive: false)
      .hasMatch(t)) {
    return true;
  }
  final trimmed = t.trim();
  if (RegExp(r'^[A-Za-z0-9+/=]{80,}$').hasMatch(trimmed) &&
      RegExp(r'[+/=]').hasMatch(trimmed)) {
    return true;
  }
  if (RegExp(r'^[A-Za-z0-9_\-]{40,}$').hasMatch(trimmed)) return true;
  return false;
}
