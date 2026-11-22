import 'admin_asset_migration.dart';
import 'admin_asset_secret_lease.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'admin_asset_settings.dart';
import 'admin_asset_drafts.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/go_text.dart';
import 'admin_asset_models.dart';
import 'admin_settings_repository.dart' show AdminPrincipal;

class AdminAssetOwnerLost extends StateError {
  AdminAssetOwnerLost() : super('Administrator ownership changed');
}

class AdminAssetReadSuperseded extends StateError {
  AdminAssetReadSuperseded() : super('Asset read was superseded');
}

class AdminAssetTargetChanged implements Exception {
  const AdminAssetTargetChanged();
  @override
  String toString() => 'Reviewed asset changed; no write was sent';
}

class AdminAssetOperationBusy implements Exception {
  const AdminAssetOperationBusy();
  @override
  String toString() => 'An asset operation is already in progress';
}

class AdminAssetWriteUnknown implements Exception {
  const AdminAssetWriteUnknown();
  @override
  String toString() => 'Asset operation result unknown; do not replay';
}

class AdminAssetOperationRefused implements Exception {
  const AdminAssetOperationRefused(this.status);
  final int status;
  @override
  String toString() => 'Asset operation refused';
}

enum _ReadKind { hosts, credentials, settings, secret, mutation }

class _ReadTicket {
  const _ReadTicket(
    this.kind,
    this.generation,
    this.epoch,
    this.token,
    this.owner,
  );
  final _ReadKind kind;
  final int generation, epoch;
  final String token;
  final AdminPrincipal owner;
}

/// Metadata-only catalog. No raw response or credential value is retained.
class AdminAssetsRepository {
  AdminAssetsRepository(this.client)
    : _initialToken = client.exportSession()['token'];
  final BookstarkClient client;
  String? _initialToken;
  AdminPrincipal? _principal;
  bool _disposed = false;
  bool _writeBusy = false;
  int _epoch = 0;
  final _versions = {for (final kind in _ReadKind.values) kind: 0};
  final Set<AdminAssetSecretLease> _secretLeases = {};
  AdminAssetMigrationPlan? _migrationPlan;
  AdminAssetMigrationCreated? _migrationCreated;
  String? _migrationSecretTag;
  bool _migrationCreateAttempted = false, _migrationBindAttempted = false;
  void _discardMigration() {
    _migrationPlan = null;
    _migrationCreated = null;
    _migrationSecretTag = null;
    _migrationCreateAttempted = false;
    _migrationBindAttempted = false;
  }

  String _secretTag(String value) =>
      Hmac(sha256, _identityKey).convert(utf8.encode(value)).toString();
  void _checkMigration(AdminAssetMigrationPlan plan) {
    if (!_sameSession) {
      _invalidateAll();
      throw AdminAssetOwnerLost();
    }
    if (!identical(_migrationPlan, plan) || _migrationSecretTag == null) {
      throw const AdminAssetTargetChanged();
    }
  }

  List<AdminAssetHostMetadata>? _hosts;
  List<AdminAssetCredentialMetadata>? _credentials;
  String? _hostQuery;
  AdminAssetStatus? _hostStatus;
  AdminAssetSettingsMetadata? _settings;
  String? _settingsKeyTag;
  final List<int> _identityKey = List.generate(
    32,
    (_) => Random.secure().nextInt(256),
  );

  AdminAssetSettingsMetadata? get reviewedSettings {
    if (!_sameSession) {
      _invalidateAll();
      return null;
    }
    return _settings;
  }

  (AdminAssetSettingsMetadata, String) _parseSettings(
    Map<String, Object?> raw,
  ) {
    final idle = raw['terminal_idle_timeout_seconds'];
    final scroll = raw['terminal_scrollback_lines'];
    final key = raw['credential_secret'];
    if (idle is! int ||
        idle < 1 ||
        idle > 86400 ||
        scroll is! int ||
        scroll < 500 ||
        scroll > 50000 ||
        key is! String) {
      throw const FormatException('Invalid asset settings response');
    }
    return (
      AdminAssetSettingsMetadata(
        idleSeconds: idle,
        scrollbackLines: scroll,
        encryptionEnabled: trimGoSpace(key).isNotEmpty,
      ),
      Hmac(sha256, _identityKey).convert(utf8.encode(key)).toString(),
    );
  }

  Future<AdminAssetSettingsMetadata> readSettings(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = _begin(owner, _ReadKind.settings);
    try {
      await _verify(ticket, abortTrigger);
      final raw = await client.adminAssetSettingsJson(
        abortTrigger: abortTrigger,
      );
      _check(ticket);
      final (metadata, tag) = _parseSettings(raw);
      _settings = metadata;
      _settingsKeyTag = tag;
      return metadata;
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  bool get _sameSession {
    if (_disposed || _initialToken == null || _initialToken!.isEmpty) {
      return false;
    }
    return client.exportSession()['token'] == _initialToken;
  }

  List<AdminAssetHostMetadata>? get reviewedHosts {
    if (!_sameSession) {
      _invalidateAll();
      return null;
    }
    return _hosts;
  }

  List<AdminAssetCredentialMetadata>? get reviewedCredentials {
    if (!_sameSession) {
      _invalidateAll();
      return null;
    }
    return _credentials;
  }

  String? get reviewedHostQuery => reviewedHosts == null ? null : _hostQuery;
  AdminAssetStatus? get reviewedHostStatus =>
      reviewedHosts == null ? null : _hostStatus;

  void _clear(_ReadKind kind) {
    switch (kind) {
      case _ReadKind.hosts:
        _hosts = null;
        _hostQuery = null;
        _hostStatus = null;
      case _ReadKind.credentials:
        _credentials = null;
      case _ReadKind.settings:
        _settings = null;
        _settingsKeyTag = null;
      case _ReadKind.secret:
        return;
      case _ReadKind.mutation:
        return;
    }
  }

  void _invalidateAll() {
    closeSecrets();
    _epoch++;
    _principal = null;
    for (final kind in _ReadKind.values) {
      _versions[kind] = _versions[kind]! + 1;
      _clear(kind);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initialToken = null;
    _identityKey.fillRange(0, _identityKey.length, 0);
    _invalidateAll();
    // The application owns the shared account client.
  }

  _ReadTicket _begin(AdminPrincipal owner, _ReadKind kind) {
    if (!_sameSession ||
        owner.role != 0 ||
        owner.memberId <= 0 ||
        owner.account.isEmpty) {
      _invalidateAll();
      throw AdminAssetOwnerLost();
    }
    if (_writeBusy) throw const AdminAssetOperationBusy();
    final previous = _principal;
    if (previous != null &&
        (previous.memberId != owner.memberId ||
            previous.account != owner.account)) {
      _invalidateAll();
    }
    _principal = owner;
    _versions[kind] = _versions[kind]! + 1;
    _clear(kind);
    return _ReadTicket(kind, _versions[kind]!, _epoch, _initialToken!, owner);
  }

  bool _current(_ReadTicket ticket) =>
      !_disposed &&
      ticket.epoch == _epoch &&
      ticket.generation == _versions[ticket.kind];

  void _check(_ReadTicket ticket) {
    if (!_sameSession || client.exportSession()['token'] != ticket.token) {
      _invalidateAll();
      throw AdminAssetOwnerLost();
    }
    if (!_current(ticket)) throw AdminAssetReadSuperseded();
  }

  Future<void> _verify(_ReadTicket ticket, Future<void>? abort) async {
    final profile = await client.adminAssetPrincipalJson(abortTrigger: abort);
    _check(ticket);
    if (profile['member_id'] is! int ||
        profile['member_id'] != ticket.owner.memberId ||
        profile['account'] != ticket.owner.account ||
        profile['role'] is! int ||
        profile['role'] != 0) {
      throw AdminAssetOwnerLost();
    }
  }

  void _failed(_ReadTicket ticket, Object error) {
    if (!_current(ticket)) return;
    if (error is AdminAssetOwnerLost ||
        error is ApiFailure && {401, 403}.contains(error.status)) {
      _invalidateAll();
    } else {
      _clear(ticket.kind);
    }
  }

  Future<List<AdminAssetHostMetadata>> readHosts(
    AdminPrincipal owner, {
    String query = '',
    AdminAssetStatus? status,
    Future<void>? abortTrigger,
  }) async {
    final ticket = _begin(owner, _ReadKind.hosts);
    final applied = trimGoSpace(query);
    try {
      await _verify(ticket, abortTrigger);
      final raw = await client.adminAssetHostsJson(
        query: applied,
        status: status?.value,
        abortTrigger: abortTrigger,
      );
      _check(ticket);
      final result = adminAssetMetadataList(
        raw,
        AdminAssetHostMetadata.parse,
        (row) => row.id,
      );
      _hosts = result;
      _hostQuery = applied;
      _hostStatus = status;
      return result;
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  Future<List<AdminAssetCredentialMetadata>> readCredentials(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = _begin(owner, _ReadKind.credentials);
    try {
      await _verify(ticket, abortTrigger);
      final raw = await client.adminAssetCredentialsJson(
        abortTrigger: abortTrigger,
      );
      _check(ticket);
      final result = adminAssetMetadataList(
        raw,
        AdminAssetCredentialMetadata.parse,
        (row) => row.id,
      );
      _credentials = result;
      return result;
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  void _prepareWrite(AdminPrincipal owner) {
    if (!_sameSession ||
        owner.role != 0 ||
        owner.memberId <= 0 ||
        owner.account.isEmpty) {
      _invalidateAll();
      throw AdminAssetOwnerLost();
    }
    if (_writeBusy) throw const AdminAssetOperationBusy();
    final previous = _principal;
    if (previous != null &&
        (previous.memberId != owner.memberId ||
            previous.account != owner.account)) {
      _invalidateAll();
      throw AdminAssetOwnerLost();
    }
  }

  void _catalogsRetired() {
    for (final kind in [
      _ReadKind.hosts,
      _ReadKind.credentials,
      _ReadKind.settings,
    ]) {
      _versions[kind] = _versions[kind]! + 1;
      _clear(kind);
    }
  }

  void _requireHost(AdminAssetHostMetadata expected) {
    if (!(reviewedHosts?.any(
          (row) =>
              row.id == expected.id &&
              row.reviewFingerprint == expected.reviewFingerprint,
        ) ??
        false)) {
      throw const AdminAssetTargetChanged();
    }
  }

  void _requireCredential(AdminAssetCredentialMetadata expected) {
    if (!(reviewedCredentials?.any(
          (row) =>
              row.id == expected.id &&
              row.reviewFingerprint == expected.reviewFingerprint,
        ) ??
        false)) {
      throw const AdminAssetTargetChanged();
    }
  }

  Future<List<AdminAssetHostMetadata>> _freshHosts(
    _ReadTicket ticket,
    Future<void>? abort,
  ) async {
    final raw = await client.adminAssetHostsJson(abortTrigger: abort);
    _check(ticket);
    return adminAssetMetadataList(
      raw,
      AdminAssetHostMetadata.parse,
      (row) => row.id,
    );
  }

  Future<List<AdminAssetCredentialMetadata>> _freshCredentials(
    _ReadTicket ticket,
    Future<void>? abort,
  ) async {
    final raw = await client.adminAssetCredentialsJson(abortTrigger: abort);
    _check(ticket);
    return adminAssetMetadataList(
      raw,
      AdminAssetCredentialMetadata.parse,
      (row) => row.id,
    );
  }

  Future<void> _currentHost(
    _ReadTicket ticket,
    AdminAssetHostMetadata expected,
    Future<void>? abort,
  ) async {
    final rows = await _freshHosts(ticket, abort);
    if (!rows.any(
      (row) =>
          row.id == expected.id &&
          row.reviewFingerprint == expected.reviewFingerprint,
    )) {
      throw const AdminAssetTargetChanged();
    }
  }

  Future<void> _currentCredential(
    _ReadTicket ticket,
    AdminAssetCredentialMetadata expected,
    Future<void>? abort,
  ) async {
    final rows = await _freshCredentials(ticket, abort);
    if (!rows.any(
      (row) =>
          row.id == expected.id &&
          row.reviewFingerprint == expected.reviewFingerprint,
    )) {
      throw const AdminAssetTargetChanged();
    }
  }

  Future<T> _mutate<T>(
    AdminPrincipal owner,
    Future<T> Function(_ReadTicket, void Function()) action, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
    bool keepMigrationPlan = false,
  }) async {
    closeSecrets(discardMigration: !keepMigrationPlan);
    final ticket = _begin(owner, _ReadKind.mutation);
    _writeBusy = true;
    _catalogsRetired();
    var submitted = false;
    try {
      await _verify(ticket, abortTrigger);
      final result = await action(ticket, () {
        _check(ticket);
        submitted = true;
        onSubmitted?.call();
      });
      _check(ticket);
      return result;
    } on AdminAssetOwnerLost {
      _invalidateAll();
      rethrow;
    } on ApiFailure catch (error) {
      _failed(ticket, error);
      if ({401, 403}.contains(error.status)) rethrow;
      if (submitted) {
        if ({400, 404, 429}.contains(error.status)) {
          throw AdminAssetOperationRefused(error.status);
        }
        throw const AdminAssetWriteUnknown();
      }
      rethrow;
    } catch (_) {
      if (submitted) throw const AdminAssetWriteUnknown();
      rethrow;
    } finally {
      _catalogsRetired();
      _writeBusy = false;
    }
  }

  Future<AdminAssetHostMetadata> createHost(
    AdminPrincipal owner,
    AdminAssetHostDraft draft,
    AdminAssetCredentialMetadata chosen, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireCredential(chosen);
    if (draft.credentialId != chosen.id) throw const AdminAssetDraftInvalid();
    final body = draft.toRequest(creating: true);
    return _mutate(
      owner,
      (ticket, sent) async {
        final previous = await _freshHosts(ticket, abortTrigger);
        await _currentCredential(ticket, chosen, abortTrigger);
        final raw = await client.adminSaveAssetHostJson(
          body,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        final result = AdminAssetHostMetadata.parse(raw);
        if (previous.any((row) => row.id == result.id)) {
          throw const FormatException(
            'Host creation returned a pre-existing identifier',
          );
        }
        return result;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetHostMetadata> updateHost(
    AdminPrincipal owner,
    AdminAssetHostMetadata reviewed,
    AdminAssetHostDraft draft, {
    AdminAssetCredentialMetadata? chosen,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireHost(reviewed);
    final body = draft.toRequest(creating: false);
    if (draft.credentialId == 0) {
      if (reviewed.credentialId != 0 ||
          draft.username != reviewed.username ||
          draft.auth != reviewed.auth) {
        throw const AdminAssetDraftInvalid();
      }
    } else {
      if (chosen == null || chosen.id != draft.credentialId) {
        throw const AdminAssetDraftInvalid();
      }
      _requireCredential(chosen);
    }
    return _mutate(
      owner,
      (ticket, sent) async {
        await _currentHost(ticket, reviewed, abortTrigger);
        if (chosen != null) {
          await _currentCredential(ticket, chosen, abortTrigger);
        }
        final raw = await client.adminSaveAssetHostJson(
          body,
          id: reviewed.id,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        final result = AdminAssetHostMetadata.parse(raw);
        if (result.id != reviewed.id) {
          throw const FormatException(
            'Host update returned a different identifier',
          );
        }
        return result;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetCredentialMetadata> createCredential(
    AdminPrincipal owner,
    AdminAssetCredentialDraft draft,
    String replacement, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    final body = draft.toRequest(creating: true, replacement: replacement);
    return _mutate(
      owner,
      (ticket, sent) async {
        final previous = await _freshCredentials(ticket, abortTrigger);
        final raw = await client.adminSaveAssetCredentialJson(
          body,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        final result = AdminAssetCredentialMetadata.parse(raw);
        if (previous.any((row) => row.id == result.id)) {
          throw const FormatException(
            'Credential creation returned a pre-existing identifier',
          );
        }
        return result;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetCredentialMetadata> updateCredential(
    AdminPrincipal owner,
    AdminAssetCredentialMetadata reviewed,
    AdminAssetCredentialDraft draft, {
    String? replacement,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireCredential(reviewed);
    if (draft.auth != reviewed.auth && replacement == null) {
      throw const AdminAssetDraftInvalid();
    }
    final body = draft.toRequest(creating: false, replacement: replacement);
    return _mutate(
      owner,
      (ticket, sent) async {
        await _currentCredential(ticket, reviewed, abortTrigger);
        final raw = await client.adminSaveAssetCredentialJson(
          body,
          id: reviewed.id,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        final result = AdminAssetCredentialMetadata.parse(raw);
        if (result.id != reviewed.id) {
          throw const FormatException(
            'Credential update returned a different identifier',
          );
        }
        return result;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetDeleteReceipt> deleteHost(
    AdminPrincipal owner,
    AdminAssetHostMetadata reviewed, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireHost(reviewed);
    return _mutate(
      owner,
      (ticket, sent) async {
        await _currentHost(ticket, reviewed, abortTrigger);
        await client.adminDeleteAssetRecordJson(
          'ssh-hosts',
          reviewed.id,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        return AdminAssetDeleteReceipt('ssh-hosts', reviewed.id);
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetDeleteReceipt> deleteCredential(
    AdminPrincipal owner,
    AdminAssetCredentialMetadata reviewed, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireCredential(reviewed);
    return _mutate(
      owner,
      (ticket, sent) async {
        await _currentCredential(ticket, reviewed, abortTrigger);
        await client.adminDeleteAssetRecordJson(
          'credentials',
          reviewed.id,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        return AdminAssetDeleteReceipt('credentials', reviewed.id);
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetConnectionReceipt> testHost(
    AdminPrincipal owner,
    AdminAssetHostMetadata reviewed, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _requireHost(reviewed);
    return _mutate(
      owner,
      (ticket, sent) async {
        await _currentHost(ticket, reviewed, abortTrigger);
        final raw = await client.adminTestAssetHostJson(
          reviewed.id,
          abortTrigger: abortTrigger,
          onSubmitted: sent,
        );
        _check(ticket);
        return AdminAssetConnectionReceipt.parse(raw);
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  Future<AdminAssetSettingsReceipt> saveSettings(
    AdminPrincipal owner,
    AdminAssetSettingsMetadata reviewed, {
    required int idleSeconds,
    required int scrollbackLines,
    required AdminAssetKeyAction action,
    String? replacement,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    if (!identical(reviewedSettings, reviewed) || _settingsKeyTag == null) {
      throw const AdminAssetTargetChanged();
    }
    if (idleSeconds < 1 ||
        idleSeconds > 86400 ||
        scrollbackLines < 500 ||
        scrollbackLines > 50000 ||
        (action == AdminAssetKeyAction.replace
            ? replacement == null || trimGoSpace(replacement).isEmpty
            : replacement != null)) {
      throw const AdminAssetDraftInvalid();
    }
    final expectedTag = _settingsKeyTag!;
    return _mutate(
      owner,
      (ticket, sent) async {
        final raw = await client.adminAssetSettingsJson(
          abortTrigger: abortTrigger,
        );
        _check(ticket);
        final (current, tag) = _parseSettings(raw);
        if (current.idleSeconds != reviewed.idleSeconds ||
            current.scrollbackLines != reviewed.scrollbackLines ||
            tag != expectedTag) {
          throw const AdminAssetTargetChanged();
        }
        if (action == AdminAssetKeyAction.keep) {
          await client.adminAssetTerminalPolicyJson(
            idleSeconds: idleSeconds,
            scrollbackLines: scrollbackLines,
            abortTrigger: abortTrigger,
            onSubmitted: sent,
          );
          _check(ticket);
        } else {
          final hosts = await _freshHosts(ticket, abortTrigger);
          final credentials = await _freshCredentials(ticket, abortTrigger);
          final ids = credentials.map((row) => row.id).toSet();
          final invalid = hosts
              .where(
                (row) =>
                    row.credentialId == 0 || !ids.contains(row.credentialId),
              )
              .map((row) => row.id)
              .toList(growable: false);
          if (invalid.isNotEmpty) {
            throw AdminAssetLegacyMigrationRequired(List.unmodifiable(invalid));
          }
          final newKey = action == AdminAssetKeyAction.disable
              ? ''
              : trimGoSpace(replacement!);
          final saved = await client.adminAssetSettingsJson(
            update: {
              'terminal_idle_timeout_seconds': idleSeconds,
              'terminal_scrollback_lines': scrollbackLines,
              'credential_secret': newKey,
            },
            abortTrigger: abortTrigger,
            onSubmitted: sent,
          );
          _check(ticket);
          final (accepted, acceptedTag) = _parseSettings(saved);
          if (accepted.idleSeconds != idleSeconds ||
              accepted.scrollbackLines != scrollbackLines ||
              acceptedTag !=
                  Hmac(
                    sha256,
                    _identityKey,
                  ).convert(utf8.encode(newKey)).toString()) {
            throw const FormatException('Unexpected asset settings receipt');
          }
        }
        return AdminAssetSettingsReceipt(action, idleSeconds, scrollbackLines);
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
    );
  }

  /// Called by page lifecycle handling before hiding, backgrounding or leaving.
  void closeSecrets({bool discardMigration = true}) {
    if (discardMigration) _discardMigration();
    _versions[_ReadKind.secret] = _versions[_ReadKind.secret]! + 1;
    for (final lease in _secretLeases.toList(growable: false)) {
      lease.close();
    }
  }

  AdminAssetSecretLease _secretLease(String value) {
    final lease = AdminAssetSecretLease(
      value,
      () => _sameSession,
      (lease) => _secretLeases.remove(lease),
    );
    _secretLeases.add(lease);
    return lease;
  }

  Future<AdminAssetSecretLease> revealCredential(
    AdminPrincipal owner,
    AdminAssetCredentialMetadata reviewed, {
    Future<void>? abortTrigger,
  }) async {
    _prepareWrite(owner);
    _requireCredential(reviewed);
    closeSecrets();
    final ticket = _begin(owner, _ReadKind.secret);
    try {
      await _verify(ticket, abortTrigger);
      final raw = await client.adminAssetCredentialsJson(
        abortTrigger: abortTrigger,
      );
      _check(ticket);
      final rows = adminAssetMetadataList(
        raw,
        AdminAssetCredentialMetadata.parse,
        (row) => row.id,
      );
      if (!rows.any(
        (row) =>
            row.id == reviewed.id &&
            row.reviewFingerprint == reviewed.reviewFingerprint,
      )) {
        throw const AdminAssetTargetChanged();
      }
      final data = raw['data'] as List;
      final target = data.cast<Map>().singleWhere(
        (row) => row['id'] == reviewed.id,
      );
      final value = target['credential'];
      if (value is! String) {
        throw const FormatException('Credential secret was not supplied');
      }
      return _secretLease(value);
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  Future<AdminAssetSecretLease> revealSettingsKey(
    AdminPrincipal owner,
    AdminAssetSettingsMetadata reviewed, {
    Future<void>? abortTrigger,
  }) async {
    _prepareWrite(owner);
    if (!identical(reviewedSettings, reviewed) || _settingsKeyTag == null) {
      throw const AdminAssetTargetChanged();
    }
    final expected = _settingsKeyTag!;
    closeSecrets();
    final ticket = _begin(owner, _ReadKind.secret);
    try {
      await _verify(ticket, abortTrigger);
      final raw = await client.adminAssetSettingsJson(
        abortTrigger: abortTrigger,
      );
      _check(ticket);
      final (metadata, tag) = _parseSettings(raw);
      if (tag != expected ||
          metadata.idleSeconds != reviewed.idleSeconds ||
          metadata.scrollbackLines != reviewed.scrollbackLines) {
        throw const AdminAssetTargetChanged();
      }
      return _secretLease(raw['credential_secret'] as String);
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  Future<String> _legacyPlain(
    _ReadTicket ticket,
    AdminAssetHostMetadata expected,
    Future<void>? abort,
  ) async {
    final raw = await client.adminAssetHostsJson(abortTrigger: abort);
    _check(ticket);
    final rows = adminAssetMetadataList(
      raw,
      AdminAssetHostMetadata.parse,
      (row) => row.id,
    );
    if (expected.credentialId != 0 ||
        !rows.any(
          (row) =>
              row.id == expected.id &&
              row.credentialId == 0 &&
              row.reviewFingerprint == expected.reviewFingerprint,
        )) {
      throw const AdminAssetTargetChanged();
    }
    final target = (raw['data'] as List).cast<Map>().singleWhere(
      (row) => row['id'] == expected.id,
    );
    final secret = target['credential'];
    if (secret is! String || trimGoSpace(secret).isEmpty) {
      throw const AdminAssetDraftInvalid();
    }
    return secret;
  }

  Future<AdminAssetMigrationPlan> prepareLegacyMigration(
    AdminPrincipal owner,
    AdminAssetHostMetadata reviewed,
    String credentialName, {
    Future<void>? abortTrigger,
  }) async {
    _prepareWrite(owner);
    _requireHost(reviewed);
    final name = trimGoSpace(credentialName);
    if (reviewed.credentialId != 0 || name.isEmpty) {
      throw const AdminAssetDraftInvalid();
    }
    closeSecrets();
    final ticket = _begin(owner, _ReadKind.secret);
    try {
      await _verify(ticket, abortTrigger);
      final secret = await _legacyPlain(ticket, reviewed, abortTrigger);
      await _freshCredentials(ticket, abortTrigger);
      _check(ticket);
      final plan = AdminAssetMigrationPlan(reviewed, name);
      _migrationPlan = plan;
      _migrationSecretTag = _secretTag(secret);
      return plan;
    } catch (error) {
      _failed(ticket, error);
      rethrow;
    }
  }

  Future<AdminAssetMigrationCreated> createLegacyMigrationCredential(
    AdminPrincipal owner,
    AdminAssetMigrationPlan plan, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _checkMigration(plan);
    if (_migrationCreateAttempted) throw const AdminAssetTargetChanged();
    return _mutate(
      owner,
      (ticket, sent) async {
        _checkMigration(plan);
        final secret = await _legacyPlain(ticket, plan.host, abortTrigger);
        _checkMigration(plan);
        if (_secretTag(secret) != _migrationSecretTag) {
          throw const AdminAssetTargetChanged();
        }
        final previous = await _freshCredentials(ticket, abortTrigger);
        _checkMigration(plan);
        final draft = AdminAssetCredentialDraft(
          name: plan.credentialName,
          username: plan.host.username,
          auth: plan.host.auth,
        );
        final raw = await client.adminSaveAssetCredentialJson(
          draft.toRequest(creating: true, replacement: secret),
          abortTrigger: abortTrigger,
          onSubmitted: () {
            _checkMigration(plan);
            _migrationCreateAttempted = true;
            sent();
          },
        );
        _check(ticket);
        _checkMigration(plan);
        final credential = AdminAssetCredentialMetadata.parse(raw);
        final returnedSecret = raw['credential'];
        if (previous.any((row) => row.id == credential.id) ||
            credential.name != plan.credentialName ||
            credential.username != plan.host.username ||
            credential.auth != plan.host.auth ||
            returnedSecret is! String ||
            _secretTag(returnedSecret) != _migrationSecretTag) {
          throw const FormatException('Invalid migration creation receipt');
        }
        // Binding performs a separate fresh read of this exact ID and bytes.
        final created = AdminAssetMigrationCreated(plan, credential);
        _migrationCreated = created;
        return created;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
      keepMigrationPlan: true,
    );
  }

  Future<AdminAssetMigrationBound> bindLegacyMigration(
    AdminPrincipal owner,
    AdminAssetMigrationCreated created, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    _prepareWrite(owner);
    _checkMigration(created.plan);
    if (!identical(_migrationCreated, created) || _migrationBindAttempted) {
      throw const AdminAssetTargetChanged();
    }
    return _mutate(
      owner,
      (ticket, sent) async {
        final plan = created.plan;
        _checkMigration(plan);
        final oldSecret = await _legacyPlain(ticket, plan.host, abortTrigger);
        if (_secretTag(oldSecret) != _migrationSecretTag) {
          throw const AdminAssetTargetChanged();
        }
        final rawCredentials = await client.adminAssetCredentialsJson(
          abortTrigger: abortTrigger,
        );
        _check(ticket);
        _checkMigration(plan);
        final rows = adminAssetMetadataList(
          rawCredentials,
          AdminAssetCredentialMetadata.parse,
          (row) => row.id,
        );
        if (!rows.any(
          (row) =>
              row.id == created.credential.id &&
              row.reviewFingerprint == created.credential.reviewFingerprint,
        )) {
          throw const AdminAssetTargetChanged();
        }
        final secret = (rawCredentials['data'] as List).cast<Map>().singleWhere(
          (row) => row['id'] == created.credential.id,
        )['credential'];
        if (secret is! String || _secretTag(secret) != _migrationSecretTag) {
          throw const AdminAssetTargetChanged();
        }
        final body = Map<String, Object?>.of(
          AdminAssetHostDraft.fromMetadata(
            plan.host,
          ).toRequest(creating: false),
        );
        body['credential_id'] = created.credential.id;
        final raw = await client.adminSaveAssetHostJson(
          body,
          id: plan.host.id,
          abortTrigger: abortTrigger,
          onSubmitted: () {
            _checkMigration(plan);
            _migrationBindAttempted = true;
            sent();
          },
        );
        _check(ticket);
        _checkMigration(plan);
        final host = AdminAssetHostMetadata.parse(raw);
        if (host.id != plan.host.id ||
            host.credentialId != created.credential.id) {
          throw const FormatException('Invalid migration binding receipt');
        }
        final result = AdminAssetMigrationBound(created, host);
        _discardMigration();
        return result;
      },
      abortTrigger: abortTrigger,
      onSubmitted: onSubmitted,
      keepMigrationPlan: true,
    );
  }
}
