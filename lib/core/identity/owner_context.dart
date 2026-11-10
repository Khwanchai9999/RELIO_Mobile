import 'dart:async';

class OwnerChangedException implements Exception {
  const OwnerChangedException();
  @override
  String toString() => 'Owner context changed';
}

class OwnerSnapshot {
  const OwnerSnapshot(this.userId, this.generation);
  final String? userId;
  final int generation;
}

/// ผูกงาน async กับ owner เดิม รวม A → B → A โดยไม่อาศัยชื่อหรือ device ID
class OwnerContext {
  OwnerContext(this.provider, [Stream<Object?>? source]) {
    _userId = provider?.call();
    _subscription = source?.listen((_) => _refresh());
  }

  final String? Function()? provider;
  final Object _zoneKey = Object();
  final _changes = StreamController<Object?>.broadcast(sync: true);
  StreamSubscription<Object?>? _subscription;
  String? _userId;
  int _generation = 0;
  Stream<Object?> get changes => _changes.stream;

  void _refresh({bool force = false}) {
    final next = provider?.call();
    if (!force && next == _userId) return;
    _userId = next;
    _generation++;
    _changes.add(_generation);
  }

  OwnerSnapshot capture() {
    _refresh();
    final inherited = Zone.current[_zoneKey];
    if (inherited is OwnerSnapshot) return inherited;
    return OwnerSnapshot(_userId, _generation);
  }

  bool isCurrent(OwnerSnapshot snapshot) {
    _refresh();
    return snapshot.generation == _generation && snapshot.userId == _userId;
  }

  // ตรวจ owner ก่อนและหลังงาน async เพื่อไม่ให้ผลลัพธ์ของบัญชีเดิมถูกใช้หลังสลับบัญชี
  Future<T> run<T>(Future<T> Function() action) async {
    final snapshot = capture();
    requireCurrent(snapshot);
    return runZoned(() async {
      final result = await action();
      requireCurrent(snapshot);
      return result;
    }, zoneValues: {_zoneKey: snapshot});
  }

  void requireCurrent(OwnerSnapshot snapshot) {
    if (!isCurrent(snapshot)) throw const OwnerChangedException();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
  }
}
