import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/bookmark_favicon_store.dart';

class BookmarkFavicon extends StatefulWidget {
  const BookmarkFavicon({
    super.key,
    required this.explicitUrl,
    required this.store,
    required this.scopeKey,
    required this.isCurrent,
  });
  final String explicitUrl;
  final BookmarkFaviconStore store;
  final Object scopeKey;
  final bool Function() isCurrent;
  @override
  State<BookmarkFavicon> createState() => _BookmarkFaviconState();
}

class _BookmarkFaviconState extends State<BookmarkFavicon> {
  ui.Image? _image;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BookmarkFavicon old) {
    super.didUpdateWidget(old);
    if (old.explicitUrl != widget.explicitUrl ||
        old.store != widget.store ||
        old.scopeKey != widget.scopeKey) {
      _image?.dispose();
      _image = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch,
        store = widget.store,
        url = widget.explicitUrl,
        scope = widget.scopeKey;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        store == widget.store &&
        url == widget.explicitUrl &&
        scope == widget.scopeKey &&
        !store.retired &&
        widget.isCurrent();
    ui.Codec? codec;
    ui.Image? image;
    try {
      if (!current()) return;
      final bytes = await store.read(url);
      if (bytes == null || !current()) return;
      var codecExpired = false;
      final codecWork = ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
        allowUpscaling: false,
      );
      unawaited(
        codecWork.then<void>((value) {
          if (codecExpired) value.dispose();
        }, onError: (Object _, StackTrace _) {}),
      );
      codec = await codecWork.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          codecExpired = true;
          throw TimeoutException('Icon decode');
        },
      );
      if (!current()) return;
      var frameExpired = false;
      final frameWork = codec.getNextFrame();
      unawaited(
        frameWork.then<void>((value) {
          if (frameExpired) value.image.dispose();
        }, onError: (Object _, StackTrace _) {}),
      );
      final frame = await frameWork.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          frameExpired = true;
          throw TimeoutException('Icon frame');
        },
      );
      image = frame.image;
      if (!current()) return;
      setState(() {
        _image = image;
        image = null;
      });
    } catch (_) {
      if (current()) store.rejectDecoded(url); /* Stable original link icon. */
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _image == null || widget.store.retired || !widget.isCurrent()
        ? Icon(Icons.link, color: Theme.of(context).colorScheme.primary)
        : Padding(
            padding: const EdgeInsets.all(8),
            child: RawImage(image: _image, fit: BoxFit.contain),
          ),
  );
}
