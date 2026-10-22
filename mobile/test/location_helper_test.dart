import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:frontend/core/utils/location_helper.dart';

class SyntheticLocation extends GeolocatorPlatform {
  bool enabled=true;
  bool cancelled=false;
  bool fail=false;
  LocationPermission permission=LocationPermission.whileInUse;
  @override Future<bool> isLocationServiceEnabled() async=>enabled;
  @override Future<LocationPermission> checkPermission() async=>permission;
  @override Future<LocationPermission> requestPermission() async=>permission;
  @override Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    late StreamController<Position> stream;
    stream=StreamController(onListen:()=>scheduleMicrotask(()=>fail?stream.addError(StateError('GPS unavailable')):stream.add(Position(latitude:12.97,longitude:77.59,timestamp:DateTime.now(),accuracy:5,altitude:0,altitudeAccuracy:0,heading:0,headingAccuracy:0,speed:0,speedAccuracy:0))),onCancel:(){cancelled=true;});
    return stream.stream;
  }
}
void main(){
  late GeolocatorPlatform previous;
  late SyntheticLocation synthetic;
  setUp((){previous=GeolocatorPlatform.instance;synthetic=SyntheticLocation();GeolocatorPlatform.instance=synthetic;});
  tearDown(()=>GeolocatorPlatform.instance=previous);
  test('disabled GPS returns the existing service-disabled state',() async {
    synthetic.enabled=false;
    expect((await LocationHelper.getCurrentLocation()).failure,LocationFailure.serviceDisabled);
  });
  for(final permission in [LocationPermission.denied,LocationPermission.deniedForever]) {
    test('location permission $permission is handled',() async {
      synthetic.permission=permission;
      expect((await LocationHelper.getCurrentLocation()).failure,permission==LocationPermission.denied?LocationFailure.permissionDenied:LocationFailure.permissionDeniedForever);
    });
  }
  test('a precise synthetic GPS fix cancels its subscription',() async {
    final result=await LocationHelper.getCurrentLocation();
    expect(result.latitude,12.97);expect(result.longitude,77.59);expect(synthetic.cancelled,isTrue);
  });
  test('GPS stream errors release the subscription',() async {
    synthetic.fail=true;
    expect((await LocationHelper.getCurrentLocation()).failure,LocationFailure.failed);
    expect(synthetic.cancelled,isTrue);
  });
}
