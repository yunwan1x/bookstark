import 'dart:async';
import 'dart:convert';
import 'local_backup_codec.dart';
import 'package:flutter/services.dart';
import 'local_generation_state.dart';

typedef LocalDataControlInvoke =
    Future<Object?> Function(String method, Map<String, Object?>? arguments);

class LocalControlUnconfirmed implements Exception {
  const LocalControlUnconfirmed(this.action);
  final String action;
  @override
  String toString() => 'Local data operation needs read-only review';
}

class LocalDataControlState {
  LocalDataControlState._({
    required this.pointerRaw,
    required this.intentRaw,
    required this.currentRetentionRaw,
    required this.sourceRetentionRaw,
    required this.observation,
  });
  final String? pointerRaw, intentRaw, currentRetentionRaw, sourceRetentionRaw;
  final LocalGenerationObservation observation;
  String get pointerSHA256 => localPointerSHA256(pointerRaw);
}

class LocalAppliedFileReview {
  LocalAppliedFileReview._(this.manifest, this.manifestRaw);
  final LocalBackupManifest manifest;
  final String manifestRaw;
}

class LocalRetentionCatalog {
  LocalRetentionCatalog._(this.entries, this.unknown, this.overflow);
  final List<LocalRetention> entries;
  final int unknown;
  final bool overflow;
}

class LocalControlReceipt {
  LocalControlReceipt._(this.action, this.id, this.state);
  final String action, id;
  final LocalDataControlState state;
}

/// Native mutations always retain their durable intent on uncertain results.
/// A read-only state observation is deliberately a different type from a receipt.
class NativeLocalDataControl {
  NativeLocalDataControl({
    LocalDataControlInvoke? invoke,
    this.timeout = const Duration(minutes: 5),
  }) : _invoke =
           invoke ??
           ((method, args) => channel.invokeMethod<Object?>(method, args)) {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Positive native timeout required');
    }
  }
  static const channel = MethodChannel('bookstark/local_data_control');
  final LocalDataControlInvoke _invoke;
  final Duration timeout;

  Future<Object?> _call(String method, [Map<String, Object?>? arguments]) =>
      _invoke(method, arguments).timeout(timeout);

  Future<LocalDataControlState> readState() async =>
      _state(await _call('readState'));

  /// A read-only full native byte check, deliberately not a durable receipt.
  Future<LocalAppliedFileReview> reviewApplied(
    LocalRestoreIntent intent,
  ) async {
    final value = _map(await _call('reviewApplied', _intentArguments(intent)), {
      'format',
      'operationId',
      'pointerSHA256',
      'intentSHA256',
      'manifestRaw',
      'metadataOnly',
    });
    final raw = value['manifestRaw'];
    if (value['operationId'] != intent.operationId ||
        value['pointerSHA256'] != localPointerSHA256(intent.targetPointerRaw) ||
        value['intentSHA256'] != localPointerSHA256(intent.encode()) ||
        value['metadataOnly'] != true ||
        raw is! String ||
        utf8.encode(raw).length > LocalBackupManifest.maxManifestBytes) {
      throw const FormatException('Unbound applied file review');
    }
    return LocalAppliedFileReview._(
      LocalBackupManifest.fromJson(jsonDecode(raw)),
      raw,
    );
  }

  Future<LocalRetentionCatalog> listRetained() async {
    final value = _map(await _call('listRetained'), {
      'format',
      'retentions',
      'unknown',
      'overflow',
      'metadataOnly',
    });
    final rows = value['retentions'], unknown = value['unknown'];
    if (value['metadataOnly'] != true ||
        rows is! List ||
        rows.length > 256 ||
        unknown is! int ||
        unknown < 0 ||
        unknown > 256 ||
        value['overflow'] is! bool) {
      throw const FormatException('Invalid retained backup catalog');
    }
    final entries = <LocalRetention>[];
    final seen = <String>{};
    for (final raw in rows) {
      if (raw is! String) {
        throw const FormatException('Invalid retained backup entry');
      }
      final entry = LocalRetention.parse(raw);
      if (!seen.add(entry.id)) {
        throw const FormatException('Duplicate retained backup identity');
      }
      entries.add(entry);
    }
    return LocalRetentionCatalog._(
      List.unmodifiable(entries),
      unknown,
      value['overflow'] as bool,
    );
  }

  Future<int> availableBytes() async {
    final value = _map(await _call('space'), {'format', 'availableBytes'});
    final bytes = value['availableBytes'];
    if (bytes is! int || bytes < 0) {
      throw const FormatException('Invalid local storage capacity metadata');
    }
    return bytes;
  }

  Future<LocalControlReceipt> prepare(LocalRestoreIntent intent) => _mutate(
    'prepareRestore',
    {'intentRaw': intent.encode()},
    'prepared',
    intent.operationId,
    (state) {
      if (state.pointerRaw != intent.sourcePointerRaw ||
          state.intentRaw != intent.encode() ||
          state.observation.phase != LocalGenerationPhase.prepared) {
        throw const FormatException('Prepared local intent is not bound');
      }
    },
  );

  Future<LocalControlReceipt> commit(LocalRestoreIntent intent) => _mutate(
    'commitRestore',
    _intentArguments(intent),
    'switched',
    intent.operationId,
    (state) {
      if (state.pointerRaw != intent.targetPointerRaw ||
          state.intentRaw != intent.encode() ||
          state.observation.phase != LocalGenerationPhase.switched) {
        throw const FormatException('Local activation receipt is not bound');
      }
    },
  );

  Future<LocalControlReceipt> acknowledgeApplied(LocalRestoreIntent intent) =>
      _mutate(
        'acknowledgeApplied',
        _intentArguments(intent),
        'acknowledged',
        intent.operationId,
        (state) {
          if (state.pointerRaw != intent.targetPointerRaw ||
              state.intentRaw != null ||
              state.observation.needsReview) {
            throw const FormatException('Local acknowledgement is not bound');
          }
        },
      );

  Future<LocalControlReceipt> finishUnapplied(LocalRestoreIntent intent) =>
      _mutate(
        'finishUnapplied',
        _intentArguments(intent),
        'finished-unapplied',
        intent.operationId,
        (state) {
          if (state.pointerRaw != intent.sourcePointerRaw ||
              state.intentRaw != null ||
              state.observation.phase != LocalGenerationPhase.retained ||
              state.observation.currentRetention?.id != intent.retainedId ||
              state.observation.currentRetention?.manifestSHA256 !=
                  intent.retainedManifestSHA256) {
            throw const FormatException('Unapplied local intent is not bound');
          }
        },
      );

  Future<LocalControlReceipt> reenterUnchangedSource(
    LocalDataControlState reviewed,
  ) {
    final retention = reviewed.observation.currentRetention;
    if (!reviewed.observation.canReenterUnchangedSource || retention == null) {
      throw StateError('A retained, unchanged source must be reviewed first');
    }
    return _mutate(
      'reenterUnchangedSource',
      {
        'sourcePointerSHA256': reviewed.pointerSHA256,
        'retainedId': retention.id,
        'retainedManifestSHA256': retention.manifestSHA256,
      },
      'reentered',
      retention.id,
      (state) {
        if (state.pointerRaw != reviewed.pointerRaw ||
            state.intentRaw != null ||
            state.observation.needsReview) {
          throw const FormatException('Local source reentry is not bound');
        }
      },
    );
  }

  Future<LocalControlReceipt> reenterReadySource(
    LocalDataControlState reviewed,
  ) {
    if (reviewed.observation.needsReview) {
      throw StateError('Unchanged ready source must be reviewed first');
    }
    return _mutate(
      'reenterReadySource',
      {'sourcePointerSHA256': reviewed.pointerSHA256},
      'reentered-ready',
      reviewed.pointerSHA256,
      (state) {
        if (state.pointerRaw != reviewed.pointerRaw ||
            state.observation.needsReview) {
          throw const FormatException('Ready source reentry is not bound');
        }
      },
    );
  }

  Future<LocalControlReceipt> discardCandidate(String generation) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(generation)) {
      throw const FormatException('Invalid candidate generation identity');
    }
    return _mutate(
      'discardCandidate',
      {'generation': generation},
      'discarded',
      generation,
      (state) {
        if (state.observation.pointer?.generation == generation ||
            (state.observation.intent != null &&
                LocalGenerationPointer.parse(
                      state.observation.intent!.targetPointerRaw,
                    ).generation ==
                    generation)) {
          throw const FormatException(
            'Referenced generation cannot be discarded',
          );
        }
      },
    );
  }

  Map<String, Object?> _intentArguments(LocalRestoreIntent intent) => {
    'operationId': intent.operationId,
    'intentSHA256': localPointerSHA256(intent.encode()),
  };

  Future<LocalControlReceipt> _mutate(
    String method,
    Map<String, Object?> arguments,
    String action,
    String id,
    void Function(LocalDataControlState) validate,
  ) async {
    try {
      final reply = _map(await _call(method, arguments), {
        'format',
        'action',
        'id',
        'durable',
        'state',
      });
      if (reply['action'] != action ||
          reply['id'] != id ||
          reply['durable'] != true) {
        throw const FormatException('Unbound local control receipt');
      }
      final state = _state(reply['state']);
      validate(state);
      return LocalControlReceipt._(action, id, state);
    } catch (_) {
      // No retry, read-back, file cleanup, compensation or acknowledgement here.
      throw LocalControlUnconfirmed(action);
    }
  }

  Map<String, Object?> _map(Object? value, Set<String> keys) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid local control reply');
    }
    final result = value.cast<String, Object?>();
    if (result.length != keys.length ||
        !result.keys.toSet().containsAll(keys) ||
        result['format'] is! int ||
        result['format'] != 1) {
      throw const FormatException('Unsupported local control reply');
    }
    return result;
  }

  LocalDataControlState _state(Object? value) {
    final state = _map(value, {
      'format',
      'pointerRaw',
      'intentRaw',
      'currentRetentionRaw',
      'sourceRetentionRaw',
      'metadataOnly',
    });
    if (state['metadataOnly'] != true) {
      throw const FormatException('Unexpected local control content');
    }
    String? field(String name) {
      final raw = state[name];
      if (raw == null) return null;
      if (raw is! String || raw.length > 16384) {
        throw const FormatException('Invalid local control metadata');
      }
      return raw;
    }

    final pointer = field('pointerRaw'), intent = field('intentRaw');
    final current = field('currentRetentionRaw'),
        source = field('sourceRetentionRaw');
    final observation = LocalGenerationObservation.inspect(
      pointerRaw: pointer,
      intentRaw: intent,
      currentRetentionRaw: current,
      sourceRetentionRaw: source,
    );
    return LocalDataControlState._(
      pointerRaw: pointer,
      intentRaw: intent,
      currentRetentionRaw: current,
      sourceRetentionRaw: source,
      observation: observation,
    );
  }
}
