import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/notifications/model/notification_item.dart';
import 'package:frontend/features/attendance/model/attendance.dart';

void main(){
  test('Firebase/server instants display in local time without moving business dates',(){
    const instant='2026-10-15T15:00:00Z';
    final notification=NotificationItem.fromJson({'id':1,'createdAt':instant});
    expect(notification.createdAt.isUtc,isFalse);
    expect(notification.createdAt.isAtSameMomentAs(DateTime.parse(instant)),isTrue);
    final attendance=Attendance.fromJson({'id':1,'employeeId':4,'attendanceDate':'2026-10-15','inTime':instant,'latitude':12.97,'longitude':77.59});
    expect(attendance.inTime.isUtc,isFalse);
    expect(attendance.inTime.isAtSameMomentAs(DateTime.parse(instant)),isTrue);
    expect(attendance.attendanceDate,DateTime(2026,10,15));
  });
}
