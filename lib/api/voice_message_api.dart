import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as path;

import '../models/chat_user.dart';
import '../models/group.dart';
import '../models/message.dart';
import 'apis.dart';
import 'group_apis.dart';

class VoiceMessageAPI {
  static final AudioRecorder _audioRecorder = AudioRecorder();
  static bool _isRecording = false;
  static String? _currentRecordingPath;
  static DateTime? _recordingStartTime;

  // Voice upload endpoint
  static const String _uploadEndpoint = 'https://YOUR_UPLOAD_URL.com/upload.php';

  // Check if microphone permission is granted
  static Future<bool> checkPermission() async {
    return await _audioRecorder.hasPermission();
  }

  // Start recording audio
  static Future<void> startRecording() async {
    if (!await checkPermission()) {
      log('Microphone permission not granted');
      return;
    }

    try {
      // Create unique filename with timestamp
      final appDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final filePath = path.join(appDir.path, 'voice_message_$timestamp.m4a');

      // Configure recorder
      await _audioRecorder.start(
        RecordConfig(
          encoder:
              AudioEncoder.aacLc, // AAC codec for good quality/size balance
          bitRate: 128000, // 128 kbps
          sampleRate: 44100, // CD quality
        ),
        path: filePath,
      );

      _isRecording = true;
      _currentRecordingPath = filePath;
      _recordingStartTime = DateTime.now();

      log('Recording started at: $filePath');
    } catch (e) {
      log('Error starting recording: $e');
      _isRecording = false;
    }
  }

  // Stop recording and return the file
  static Future<File?> stopRecording() async {
    if (!_isRecording) {
      log('Not currently recording');
      return null;
    }

    try {
      // Stop recording
      final path = await _audioRecorder.stop();
      _isRecording = false;

      if (path == null) {
        log('Recording failed - no file path returned');
        return null;
      }

      // Calculate recording duration
      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;

      // Only return recording if it's longer than 0.5 seconds
      if (duration.inMilliseconds < 500) {
        log('Recording too short, discarding');
        File(path).deleteSync();
        return null;
      }

      log('Recording stopped, saved at: $path');
      log('Recording duration: ${duration.inSeconds} seconds');

      return File(path);
    } catch (e) {
      log('Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  // Cancel current recording
  static Future<void> cancelRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _audioRecorder.cancel();
      _isRecording = false;
      _recordingStartTime = null;
      _currentRecordingPath = null;

      log('Recording cancelled');
    } catch (e) {
      log('Error cancelling recording: $e');
    } finally {
      _isRecording = false;
    }
  }

  // Get recording status
  static bool get isRecording => _isRecording;

  // Get recording duration in seconds (for UI display)
  static int getRecordingDuration() {
    if (!_isRecording || _recordingStartTime == null) {
      return 0;
    }

    final duration = DateTime.now().difference(_recordingStartTime!);
    return duration.inSeconds;
  }

  // Dispose resources
  static void dispose() {
    _audioRecorder.dispose();
  }

  // Upload voice message to server and send to user
  static Future<void> uploadAndSendVoiceMessage(
      File audioFile, ChatUser user) async {
    try {
      // Get file info
      final fileName = path.basename(audioFile.path);
      final fileSize = await audioFile.length();

      // Create multipart request
      final uri = Uri.parse('$_uploadEndpoint?folder=users_audio_messages');
      final request = http.MultipartRequest('POST', uri);

      // Add audio file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        contentType: MediaType('audio', 'm4a'),
      ));

      // Send request
      log('Uploading voice message: ${audioFile.path}');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseBody);
        if (jsonResponse['url'] != null) {
          final audioUrl = jsonResponse['url'];
          log('Voice message uploaded successfully: $audioUrl');

          // Send message with audio URL
          await APIs.sendMessage(
            user,
            audioUrl,
            Type.audio,
            fileName: fileName,
            fileSize: fileSize,
            fileType: 'audio/m4a',
          );
        } else {
          log('Failed to get URL from response: $responseBody');
        }
      } else {
        log('Failed to upload voice message: ${response.statusCode}');
        log('Response: $responseBody');
      }
    } catch (e) {
      log('Error uploading voice message: $e');
    }
  }

  // Upload voice message to server and send to group
  static Future<void> uploadAndSendGroupVoiceMessage(
      File audioFile, Group group) async {
    try {
      // Get file info
      final fileName = path.basename(audioFile.path);
      final fileSize = await audioFile.length();

      // Create multipart request
      final uri = Uri.parse('$_uploadEndpoint?folder=users_audio_messages');
      final request = http.MultipartRequest('POST', uri);

      // Add audio file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        contentType: MediaType('audio', 'm4a'),
      ));

      // Send request
      log('Uploading group voice message: ${audioFile.path}');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseBody);
        if (jsonResponse['url'] != null) {
          final audioUrl = jsonResponse['url'];
          log('Group voice message uploaded successfully: $audioUrl');

          // Send message with audio URL
          await GroupAPIs.sendGroupMessage(
            group: group,
            msg: audioUrl,
            type: Type.audio,
            fileName: fileName,
            fileSize: fileSize,
            fileType: 'audio/m4a',
          );
        } else {
          log('Failed to get URL from response: $responseBody');
        }
      } else {
        log('Failed to upload group voice message: ${response.statusCode}');
        log('Response: $responseBody');
      }
    } catch (e) {
      log('Error uploading group voice message: $e');
    }
  }
}
