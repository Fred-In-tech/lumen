import 'dart:async';
import 'dart:collection';

import 'package:lumen_core/lumen_core.dart';

import '../support.dart';

/// Global semaphore for upstream Claude calls: at most [concurrency] in
/// flight and [maxQueue] waiting; beyond that callers get 429.
class UpstreamGate {
  UpstreamGate({required this.concurrency, required this.maxQueue});

  final int concurrency;
  final int maxQueue;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  int get active => _active;
  int get queued => _waiting.length;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= concurrency) {
      if (_waiting.length >= maxQueue) {
        throw const GatewayException(
          GatewayErrorCode.rateLimited,
          'Gateway is busy; retry shortly',
          retryAfter: Duration(seconds: 2),
          details: {'reason': 'upstream_queue_full'},
        );
      }
      final ticket = Completer<void>();
      _waiting.add(ticket);
      await ticket.future;
    } else {
      _active++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        // Hand the slot straight to the next waiter (active count unchanged).
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
