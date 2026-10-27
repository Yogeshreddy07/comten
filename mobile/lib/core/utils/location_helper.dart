import 'dart:async';

import 'package:geocoding/geocoding.dart';
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
/// [address] is the place name for these coordinates (e.g. "12, MG Road,
/// Bengaluru, Karnataka 560001, India"), reverse-geocoded on the device via
/// the platform geocoder (Google's on Android). It's null when the lookup
/// fails (offline, no geocoder) - the coordinates alone are still valid for
/// check-in/check-out.
class LocationResult {
  final double? latitude;
  final double? longitude;
  final String? address;
  final LocationFailure? failure;

  const LocationResult._({
    this.latitude,
    this.longitude,
    this.address,
    this.failure,
  });

  factory LocationResult.success(
    double latitude,
    double longitude, {
    String? address,
  }) =>
      LocationResult._(
        latitude: latitude,
        longitude: longitude,
        address: address,
      );

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
      // Permission is asked before the GPS on/off check so the system
      // prompt always appears, even when location services are switched off.
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

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failure(LocationFailure.serviceDisabled);
      }

      final position = await _acquirePrecisePosition();
      final address =
          await _resolveAddress(position.latitude, position.longitude);
      return LocationResult.success(
        position.latitude,
        position.longitude,
        address: address,
      );
    } catch (e) {
      return LocationResult.failure(LocationFailure.failed);
    }
  }

  /// Reverse-geocodes [latitude]/[longitude] into a full street address.
  /// Never throws - an address is a nice-to-have on top of the coordinates,
  /// so a slow or failed lookup must not block check-in/check-out.
  static Future<String?> _resolveAddress(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty) return null;
      return formatPlacemark(placemarks.first);
    } catch (e) {
      return null;
    }
  }

  /// On Android [Placemark.street] is the geocoder's full formatted address
  /// line (house number through country), the most precise form available;
  /// otherwise (iOS, or a bare street) the address is assembled from parts.
  static String? formatPlacemark(Placemark placemark) {
    final street = placemark.street?.trim();
    if (street != null && street.contains(',')) {
      return trimTrailingAfterCountry(street);
    }

    final parts = <String>[];
    void add(String? value) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      if (parts.any((p) => p.toLowerCase() == trimmed.toLowerCase())) return;
      parts.add(trimmed);
    }

    add(street);
    add(placemark.subLocality);
    add(placemark.locality);
    add(placemark.subAdministrativeArea);
    add([placemark.administrativeArea, placemark.postalCode]
        .where((v) => v != null && v.trim().isNotEmpty)
        .join(' '));
    add(placemark.country);
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// "lat, lng" to 6 decimal places (~0.1m) - shown when no address could be
  /// resolved, so the recorded location is never just hidden.
  static String formatCoordinates(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  /// Whether [failure] can only be fixed outside the app - the OS won't show
  /// the permission prompt again once it's permanently denied, and location
  /// services can't be switched on from a runtime prompt.
  static bool needsSettings(LocationFailure? failure) =>
      failure == LocationFailure.serviceDisabled ||
      failure == LocationFailure.permissionDeniedForever;

  /// Opens the system screen that resolves [failure]: the device location
  /// toggle, or this app's permission page.
  static Future<void> openSettingsFor(LocationFailure failure) async {
    if (failure == LocationFailure.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
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
