import 'dart:async';
import 'dart:collection';

/// Shares document reads only for the lifetime of one operation. Never reuses
/// authorization or records across requests, accounts, or mutations.
class RequestReads<T> {
  RequestReads(this.load, {this.concurrency = 8}) {
    if (concurrency < 1) throw ArgumentError.value(concurrency);
  }

  final Future<T> Function(String path) load;
  final int concurrency;
  final _reads = <String, Future<T>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;

  Future<T> read(String path) => _reads.putIfAbsent(path, () => _load(path));

  Future<T> _load(String path) async {
    if (_active >= concurrency) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await load(path);
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
