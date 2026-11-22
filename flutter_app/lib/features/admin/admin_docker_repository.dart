import 'dart:async';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_repository.dart';
import 'admin_assets_scope.dart';
import 'admin_docker_models.dart';

final class DockerUnconfirmed {
  DockerUnconfirmed(this.resource, this.action, this.target);
  final DockerResource resource;
  final String action;
  final String? target;
  bool observed = false;
}

final class DockerMutationUnknown implements Exception {
  const DockerMutationUnknown();
  @override
  String toString() => 'Docker result unknown; observe without replay';
}

Object? _dockerFreeze(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable({
      for (final item in value.entries) item.key: _dockerFreeze(item.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_dockerFreeze));
  }
  return value;
}

final class DockerReview {
  DockerReview._(
    this.resource,
    this.action,
    this.target,
    Map<String, Object?>? body,
    this.record,
    this.inspect,
    this.inventory,
  ) : body = body == null ? null : _dockerFreeze(body) as Map<String, Object?>;
  final DockerResource resource;
  final String action;
  final String? target;
  final Map<String, Object?>? body;
  final DockerRecord? record;
  final DockerInspect? inspect;
  final String? inventory;
  @override
  String toString() => 'DockerReview($action)';
}

final class DockerObservation {
  DockerObservation(this.rows, this.container);
  final List<DockerRecord> rows;
  final DockerInspect? container;
}

/// One reviewed host, credential metadata and owner. No retries or raw errors.
class AdminDockerRepository {
  AdminDockerRepository(
    this.scope,
    this.host, {
    AdminAssetCredentialMetadata? credential,
  }) : _credential = credential,
       _credentialBound = credential != null,
       assets = AdminAssetsRepository(scope.client);
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final AdminAssetsRepository assets;
  AdminAssetCredentialMetadata? _credential;
  AdminAssetCredentialMetadata? get reviewedCredential =>
      active ? _credential : null;
  bool _credentialBound;
  bool _disposed = false, _busy = false;
  Completer<void>? _abort;
  DockerReview? _review;
  DockerUnconfirmed? unknown;
  bool get active => !_disposed && scope.active;
  void _guard() {
    if (!active || !scope.guard()) throw AdminAssetOwnerLost();
    if (_abort?.isCompleted == true) throw AdminAssetReadSuperseded();
  }

  Future<void> verifyOwner({Future<void>? abortTrigger}) async {
    _guard();
    final raw = await scope.client.adminAssetPrincipalJson(
      abortTrigger: abortTrigger ?? _abort?.future,
    );
    _guard();
    if (raw['member_id'] != scope.owner.memberId ||
        raw['account'] != scope.owner.account ||
        raw['role'] != 0) {
      scope.close();
      throw AdminAssetOwnerLost();
    }
  }

  Future<void> _verify() async {
    _guard();
    final hosts = await assets.readHosts(
      scope.owner,
      abortTrigger: _abort?.future,
    );
    final matches = hosts.where((v) => v.id == host.id).toList();
    if (matches.length != 1 ||
        matches.single.reviewFingerprint != host.reviewFingerprint) {
      throw const AdminAssetTargetChanged();
    }
    if (host.credentialId != 0) {
      final credentials = await assets.readCredentials(
        scope.owner,
        abortTrigger: _abort?.future,
      );
      final found = credentials
          .where((v) => v.id == host.credentialId)
          .toList();
      if (found.length != 1 ||
          (_credentialBound &&
              found.single.reviewFingerprint !=
                  _credential?.reviewFingerprint)) {
        throw const AdminAssetTargetChanged();
      }
      _credential ??= found.single;
    }
    _credentialBound = true;
    await verifyOwner();
  }

  Future<T> _run<T>(Future<T> Function() fn) async {
    _guard();
    if (_busy) throw const AdminAssetOperationBusy();
    _busy = true;
    final abort = Completer<void>();
    _abort = abort;
    try {
      await _verify();
      final value = await fn();
      _guard();
      return value;
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      rethrow;
    } on AdminAssetOwnerLost {
      scope.close();
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
      _busy = false;
    }
  }

  Future<Map<String, Object?>> _api(
    DockerResource resource, {
    String operation = 'list',
    String? target,
    Map<String, Object?>? body,
    void Function()? onSubmitted,
    int tail = 200,
  }) => scope.client.adminDockerJson(
    host.id,
    resource: resource.name,
    operation: operation,
    target: target,
    body: body,
    onSubmitted: onSubmitted,
    tail: tail,
    abortTrigger: _abort?.future,
  );
  Future<List<DockerRecord>> _list(DockerResource resource) async {
    final raw = await _api(resource);
    _guard();
    return DockerRecord.parseList(resource, raw['data']);
  }

  Future<List<DockerRecord>> list(DockerResource resource) =>
      _run(() => _list(resource));
  Future<DockerInspect> _inspect(String id) async {
    final raw = await _api(
      DockerResource.containers,
      operation: 'inspect',
      target: id,
    );
    _guard();
    return DockerInspect.parse(raw);
  }

  Future<DockerInspect> inspect(DockerRecord row) => _run(() async {
    if (row.resource != DockerResource.containers) {
      throw const FormatException('Container required');
    }
    final result = await _inspect(row.id);
    result.match(row);
    return result;
  });
  Future<DockerRecord> _fresh(DockerRecord expected) async {
    final rows = await _list(expected.resource);
    final same = rows.where((v) => v.target == expected.target).toList();
    if (same.length != 1 || same.single.fingerprint != expected.fingerprint) {
      throw const AdminAssetTargetChanged();
    }
    return same.single;
  }

  String _inventory(List<DockerRecord> rows) {
    final fingerprints = rows.map((v) => v.fingerprint).toList()..sort();
    return dockerDigest(fingerprints);
  }

  Future<DockerReview> reviewAction(
    DockerRecord row,
    String action, {
    DockerInspect? baseline,
    String? policy,
  }) => _run(() async {
    if (unknown != null) throw const DockerMutationUnknown();
    if (row.resource == DockerResource.containers) {
      if (!{
        'start',
        'stop',
        'restart',
        'delete',
        'restart-policy',
      }.contains(action)) {
        throw const FormatException('Invalid container action');
      }
      final detail = await _inspect(row.id);
      detail.match(row);
      if (baseline != null && detail.fingerprint != baseline.fingerprint) {
        throw const AdminAssetTargetChanged();
      }
      if (action == 'delete' && detail.running) {
        throw const AdminAssetTargetChanged();
      }
      if (action == 'restart-policy' && !dockerPolicies.contains(policy)) {
        throw const FormatException('Invalid policy');
      }
      return _review = DockerReview._(
        row.resource,
        action,
        detail.id,
        action == 'restart-policy' ? {'policy': policy!} : null,
        row,
        detail,
        null,
      );
    }
    if (action != 'delete') {
      throw const FormatException('Invalid resource action');
    }
    await _fresh(row);
    return _review = DockerReview._(
      row.resource,
      action,
      row.target,
      null,
      row,
      null,
      null,
    );
  });
  Future<DockerReview> reviewContainerCreate(DockerCreateDraft draft) =>
      _run(() async {
        if (unknown != null) throw const DockerMutationUnknown();
        final request = draft.toRequest();
        final rows = await _list(DockerResource.containers);
        if (rows.any((v) => v.name == draft.name)) {
          throw const AdminAssetTargetChanged();
        }
        return _review = DockerReview._(
          DockerResource.containers,
          'create',
          null,
          request,
          null,
          null,
          null,
        );
      });
  Future<DockerReview> reviewNamedCreate(
    DockerResource resource,
    String name,
    String driver,
  ) => _run(() async {
    if (unknown != null) throw const DockerMutationUnknown();
    if (!{DockerResource.networks, DockerResource.volumes}.contains(resource)) {
      throw const FormatException('Invalid named resource');
    }
    dockerObjectName(name);
    if (driver.isNotEmpty) dockerObjectName(driver);
    final rows = await _list(resource);
    if (rows.any((v) => v.name == name)) throw const AdminAssetTargetChanged();
    return _review = DockerReview._(
      resource,
      'create',
      null,
      {'name': name, 'driver': driver},
      null,
      null,
      null,
    );
  });
  Future<DockerReview> reviewPull(String image) => _run(() async {
    if (unknown != null) throw const DockerMutationUnknown();
    dockerImageReference(image);
    return _review = DockerReview._(
      DockerResource.images,
      'create',
      null,
      {'image': image},
      null,
      null,
      null,
    );
  });
  Future<DockerReview> reviewPrune(DockerResource resource) => _run(() async {
    if (unknown != null) throw const DockerMutationUnknown();
    final rows = await _list(resource);
    return _review = DockerReview._(
      resource,
      'prune',
      null,
      null,
      null,
      null,
      _inventory(rows),
    );
  });
  void _validateReceipt(DockerReview review, Map<String, Object?> raw) {
    dockerText(raw['output'], limit: 2 * 1024 * 1024);
    bool matches;
    if (review.action == 'prune') {
      matches = raw['resource'] == review.resource.name;
    } else if (review.resource == DockerResource.containers) {
      if (review.action == 'create') {
        final id = raw['id'];
        matches =
            id is String &&
            (id.isEmpty || RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) &&
            raw['name'] == review.body!['name'] &&
            raw['image'] == review.body!['image'] &&
            raw['start_after_create'] == review.body!['start_after_create'];
      } else {
        matches =
            raw['id'] == review.target &&
            raw['action'] == review.action &&
            (review.action != 'restart-policy' ||
                raw['policy'] == review.body!['policy']);
      }
    } else if (review.resource == DockerResource.images) {
      matches =
          raw['image'] ==
          (review.action == 'create' ? review.body!['image'] : review.target);
    } else {
      matches =
          raw['name'] ==
          (review.action == 'create' ? review.body!['name'] : review.target);
    }
    if (!matches) throw const FormatException('Docker receipt target differs');
  }

  Future<void> commit(DockerReview review) => _run(() async {
    if (unknown != null || !identical(review, _review)) {
      throw const AdminAssetTargetChanged();
    }
    if (review.inspect != null) {
      final current = await _inspect(review.inspect!.id);
      if (current.fingerprint != review.inspect!.fingerprint) {
        throw const AdminAssetTargetChanged();
      }
    } else if (review.record != null) {
      await _fresh(review.record!);
    }
    if (review.inventory != null &&
        _inventory(await _list(review.resource)) != review.inventory) {
      throw const AdminAssetTargetChanged();
    }
    if (review.action == 'create' && review.resource != DockerResource.images) {
      final rows = await _list(review.resource);
      if (rows.any((v) => v.name == review.body!['name'])) {
        throw const AdminAssetTargetChanged();
      }
    }
    await _verify();
    _review = null;
    var submitted = false;
    try {
      final result = await _api(
        review.resource,
        operation: review.action,
        target: review.target,
        body: review.body,
        onSubmitted: () => submitted = true,
      );
      _guard();
      _validateReceipt(review, result);
    } catch (error) {
      if (!active) throw AdminAssetOwnerLost();
      if (error is ApiFailure && {401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      if (submitted &&
          !(error is ApiFailure && error.status >= 400 && error.status < 500)) {
        unknown = DockerUnconfirmed(
          review.resource,
          review.action,
          review.target,
        );
        throw const DockerMutationUnknown();
      }
      rethrow;
    }
  });
  Future<DockerObservation> observeUnknown() => _run(() async {
    final pending = unknown;
    if (pending == null) throw const AdminAssetTargetChanged();
    final rows = await _list(pending.resource);
    DockerInspect? detail;
    if (pending.resource == DockerResource.containers &&
        pending.target != null) {
      final found = rows
          .where((v) => pending.target!.startsWith(v.id))
          .toList();
      if (found.length == 1) {
        detail = await _inspect(pending.target!);
        detail.match(found.single);
      }
    }
    _guard();
    pending.observed = true;
    return DockerObservation(rows, detail);
  });
  void finishUnknownReview() {
    _guard();
    if (unknown?.observed != true) throw const AdminAssetTargetChanged();
    unknown = null;
  }

  Future<String> logs(DockerInspect reviewed, int tail) => _run(() async {
    final current = await _inspect(reviewed.id);
    if (current.fingerprint != reviewed.fingerprint) {
      throw const AdminAssetTargetChanged();
    }
    final raw = await _api(
      DockerResource.containers,
      operation: 'logs',
      target: reviewed.id,
      tail: tail,
    );
    final data = raw;
    if (data['id'] != reviewed.id || data['tail'] != tail) {
      throw const FormatException('Invalid Docker logs');
    }
    return dockerText(data['logs'], limit: 1024 * 1024);
  });
  Future<void> verifyContainer(
    DockerInspect expected, {
    bool requireRunning = true,
  }) => _run(() async {
    final current = await _inspect(expected.id);
    if (current.fingerprint != expected.fingerprint ||
        (requireRunning && !current.running)) {
      throw const AdminAssetTargetChanged();
    }
  });
  void cancelReview() {
    _review = null;
  }

  void cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _review = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    unknown = null;
    _credential = null;
    assets.dispose();
  }
}
