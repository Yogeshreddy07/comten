import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:frontend/core/services/account_cache.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Encrypted Hive disk reopen, identity isolation, permission version and logout',() async {
    FlutterSecureStorage.setMockInitialValues({});
    final directory=await Directory.systemTemp.createTemp('crompton-cache-');
    Hive.init(directory.path);
    final first=AccountCache();
    await first.bind('4',1);await first.put('auth_profile',{'employeeCode':'EMP001','permissionVersion':1});
    await first.put('/projects',[{'id':100,'projectName':'Synthetic'}]);
    await first.close();
    final reopened=AccountCache();
    expect((await reopened.restoreProfile('4'))?['employeeCode'],'EMP001');
    expect(reopened.read('/projects'),[{'id':100,'projectName':'Synthetic'}]);
    await reopened.bind('3',1);expect(reopened.read('/projects'),null);
    await reopened.bind('4',2);expect(reopened.read('/projects'),null);
    await reopened.clear();expect(await reopened.restoreProfile('4'),null);
    await Hive.close();await directory.delete(recursive:true);
  });
}
