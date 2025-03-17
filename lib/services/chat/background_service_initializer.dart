import 'package:we_chat/services/chat/background_message_service.dart';
import 'dart:async';

class BackgroundServiceInitializer {
  static final BackgroundServiceInitializer _instance =
      BackgroundServiceInitializer._internal();

  factory BackgroundServiceInitializer() => _instance;

  BackgroundServiceInitializer._internal();

  bool _initialized = false;
  bool _initializing = false;

  Future<void> initialize() async {
    // Skip if already initialized or currently initializing
    if (_initialized && !_initializing) {
      // If already initialized, just refresh the users stream
      await BackgroundMessageService().refreshUsersStream();
      return;
    }

    if (_initializing) return;

    _initializing = true;

    try {
      // Set a timeout for initialization
      final completer = Completer<void>();

      // Start the initialization
      final initFuture = BackgroundMessageService().initialize();

      // Set a timeout
      final timeoutFuture =
          Future.delayed(const Duration(seconds: 20)).then((_) {
        if (!completer.isCompleted) {
          throw TimeoutException('Background service initialization timed out');
        }
      });

      // Wait for either completion or timeout
      initFuture.then((_) {
        if (!completer.isCompleted) {
          _initialized = true;
          completer.complete();
        }
      }).catchError((error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      });

      // Wait for either the initialization or the timeout
      await Future.any([initFuture, timeoutFuture]);

      // If we get here and the completer isn't completed, complete it
      if (!completer.isCompleted) {
        _initialized = true;
        completer.complete();
      }

      // Wait for the completer to ensure proper completion
      await completer.future;
    } catch (e) {
      print('Error in BackgroundServiceInitializer: $e');
      _initialized = false;
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  // Reset the initializer (useful for testing or after logout)
  void reset() {
    _initialized = false;
    _initializing = false;
  }
}
