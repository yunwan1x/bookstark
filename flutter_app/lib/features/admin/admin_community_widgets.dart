import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/attachments.dart';
import '../../widgets/native_image.dart';
import 'admin_community_scope.dart';
import 'admin_community_strings.dart';
import 'admin_community_controller.dart';
import 'admin_friend_links_models.dart';

enum AdminCommunityTone { info, warning, danger, neutral }

class AdminCommunityInfo extends StatelessWidget {
  const AdminCommunityInfo({
    super.key,
    required this.text,
    this.tone = AdminCommunityTone.info,
  });
  final String text;
  final AdminCommunityTone tone;
  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (tone) {
      AdminCommunityTone.info => (
        const Color(0xffeaf2ff),
        const Color(0xff1555ef),
        Icons.info_outline,
      ),
      AdminCommunityTone.warning => (
        const Color(0xfffff2d5),
        const Color(0xff946100),
        Icons.warning_amber_rounded,
      ),
      AdminCommunityTone.danger => (
        const Color(0xffffe8ea),
        const Color(0xffbf2637),
        Icons.warning_amber_rounded,
      ),
      AdminCommunityTone.neutral => (
        const Color(0xffeff1f5),
        const Color(0xff586882),
        Icons.info_outline,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(child: Text(text, softWrap: true)),
        ],
      ),
    );
  }
}

class AdminCommunityNoticeCard extends StatelessWidget {
  const AdminCommunityNoticeCard({
    super.key,
    required this.controller,
    required this.strings,
  });
  final AdminCommunityController controller;
  final AdminCommunityStrings strings;
  @override
  Widget build(BuildContext context) {
    final notice = controller.notice;
    if (notice == null || notice == AdminCommunityNotice.loaded) {
      return const SizedBox.shrink();
    }
    final normal = {
      AdminCommunityNotice.empty,
      AdminCommunityNotice.knownLinksRead,
      AdminCommunityNotice.knownDeletedRead,
      AdminCommunityNotice.knownDeleteZero,
      AdminCommunityNotice.reviewEnded,
      AdminCommunityNotice.staleDraftDiscarded,
    };
    final unknown = {
      AdminCommunityNotice.unknownWrite,
      AdminCommunityNotice.unknownCurrent,
    };
    final deleted = controller is AdminCommentsController
        ? (controller as AdminCommentsController).actualDeleted
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: AdminCommunityInfo(
          text: strings.notice(notice, deleted: deleted),
          tone: unknown.contains(notice)
              ? AdminCommunityTone.neutral
              : normal.contains(notice)
              ? AdminCommunityTone.info
              : AdminCommunityTone.warning,
        ),
      ),
    );
  }
}

class AdminCommunityPager extends StatelessWidget {
  const AdminCommunityPager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.strings,
    this.onPrevious,
    this.onNext,
  });
  final int page, totalPages;
  final AdminCommunityStrings strings;
  final VoidCallback? onPrevious, onNext;
  @override
  Widget build(BuildContext context) {
    final previous = OutlinedButton(
      onPressed: onPrevious,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(strings.t('上一页', 'Previous')),
    );
    final next = OutlinedButton(
      onPressed: onNext,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(strings.t('下一页', 'Next')),
    );
    final label = Text(
      strings.page(page, totalPages),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    if (MediaQuery.textScalerOf(context).scale(16) > 24) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 8),
          previous,
          const SizedBox(height: 8),
          next,
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [previous, label, next],
      ),
    );
  }
}

class AdminFriendQrReader {
  AdminFriendQrReader(this.scope, {http.Client? transport})
    : _attachments = RemoteAttachments(
        scope.client,
        publicTransport: transport,
      ) {
    scope.addListener(_scopeChanged);
  }
  final AdminCommunityScope scope;
  final RemoteAttachments _attachments;
  bool _closed = false;
  void _scopeChanged() {
    if (!scope.active) {
      close();
    }
  }

  Future<Uint8List> read(String path) async {
    try {
      if (_closed || !scope.guard() || scope.owner.role != 0) {
        throw const AttachmentCancelled();
      }
      if (!canonicalFriendQr(path)) {
        throw const FormatException('Invalid QR preview path');
      }
      final base = scope.client.baseUri.toString().replaceFirst(
        RegExp(r'/+$'),
        '',
      );
      final uri = Uri.parse('$base$path');
      if (uri.origin != scope.client.baseUri.origin ||
          !_attachments.owns(uri)) {
        throw const FormatException('QR preview escaped server ownership');
      }
      final bytes = await _attachments
          .readPublic(uri, maxBytes: 2 * 1024 * 1024)
          .timeout(const Duration(seconds: 15));
      if (_closed || !scope.guard()) throw const AttachmentCancelled();
      return bytes;
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    scope.removeListener(_scopeChanged);
    _attachments.close();
  }
}

class AdminFriendQrThumbnail extends StatefulWidget {
  const AdminFriendQrThumbnail({
    super.key,
    required this.scope,
    required this.path,
    required this.strings,
    this.transportFactory,
  });
  final AdminCommunityScope scope;
  final String path;
  final AdminCommunityStrings strings;
  final http.Client Function()? transportFactory;
  @override
  State<AdminFriendQrThumbnail> createState() => _AdminFriendQrThumbnailState();
}

class _AdminFriendQrThumbnailState extends State<AdminFriendQrThumbnail> {
  AdminFriendQrReader? _reader;
  Uint8List? _bytes;
  int _epoch = 0;
  bool _loading = true, _failed = false;
  @override
  void initState() {
    super.initState();
    widget.scope.addListener(_scopeChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AdminFriendQrThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      oldWidget.scope.removeListener(_scopeChanged);
      widget.scope.addListener(_scopeChanged);
    }
    if (oldWidget.scope != widget.scope || oldWidget.path != widget.path) {
      unawaited(_load());
    }
  }

  void _scopeChanged() {
    if (widget.scope.active) return;
    _epoch++;
    _reader?.close();
    _bytes = null;
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    _reader?.close();
    _bytes = null;
    _failed = false;
    _loading = true;
    final reader = AdminFriendQrReader(
      widget.scope,
      transport: widget.transportFactory?.call(),
    );
    _reader = reader;
    try {
      final bytes = await reader.read(widget.path);
      if (!mounted || epoch != _epoch || !widget.scope.active) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    } finally {
      reader.close();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _reader?.close();
    _bytes = null;
    widget.scope.removeListener(_scopeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scope.active) return const SizedBox.shrink();
    final s = widget.strings;
    if (_loading) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed || _bytes == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.t('二维码图片加载失败', 'Could not load QR image')),
          TextButton(
            onPressed: () => setState(() {
              unawaited(_load());
            }),
            child: Text(s.t('重试预览', 'Retry preview')),
          ),
        ],
      );
    }
    return NativeImage(
      bytes: _bytes!,
      label: s.t('本站二维码图片', 'QR image from this server'),
      width: 120,
      height: 120,
      maxDecodeSide: 512,
      english: s.english,
    );
  }
}
