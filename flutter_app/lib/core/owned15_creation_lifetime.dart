import 'package:flutter/foundation.dart';
import 'owned15_creation_recovery_controller.dart';
import 'protected_complex_lifetime.dart';

/// Synchronous memory invalidation and genuine worker drain are distinct.
/// Root registers this owner in its existing transition/backup retirement set.
final class Owned15CreationLifetime implements ProtectedComplexOwner {
  Owned15CreationLifetime({required this.controller,required this.isCurrentScope});
  final Owned15CreationRecoveryController controller;
  final bool Function() isCurrentScope;
  final released=ValueNotifier<bool>(false);
  final _releaseMemory=<VoidCallback>{};
  final _drainers=<Future<void> Function()>{};
  bool _closed=false,_releaseFailed=false;
  Future<void>? _draining;
  Future<void> Function()? _closeRoute;
  void bindRoute(Future<void> Function()? close) {
    if(close!=null && !current)throw StateError('Creation owner retired');
    _closeRoute=close;
  }
  @override bool get current {
    try{return !_closed && controller.current && isCurrentScope();}
    catch(_){return false;}
  }
  void registerMemoryRelease(VoidCallback release) {
    if(!current) {release();return;}
    _releaseMemory.add(release);
  }
  void unregisterMemoryRelease(VoidCallback release)=>_releaseMemory.remove(release);
  void registerDrainer(Future<void> Function() drainer) {
    if(!current)throw StateError('Creation owner retired');
    _drainers.add(drainer);
  }
  void unregisterDrainer(Future<void> Function() drainer)=>_drainers.remove(drainer);
  @override Future<void> retire() {
    if(!_closed) {
      _closed=true;
      for(final release in _releaseMemory.toList(growable:false)) {
        try {release();}catch(_){_releaseFailed=true;}
      }
      _releaseMemory.clear();
      released.value=true;
    }
    return _draining??=()async{
      await Future.wait<void>([
        controller.retire(),
        if(_closeRoute!=null)Future<void>.sync(_closeRoute!),
        for(final drainer in _drainers.toList(growable:false))
          Future<void>.sync(drainer),
      ]);
      _drainers.clear();
      if(_releaseFailed)throw StateError('Creation memory release failed');
    }();
  }
}
