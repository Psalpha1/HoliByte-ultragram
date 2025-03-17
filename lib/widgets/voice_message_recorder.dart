import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/voice_message_api.dart';
import '../models/chat_user.dart';
import '../models/group.dart';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart';

class VoiceMessageRecorder extends StatefulWidget {
  final ChatUser? user; // For direct messages
  final Group? group; // For group messages
  final VoidCallback onCancel;

  const VoiceMessageRecorder({
    super.key,
    this.user,
    this.group,
    required this.onCancel,
  })  : assert(user != null || group != null,
            'Either user or group must be provided');

  @override
  State<VoiceMessageRecorder> createState() => _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends State<VoiceMessageRecorder>
    with SingleTickerProviderStateMixin {
  static const int _maxRecordingDurationSeconds = 60; // One minute limit
  static const Color _messengerBlue = Color(0xFF0084FF);

  bool _isRecording = false;
  String _timerText = '00:00';
  late AnimationController _animationController;
  int _recordingDuration = 0;
  final bool _isSending = false;
  bool _reachedTimeLimit = false;
  double _progressValue = 0.0;

  // Animation values for the wave
  final List<double> _amplitudes = List.filled(30, 0);
  int _amplitudeIndex = 0;

  // Add a field to store the audio file when time limit is reached
  File? _recordedAudioFile;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller for pulsating animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Start recording immediately
    _startRecording();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Request vibration on start
    HapticFeedback.mediumImpact();

    // Initialize recording
    await VoiceMessageAPI.startRecording();

    if (mounted) {
      setState(() {
        _isRecording = true;
        _progressValue = 0.0;
      });

      // Update timer text
      _startTimer();
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isRecording) {
        // Update recording duration
        _recordingDuration = VoiceMessageAPI.getRecordingDuration();

        // Check if we've reached the time limit
        if (_recordingDuration >= _maxRecordingDurationSeconds) {
          _handleTimeLimitReached();
          return;
        }

        // Format time as mm:ss
        final minutes = (_recordingDuration ~/ 60).toString().padLeft(2, '0');
        final seconds = (_recordingDuration % 60).toString().padLeft(2, '0');

        setState(() {
          _timerText = '$minutes:$seconds';
          _progressValue = _recordingDuration / _maxRecordingDurationSeconds;

          // Generate a random amplitude for visualization
          final amplitude = math.Random().nextDouble() * 0.5 + 0.2;
          _amplitudes[_amplitudeIndex] = amplitude;
          _amplitudeIndex = (_amplitudeIndex + 1) % _amplitudes.length;
        });

        // Continue timer
        _startTimer();
      }
    });
  }

  Future<void> _handleTimeLimitReached() async {
    // Stop the recording and store the file
    final audioFile = await VoiceMessageAPI.stopRecording();
    _recordedAudioFile = audioFile;

    if (mounted) {
      setState(() {
        _reachedTimeLimit = true;
        _isRecording = false;
        _timerText = '00:10'; // Update to show correct max time
        _progressValue = 1.0;
      });
    }

    // Vibrate to indicate recording stopped
    HapticFeedback.mediumImpact();
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording && !_reachedTimeLimit) return;

    // Vibrate to indicate recording stopped
    HapticFeedback.mediumImpact();

    File? audioFile;
    if (_isRecording) {
      // If still recording, stop and get the file
      audioFile = await VoiceMessageAPI.stopRecording();
    } else if (_reachedTimeLimit) {
      // If time limit reached, use the stored file
      audioFile = _recordedAudioFile;
    }

    if (audioFile != null) {
      // Send voice message based on whether it's a direct or group message
      if (widget.user != null) {
        VoiceMessageAPI.uploadAndSendVoiceMessage(
            audioFile, widget.user!); // Don't await here
      } else if (widget.group != null) {
        VoiceMessageAPI.uploadAndSendGroupVoiceMessage(
            audioFile, widget.group!); // Don't await here
      }
    }

    // Close the recorder immediately
    if (mounted) {
      widget.onCancel();
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording && !_reachedTimeLimit) return;

    // Cancel recording
    await VoiceMessageAPI.cancelRecording();

    if (mounted) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[900] : Colors.white;
    final foregroundColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Progress bar background
            Container(
              height: 56,
              width: double.infinity,
              color: backgroundColor,
            ),

            // Progress bar
            Positioned.fill(
              child: LinearProgressIndicator(
                value: _progressValue,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _messengerBlue.withOpacity(0.2),
                ),
              ),
            ),

            // Content
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  // Cancel Button (moved to left)
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: foregroundColor.withOpacity(0.7),
                    ),
                    onPressed: _cancelRecording,
                  ),

                  // Animated Recording Icon
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _messengerBlue.withOpacity(0.1),
                    ),
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 + (_animationController.value * 0.2),
                          child: Icon(
                            Icons.mic,
                            color: _messengerBlue,
                            size: 20,
                          ),
                        );
                      },
                    ),
                  ),

                  // Timer and Waveform
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          _timerText,
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: RectangleWaveform(
                              samples: _amplitudes,
                              height: 32,
                              width: double.infinity,
                              activeColor: _messengerBlue.withOpacity(0.7),
                              inactiveColor: _messengerBlue.withOpacity(0.3),
                              showActiveWaveform: true,
                              isRoundedRectangle: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Send Button
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: _messengerBlue,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: (_isRecording || _reachedTimeLimit)
                            ? _stopAndSendRecording
                            : null,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
