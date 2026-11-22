/// URI grammar shared by the local source-insertion protocol. No IO or network.
String localHtmlAttachmentName(Uri uri) {
  if (uri.scheme != 'bookstark-attachment' || uri.host.isNotEmpty ||
      uri.userInfo.isNotEmpty || uri.hasPort || uri.hasQuery || uri.hasFragment ||
      uri.pathSegments.length != 2 || uri.toString().length > 2048 ||
      !RegExp(r'^[a-f0-9]{32}$').hasMatch(uri.pathSegments.first)) {
    throw const FormatException('Invalid local HTML attachment reference');
  }
  final name = uri.pathSegments.last;
  if (name.isEmpty || name == '.' || name == '..' || name.length > 255 ||
      name.contains('/') || name.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
    throw const FormatException('Invalid local HTML attachment name');
  }
  return name;
}
