import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:we_chat/services/notification/notification_service.dart';
import 'package:we_chat/services/signalling/signalling_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class CallPage extends StatefulWidget {
  final String receiverUserId;
  final String receiverUserEmail;
  final bool isIncoming;
  final String? roomId;

  const CallPage({
    super.key,
    required this.receiverUserId,
    required this.receiverUserEmail,
    this.isIncoming = false,
    this.roomId,
  });

  @override
  CallPageState createState() => CallPageState();
}

class CallPageState extends State<CallPage> {
  final Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final _auth = FirebaseAuth.instance;
  final _notificationService = NotificationService();

  bool _hasRemoteVideo = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isCallStarted = false;
  bool _isEnding = false;
  bool _isUsingFrontCamera = true;
  bool _isCameraEnabled = true;
  bool _isRemoteCameraEnabled = true;
  Timer? _remoteVideoCheckTimer;

  void _logDebug(String message) {
    log('CallPage Debug: $message');
  }

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    _logDebug('Starting call initialization');
  
    try {
      _logDebug('Initializing renderers');
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      signaling.onAddRemoteStream = ((stream) {
        _logDebug('Remote stream added');
        _remoteRenderer.srcObject = stream;
        
        final audioTracks = stream.getAudioTracks();
        _logDebug('Remote audio tracks: ${audioTracks.length}');
        if (audioTracks.isNotEmpty) {
          for (var track in audioTracks) {
            track.enabled = true;
          }
        }

        final videoTracks = stream.getVideoTracks();
        _logDebug('Remote video tracks: ${videoTracks.length}');
        
        if (videoTracks.isNotEmpty) {
          _checkRemoteVideoStatus(videoTracks);

          for (var track in videoTracks) {
            track.onEnded = () {
              _logDebug('Remote video track ended');
              if (mounted) {
                setState(() {
                  _isRemoteCameraEnabled = false;
                });
              }
            };

            if (mounted) {
              setState(() {
                _isRemoteCameraEnabled = track.enabled;
                _logDebug('Initial remote camera state: ${track.enabled}');
              });
            }
          }

          _startRemoteVideoCheck();
        } else {
          _logDebug('No remote video tracks available');
          if (mounted) {
            setState(() {
              _isRemoteCameraEnabled = false;
            });
          }
        }

        setState(() {
          _hasRemoteVideo = true;
          _logDebug('Remote video state updated: $_hasRemoteVideo');
        });
      });

      signaling.onCallEnded = () {
        _logDebug('Call ended by remote party');
        if (mounted) {
          _endCall(isRemoteEnded: true);
        }
      };

      _logDebug('Opening user media');
      await signaling.openUserMedia(_localRenderer, _remoteRenderer);

      if (widget.isIncoming && widget.roomId != null) {
        _logDebug('Joining room: ${widget.roomId}');
        await signaling.joinRoom(widget.roomId!, _remoteRenderer);
      } else if (!widget.isIncoming) {
        _logDebug('Creating new room for outgoing call');
        final roomId = await signaling.createRoom(_remoteRenderer);
        _logDebug('Room created: $roomId');
        await _sendCallNotification(roomId);
      }

      setState(() {
        _isCallStarted = true;
        _logDebug('Call started successfully');
      });
    } catch (e) {
      _logDebug('Error during call initialization: $e');
      rethrow;
    }
  }

  // Helper method to check remote video status
  void _checkRemoteVideoStatus(List<MediaStreamTrack> videoTracks) {
    bool anyTrackEnabled = false;

    for (var track in videoTracks) {
      if (track.enabled) {
        anyTrackEnabled = true;
        break;
      }
    }

    _logDebug('Remote video status check - Enabled: $anyTrackEnabled');

    if (mounted) {
      setState(() {
        _isRemoteCameraEnabled = anyTrackEnabled;
      });
    }
  }

  Future<void> _sendCallNotification(String roomId) async {
    final currentUser = _auth.currentUser;
    if (currentUser != null && !signaling.hasNotifiedReceiver) {
      log("Sending call notification to ${widget.receiverUserId}");
      await _notificationService.sendCallNotification(
        receiverUserId: widget.receiverUserId,
        callerName: currentUser.email ?? 'Unknown',
        roomId: roomId,
      );
    }
  }

  Future<void> _endCall({bool isRemoteEnded = false}) async {
    if (!mounted || _isEnding) return;
    _logDebug('Starting call end process - Remote ended: $isRemoteEnded');
    _isEnding = true;

    try {
      // Cancel the call notification if we have a room ID
      if (widget.roomId != null) {
        _logDebug('Canceling call notification for room: ${widget.roomId}');
        await _notificationService.cancelCallNotification(widget.roomId!);
      }

      // Clear video renderers first
      if (mounted) {
        setState(() {
          _hasRemoteVideo = false;
          _isCallStarted = false;
          _logDebug('Call state updated for ending');
        });
      }

      // Cleanup call
      _logDebug('Hanging up call');
      await signaling.hangUp(_localRenderer);

      if (mounted) {
        if (isRemoteEnded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call ended by other party'),
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Use Future.microtask to avoid navigation during build
        Future.microtask(() {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      _logDebug('Error during call end: $e');
      if (mounted) {
        Future.microtask(() {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });
      }
    }
  }

  void _startRemoteVideoCheck() {
    _logDebug('Starting remote video check timer');
    // Cancel any existing timer
    _remoteVideoCheckTimer?.cancel();

    // Check remote video status every 2 seconds
    _remoteVideoCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        _logDebug('Widget unmounted, canceling video check timer');
        timer.cancel();
        return;
      }

      final remoteStream = _remoteRenderer.srcObject;
      if (remoteStream != null) {
        final videoTracks = remoteStream.getVideoTracks();
        _logDebug('Periodic check - Video tracks: ${videoTracks.length}');
        if (videoTracks.isNotEmpty) {
          _checkRemoteVideoStatus(videoTracks);
        } else {
          setState(() {
            _isRemoteCameraEnabled = false;
            _logDebug('No video tracks found in periodic check');
          });
        }
      }
    });
  }

  @override
  void dispose() {
    try {
      // Cancel notification first
      if (widget.roomId != null) {
        _notificationService.cancelCallNotification(widget.roomId!);
      }

      // Stop remote video check timer
      _remoteVideoCheckTimer?.cancel();

      // Clear video renderers
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;

      // Dispose renderers after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          _localRenderer.dispose();
          _remoteRenderer.dispose();
        } catch (e) {
          print('Error disposing renderers: $e');
        }
      });
    } catch (e) {
      print('Error during dispose: $e');
    }
    super.dispose();
  }

  void _toggleMute() {
    try {
      final localStream = _localRenderer.srcObject;
      if (localStream != null) {
        final audioTracks = localStream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          for (var track in audioTracks) {
            track.enabled = !track.enabled;
          }
          setState(() {
            _isMuted = !_isMuted;
          });
        }
      }
    } catch (e) {
      print('Error toggling mute: $e');
    }
  }

  void _toggleSpeaker() {
    try {
      final remoteStream = _remoteRenderer.srcObject;
      if (remoteStream != null) {
        final audioTracks = remoteStream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          for (var track in audioTracks) {
            track.enabled = !track.enabled;
          }
          setState(() {
            _isSpeakerOn = !_isSpeakerOn;
          });
        }
      }
    } catch (e) {
      print('Error toggling speaker: $e');
    }
  }

  Future<void> _toggleCamera() async {
    try {
      final localStream = _localRenderer.srcObject;
      if (localStream != null) {
        // Get the active video track
        final videoTracks = localStream.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          // Switch camera using the static method from flutter_webrtc
          await Helper.switchCamera(videoTracks[0]);
          setState(() {
            _isUsingFrontCamera = !_isUsingFrontCamera;
          });
        }
      }
    } catch (e) {
      print('Error toggling camera: $e');
    }
  }

  void _toggleCameraEnabled() {
    try {
      final localStream = _localRenderer.srcObject;
      if (localStream != null) {
        final videoTracks = localStream.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          for (var track in videoTracks) {
            track.enabled = !track.enabled;
          }
          setState(() {
            _isCameraEnabled = !_isCameraEnabled;
          });
        }
      }
    } catch (e) {
      print('Error toggling camera enabled: $e');
    }
  }

  void _showComingSoonDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87, // Darker background overlay
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.record_voice_over,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Coming Soon!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Voice changer feature will be available soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoView(RTCVideoRenderer renderer, bool isLocal) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isLocal ? 16 : 0),
      child: renderer.srcObject != null
          ? ((isLocal && !_isCameraEnabled) ||
                  (!isLocal && !_isRemoteCameraEnabled)
              ? Container(
                  color: Colors.black87,
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_off,
                        color: Colors.white.withOpacity(0.7),
                        size: isLocal ? 32 : 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isLocal
                            ? 'Camera Disabled'
                            : 'User disabled the camera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isLocal ? 16 : 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RTCVideoView(
                  renderer,
                  mirror: isLocal && _isUsingFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ))
          : Container(
              color: Colors.black87,
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam_off,
                    color: Colors.white.withOpacity(0.7),
                    size: isLocal ? 32 : 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isLocal ? 'No Video' : 'User disabled the camera',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isLocal ? 16 : 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_isEnding) {
          await _endCall();
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isCallStarted
            ? _buildCallUI()
            : const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildCallUI() {
    return Stack(
      children: [
        // Remote video - full screen
        Positioned.fill(
          child: _buildVideoView(_remoteRenderer, false),
        ),

        // Top controls
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  color: Colors.white,
                  onPressed: () => _endCall(),
                ),
                Text(
                  widget.receiverUserEmail,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 40), // Balance the back button
              ],
            ),
          ),
        ),

        // Local video - small overlay
        Positioned(
          top: 120,
          right: 16,
          child: Container(
            width: 110,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: _buildVideoView(_localRenderer, true),
          ),
        ),

        // Bottom control panel
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Camera Controls Row
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildControlButton(
                        icon: _isCameraEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        onPressed: _toggleCameraEnabled,
                        backgroundColor: _isCameraEnabled
                            ? const Color(0xFF2196F3)
                            : Colors.redAccent,
                        buttonSize: 54,
                        iconSize: 26,
                      ),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: _isUsingFrontCamera
                            ? Icons.camera_front
                            : Icons.camera_rear,
                        onPressed: _toggleCamera,
                        backgroundColor: const Color(0xFF4285F4),
                        buttonSize: 54,
                        iconSize: 26,
                      ),
                    ],
                  ),
                ),

                // Main Call Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      onPressed: _toggleMute,
                      backgroundColor:
                          _isMuted ? Colors.redAccent : const Color(0xFF03A9F4),
                      buttonSize: 56,
                      iconSize: 26,
                    ),
                    _buildControlButton(
                      icon: Icons.record_voice_over,
                      onPressed: _showComingSoonDialog,
                      backgroundColor: const Color(0xFF4CAF50),
                      buttonSize: 56,
                      iconSize: 26,
                    ),
                    _buildControlButton(
                      icon: Icons.call_end,
                      onPressed: _endCall,
                      backgroundColor: Colors.redAccent.shade700,
                      iconSize: 32,
                      buttonSize: 70,
                    ),
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      onPressed: _toggleSpeaker,
                      backgroundColor:
                          _isSpeakerOn ? const Color(0xFF03A9F4) : Colors.grey,
                      buttonSize: 56,
                      iconSize: 26,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    double iconSize = 24,
    double buttonSize = 50,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.4),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(buttonSize / 2),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  backgroundColor.withOpacity(0.9),
                  backgroundColor,
                  backgroundColor.withOpacity(0.8),
                ],
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
