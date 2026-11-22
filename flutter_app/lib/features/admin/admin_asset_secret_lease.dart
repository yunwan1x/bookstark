/// An explicitly requested secret exists only during this in-memory lease.
/// Dart strings cannot be physically zeroed; close drops this object's reference.
final class AdminAssetSecretLease {
  AdminAssetSecretLease(String value, this._valid, this._onClose)
    : _value = value;
  String? _value;
  final bool Function() _valid;
  final void Function(AdminAssetSecretLease) _onClose;
  bool _closed = false;
  String? get value {
    if (!_valid()) close();
    return _value;
  }

  bool get closed => _closed;
  void close() {
    if (_closed) return;
    _closed = true;
    _value = null;
    _onClose(this);
  }

  @override
  String toString() => 'AdminAssetSecretLease';
}
