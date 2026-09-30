import 'package:geolocator/geolocator.dart';

/// How long a location lookup may block a task start/submit action.
const Duration defaultGpsTimeout = Duration(seconds: 6);

/// How old a cached fix may be and still be used.
const Duration _cachedFixMaxAge = Duration(minutes: 15);

/// Best-effort location for task start / submit.
///
/// A high-accuracy fix inside a station routinely takes 10-30s and sometimes
/// never resolves at all, which is what made starting and submitting tasks look
/// frozen (and occasionally impossible). This reuses a recent cached fix, then
/// waits at most [timeout] for a coarse one, and returns null rather than
/// failing the action when location is unavailable.
Future<Position?> captureGps({Duration timeout = defaultGpsTimeout}) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
  } catch (_) {
    return null;
  }

  try {
    final cached =
        await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2));
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cachedFixMaxAge) {
      return cached;
    }
  } catch (_) {}

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: timeout,
      ),
    ).timeout(timeout);
  } catch (_) {
    return null;
  }
}
