import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:parachute/core/providers/file_system_provider.dart';
import '../services/photo_capture_service.dart';

/// Provider for the photo capture service.
final photoCaptureServiceProvider = Provider<PhotoCaptureService>((ref) {
  final fileSystem = ref.watch(dailyFileSystemServiceProvider);
  return PhotoCaptureService(fileSystem);
});
