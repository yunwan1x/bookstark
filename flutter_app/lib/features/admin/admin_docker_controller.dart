import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import 'admin_assets_repository.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';

enum DockerPhase {
  idle,
  reading,
  ready,
  failed,
  reviewing,
  submitting,
  unknown,
  background,
  revoked,
}

enum DockerFailure { read, changed, invalid, refused, network, unknown }

final class DockerReceiptSummary {
  DockerReceiptSummary(DockerReview review)
    : resource = review.resource,
      action = review.action,
      target =
          review.target ??
          (review.body?['name'] as String?) ??
          (review.body?['image'] as String?) ??
          '',
      name =
          review.inspect?.name ??
          review.record?.name ??
          (review.body?['name'] as String?) ??
          (review.body?['image'] as String?) ??
          '';
  final DockerResource resource;
  final String action, target, name;
  @override
  String toString() => 'DockerReceiptSummary';
}

class AdminDockerController extends ChangeNotifier {
  AdminDockerController(this.repository);
  final AdminDockerRepository repository;
  DockerResource resource = DockerResource.containers;
  DockerPhase phase = DockerPhase.idle;
  DockerFailure? failure;
  List<DockerRecord> rows = const [];
  DockerInspect? detail;
  DockerObservation? observation;
  bool receipt = false;
  DockerReceiptSummary? receiptSummary;
  String query = '';
  int _generation = 0;
  bool _disposed = false;
  DockerReview? _review;
  bool get active => !_disposed && repository.active;
  bool get busy => {
    DockerPhase.reading,
    DockerPhase.reviewing,
    DockerPhase.submitting,
  }.contains(phase);
  bool get canMutate =>
      active &&
      !busy &&
      repository.unknown == null &&
      phase != DockerPhase.background &&
      phase != DockerPhase.revoked;
  bool get unknown => repository.unknown != null;
  List<DockerRecord> get filtered {
    final value = query.toLowerCase();
    return List.unmodifiable(
      rows.where(
        (row) =>
            row.name.toLowerCase().contains(value) ||
            row.image.toLowerCase().contains(value) ||
            row.id.toLowerCase().contains(value),
      ),
    );
  }

  bool _current(int ticket) => active && ticket == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _error(Object error) {
    if (!active || error is AdminAssetOwnerLost) {
      _clear();
      phase = DockerPhase.revoked;
      return;
    }
    failure = switch (error) {
      AdminAssetTargetChanged() => DockerFailure.changed,
      FormatException() => DockerFailure.invalid,
      DockerMutationUnknown() => DockerFailure.unknown,
      ApiFailure(status: >= 400 && < 500) => DockerFailure.refused,
      _ => DockerFailure.network,
    };
    phase = unknown ? DockerPhase.unknown : DockerPhase.failed;
  }

  void filter(String value) {
    query = value;
    _notify();
  }

  Future<void> read([DockerResource? selected]) async {
    if (!active || busy || phase == DockerPhase.background) return;
    if (selected != null) resource = selected;
    final ticket = ++_generation;
    rows = const [];
    detail = null;
    observation = null;
    phase = DockerPhase.reading;
    failure = null;
    _notify();
    try {
      final result = await repository.list(resource);
      if (!_current(ticket)) return;
      rows = result;
      phase = unknown ? DockerPhase.unknown : DockerPhase.ready;
    } catch (error) {
      if (_current(ticket)) _error(error);
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  Future<DockerInspect?> inspect(DockerRecord row) async {
    if (!active || busy || phase == DockerPhase.background) return null;
    final ticket = ++_generation;
    detail = null;
    phase = DockerPhase.reading;
    failure = null;
    _notify();
    try {
      final result = await repository.inspect(row);
      if (!_current(ticket)) return null;
      detail = result;
      phase = DockerPhase.ready;
      return result;
    } catch (error) {
      if (_current(ticket)) _error(error);
      return null;
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  Future<DockerReview?> review(Future<DockerReview> Function() prepare) async {
    if (!canMutate) return null;
    final ticket = ++_generation;
    failure = null;
    phase = DockerPhase.reviewing;
    _notify();
    try {
      final plan = await prepare();
      if (!_current(ticket)) {
        repository.cancelReview();
        return null;
      }
      _review = plan;
      phase = DockerPhase.ready;
      return plan;
    } catch (error) {
      if (_current(ticket)) _error(error);
      return null;
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  void cancelReview() {
    _review = null;
    repository.cancelReview();
  }

  Future<bool> commit(DockerReview plan) async {
    if (!canMutate || !identical(_review, plan)) return false;
    final ticket = ++_generation;
    receipt = false;
    receiptSummary = null;
    failure = null;
    observation = null;
    phase = DockerPhase.submitting;
    _review = null;
    _notify();
    try {
      await repository.commit(plan);
      if (!_current(ticket)) return false;
      receipt = true;
      receiptSummary = DockerReceiptSummary(plan);
      phase = DockerPhase.ready;
      return true;
    } catch (error) {
      if (_current(ticket)) _error(error);
      return false;
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  Future<void> observe() async {
    if (!active || busy || !unknown || phase == DockerPhase.background) return;
    final ticket = ++_generation;
    phase = DockerPhase.reading;
    failure = null;
    observation = null;
    _notify();
    try {
      final result = await repository.observeUnknown();
      if (!_current(ticket)) return;
      observation = result;
      resource = repository.unknown!.resource;
      rows = result.rows;
      detail = result.container;
      phase = DockerPhase.unknown;
    } catch (error) {
      if (_current(ticket)) _error(error);
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  void finishObservation() {
    if (!active || busy || observation == null || !unknown) return;
    repository.finishUnknownReview();
    observation = null;
    detail = null;
    phase = DockerPhase.ready;
    failure = null;
    receipt = false;
    receiptSummary = null;
    _notify();
  }

  void _clear() {
    rows = const [];
    detail = null;
    observation = null;
    query = '';
    _review = null;
    receipt = false;
    receiptSummary = null;
  }

  void background() {
    if (_disposed) return;
    ++_generation;
    repository.cancel();
    _clear();
    phase = DockerPhase.background;
    _notify();
  }

  /// Foreground return only enables an explicit read. It never dispatches.
  void resume() {
    if (_disposed || phase != DockerPhase.background) return;
    phase = unknown ? DockerPhase.unknown : DockerPhase.idle;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _clear();
    repository.dispose();
    super.dispose();
  }
}
