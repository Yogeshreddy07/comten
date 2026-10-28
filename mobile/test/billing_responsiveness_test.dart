import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/billing/model/billing_entry.dart';
import 'package:frontend/features/billing/model/update_billing_status_request.dart';
import 'package:frontend/features/billing/repository/billing_repository.dart';
import 'package:frontend/features/billing/viewmodel/billing_view_model.dart';

const original = BillingEntry(
  moduleId: 1,
  moduleName: 'Synthetic',
  projectId: 10,
  projectCode: 'SYN',
  projectName: 'Synthetic',
  status: 'INVOICE_RAISED',
);
const confirmed = BillingEntry(
  moduleId: 1,
  moduleName: 'Synthetic',
  projectId: 10,
  projectCode: 'SYN',
  projectName: 'Synthetic',
  status: 'FULL_PAYMENT_RECEIVED',
);
const request = UpdateBillingStatusRequest(
  spocName: 'Synthetic',
  status: 'FULL_PAYMENT_RECEIVED',
);
ApiResult rows() => ApiResult(success: true, message: '', data: [original]);

class BillingFixture extends BillingRepository {
  Future<ApiResult>? read;
  Future<ApiResult>? write;
  int reads = 0;
  int writes = 0;
  @override
  Future<ApiResult> getBillingList() {
    reads++;
    return read ?? Future.value(rows());
  }

  @override
  Future<ApiResult> updateBillingStatus(
    int moduleId,
    UpdateBillingStatusRequest request,
  ) {
    writes++;
    return write ??
        Future.value(ApiResult(success: true, message: '', data: confirmed));
  }
}

void main() {
  test(
    'slow refresh retains content and simultaneous loads share one request',
    () async {
      final repository = BillingFixture();
      final vm = BillingViewModel(repository: repository);
      await vm.fetchBillingList();
      final gate = Completer<ApiResult>();
      repository.read = gate.future;
      final first = vm.fetchBillingList();
      final second = vm.fetchBillingList();
      expect(identical(first, second), isTrue);
      expect(repository.reads, 2);
      expect(vm.loadState, BillingLoadState.success);
      expect(vm.entries, [original]);
      gate.complete(rows());
      await first;
    },
  );

  test(
    'reset prevents a former session load revealing its billing data',
    () async {
      final gate = Completer<ApiResult>();
      final repository = BillingFixture()..read = gate.future;
      final vm = BillingViewModel(repository: repository);
      final pending = vm.fetchBillingList();
      vm.reset();
      gate.complete(rows());
      await pending;
      expect(vm.entries, isEmpty);
      expect(vm.loadState, BillingLoadState.initial);
    },
  );

  test('an older refresh cannot erase a confirmed billing update', () async {
    final repository = BillingFixture();
    final vm = BillingViewModel(repository: repository);
    await vm.fetchBillingList();
    final gate = Completer<ApiResult>();
    repository.read = gate.future;
    final pending = vm.fetchBillingList();
    expect((await vm.updateBillingStatus(1, request)).success, isTrue);
    gate.complete(rows());
    await pending;
    expect(vm.entries.single.status, confirmed.status);
  });

  test(
    'duplicate saves issue one write and retain old state until confirmation',
    () async {
      final gate = Completer<ApiResult>();
      final repository = BillingFixture()..write = gate.future;
      final vm = BillingViewModel(repository: repository);
      await vm.fetchBillingList();
      final pending = vm.updateBillingStatus(1, request);
      expect(vm.entries.single.status, original.status);
      expect((await vm.updateBillingStatus(1, request)).success, isFalse);
      expect(repository.writes, 1);
      gate.complete(ApiResult(success: true, message: '', data: confirmed));
      await pending;
      expect(vm.isSaving, isFalse);
      expect(vm.entries.single.status, confirmed.status);
    },
  );

  test('server refusal clears previously displayed billing content', () async {
    final repository = BillingFixture();
    final vm = BillingViewModel(repository: repository);
    await vm.fetchBillingList();
    repository.read = Future.value(
      ApiResult(success: false, message: 'Permission denied'),
    );
    await vm.fetchBillingList();
    expect(vm.loadState, BillingLoadState.error);
    expect(vm.entries, isEmpty);
  });
}
