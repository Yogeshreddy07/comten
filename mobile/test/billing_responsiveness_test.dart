import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/billing/model/billing_entry.dart';
import 'package:frontend/features/billing/model/update_billing_status_request.dart';
import 'package:frontend/features/billing/repository/billing_repository.dart';
import 'package:frontend/features/billing/viewmodel/billing_view_model.dart';

class Billing extends BillingRepository {
  final reads = <Completer<ApiResult>>[];
  final writes = <Completer<ApiResult>>[];
  @override
  Future<ApiResult> getBillingList() {
    final result = Completer<ApiResult>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<ApiResult> updateBillingStatus(
    int id,
    UpdateBillingStatusRequest request,
  ) {
    final result = Completer<ApiResult>();
    writes.add(result);
    return result.future;
  }
}

BillingEntry row(String status) => BillingEntry.fromJson({
  'moduleId': 1,
  'projectId': 1,
  'status': status,
  'stage': 'PENDING',
});
ApiResult loaded(String status) =>
    ApiResult(success: true, message: '', data: [row(status)]);
const change = UpdateBillingStatusRequest(
  spocName: '',
  status: 'INVOICE_RAISED',
);

void main() {
  test('refresh keeps loaded rows and combines simultaneous fetches', () async {
    final repository = Billing();
    final model = BillingViewModel(repository: repository);
    var fetch = model.fetchBillingList();
    repository.reads.last.complete(loaded('PART_PAYMENT_RECEIVED'));
    await fetch;
    fetch = model.fetchBillingList();
    final joined = model.fetchBillingList();
    expect(identical(fetch, joined), isTrue);
    expect(repository.reads.length, 2);
    expect(model.loadState, BillingLoadState.success);
    expect(model.entries.single.status, 'PART_PAYMENT_RECEIVED');
    expect(model.isRefreshing, isTrue);
    repository.reads.last.complete(
      ApiResult(success: false, message: 'Permission denied'),
    );
    await fetch;
    expect(model.entries, isEmpty);
    expect(model.loadState, BillingLoadState.error);
    expect(model.isRefreshing, isFalse);
    model.dispose();
  });

  test('previous-session responses cannot populate a new session', () async {
    final repository = Billing();
    final model = BillingViewModel(repository: repository);
    final old = model.fetchBillingList();
    model.reset();
    final fresh = model.fetchBillingList();
    repository.reads.last.complete(loaded('INVOICE_RAISED'));
    await fresh;
    repository.reads.first.complete(loaded('PART_PAYMENT_RECEIVED'));
    await old;
    expect(model.entries.single.status, 'INVOICE_RAISED');
    model.dispose();
  });

  test(
    'stale list cannot erase a confirmed save; duplicate saves are refused',
    () async {
      final repository = Billing();
      final model = BillingViewModel(repository: repository);
      final first = model.fetchBillingList();
      repository.reads.first.complete(loaded('PART_PAYMENT_RECEIVED'));
      await first;
      final stale = model.fetchBillingList();
      final save = model.updateBillingStatus(1, change);
      expect((await model.updateBillingStatus(1, change)).success, isFalse);
      expect(repository.writes.length, 1);
      repository.writes.single.complete(
        ApiResult(success: true, message: '', data: row('INVOICE_RAISED')),
      );
      expect((await save).success, isTrue);
      repository.reads.last.complete(loaded('PART_PAYMENT_RECEIVED'));
      await stale;
      expect(model.entries.single.status, 'INVOICE_RAISED');
      expect(model.isSaving, isFalse);
      model.dispose();
    },
  );

  test(
    'thrown fetch/save errors release progress and disposed responses are ignored',
    () async {
      final repository = Billing();
      final model = BillingViewModel(repository: repository);
      var fetch = model.fetchBillingList();
      repository.reads.last.completeError(StateError('Offline'));
      await fetch;
      expect(model.isRefreshing, isFalse);
      expect(model.loadState, BillingLoadState.error);
      final save = model.updateBillingStatus(1, change);
      repository.writes.last.completeError(StateError('Offline'));
      expect((await save).success, isFalse);
      expect(model.isSaving, isFalse);
      fetch = model.fetchBillingList();
      model.dispose();
      repository.reads.last.complete(loaded('INVOICE_RAISED'));
      await fetch;
    },
  );
}
