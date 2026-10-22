import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failed,
}

/// Either the device's current coordinates, or the reason they couldn't be
/// obtained - callers (Check-in / Check-out screens) branch on [failure] to
/// show a specific message (e.g. "enable location services" vs. "grant
/// permission") rather than one generic error.
///
/// The place name for these coordinates (e.g. "MG Road, Bengaluru") is no
/// longer resolved here - it's reverse-geocoded server-side (via Google's
/// Geocoding API, see `GeocodingService`) once the coordinates reach the
/// backend on check-in/check-out, not shown live on this screen.
class LocationResult {
  final double? latitude;
  final double? longitude;
  final LocationFailure? failure;

  const LocationResult._({this.latitude, this.longitude, this.failure});

  factory LocationResult.success(double latitude, double longitude) =>
      LocationResult._(latitude: latitude, longitude: longitude);

  factory LocationResult.failure(LocationFailure failure) =>
      LocationResult._(failure: failure);

  bool get isSuccess => failure == null;
}

class LocationHelper {
  LocationHelper._();

  /// Requests location permission (if not already granted) and returns the
  /// device's current GPS coordinates, for attaching to a Check-in /
  /// Check-out request.
  static Future<LocationResult> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failure(LocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return LocationResult.failure(LocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failure(LocationFailure.permissionDeniedForever);
      }

      final position = await _acquirePrecisePosition();
      return LocationResult.success(position.latitude, position.longitude);
    } catch (e) {
      return LocationResult.failure(LocationFailure.failed);
    }
  }

  /// A fix is accepted immediately once its reported error radius is at or
  /// under this; below ~20m, GPS noise is small enough that check-in/out
  /// location no longer visibly jumps between attempts at the same spot.
  static const _maxAcceptableAccuracyMeters = 20.0;

  /// Upper bound on how long a check-in/check-out screen waits for GPS
  /// before settling for the best fix seen so far - long enough for a cold
  /// GPS lock to sharpen, short enough that check-in doesn't feel stuck.
  static const _acquisitionTimeout = Duration(seconds: 12);

  /// A single `getCurrentPosition` call returns whatever fix the OS happens
  /// to have on hand right then - right after a cold GPS start, or indoors/
  /// near tall buildings, that can be 100+ meters off, which is why the
  /// recorded location sometimes looked wrong. Instead, sample the live
  /// position stream for up to [_acquisitionTimeout] and keep the most
  /// accurate fix seen (via [Position.accuracy], the GPS's own error-radius
  /// estimate in meters), returning as soon as one is within
  /// [_maxAcceptableAccuracyMeters] rather than always waiting out the timeout.
  static Future<Position> _acquirePrecisePosition() async {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    Position? best;
    final completer = Completer<Position>();
    late final StreamSubscription<Position> subscription;

    final timeoutTimer = Timer(_acquisitionTimeout, () async {
      if (completer.isCompleted) return;
      await subscription.cancel();
      if (best != null) {
        completer.complete(best);
        return;
      }
      // The stream never delivered anything (e.g. GPS still acquiring) -
      // fall back to a single one-shot fix rather than failing check-in/out.
      try {
        completer.complete(
          await Geolocator.getCurrentPosition(locationSettings: locationSettings)
              .timeout(const Duration(seconds: 5)),
        );
      } catch (e) {
        completer.completeError(e);
      }
    });

    subscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen(
      (position) async {
        if (best == null || position.accuracy < best!.accuracy) {
          best = position;
        }
        if (position.accuracy <= _maxAcceptableAccuracyMeters) {
          timeoutTimer.cancel();
          await subscription.cancel();
          if (!completer.isCompleted) completer.complete(position);
        }
      },
      onError: (Object e) {
        timeoutTimer.cancel();
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    try {
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
  }

  /// Drops everything after the country name in a comma-joined location
  /// string (e.g. "..., Tamil Nadu 642112, India, Munnar - Udumalpet Road"
  /// -> "..., Tamil Nadu 642112, India") - a defensive safeguard when
  /// rendering an already-stored [Attendance.locationName]/
  /// [Attendance.checkOutLocationName] that may predate server-side
  /// geocoding.
  static String? trimTrailingAfterCountry(
    String? value, {
    String country = 'India',
  }) {
    if (value == null) return null;
    final segments = value.split(',');
    final countryIndex = segments.indexWhere(
      (segment) => segment.trim().toLowerCase() == country.toLowerCase(),
    );
    if (countryIndex == -1) return value;
    return segments
        .sublist(0, countryIndex + 1)
        .map((segment) => segment.trim())
        .join(', ');
  }
}
