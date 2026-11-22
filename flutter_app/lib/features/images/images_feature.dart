import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/images_repository.dart';
import 'images_page.dart';

/// Owns the image repository; its HTTP client / local store are borrowed.
class ImagesFeature extends StatefulWidget {
  const ImagesFeature({
    super.key,
    required this.createRepository,
    this.english = false,
    this.ownerScope,
    this.createOwner,
  });
  final ImagesRepository Function() createRepository;
  final bool english;

  /// Stable server/member/local-space identity; Root must supply its namespace.
  final Object? ownerScope;
  final ImageLibraryOwner Function()? createOwner;
  @override
  State<ImagesFeature> createState() => _ImagesFeatureState();
}

class _ImagesFeatureState extends State<ImagesFeature> {
  late ImagesRepository repository;
  late ImageLibraryOwner owner;
  @override
  void initState() {
    super.initState();
    owner = widget.createOwner?.call() ?? ImageLibraryOwner();
    repository = widget.createRepository();
  }

  void _retire(ImagesRepository previous, ImageLibraryOwner previousOwner) {
    unawaited(previousOwner.retireAndDrain().then((_) => previous.dispose()));
  }

  @override
  void didUpdateWidget(covariant ImagesFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerScope != widget.ownerScope) {
      final previous = repository, previousOwner = owner;
      owner = widget.createOwner?.call() ?? ImageLibraryOwner();
      repository = widget.createRepository();
      _retire(previous, previousOwner);
    }
  }

  @override
  void dispose() {
    _retire(repository, owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ImagesPage(repository: repository, owner: owner, english: widget.english);
}
