import 'dart:math' as math;
import 'dart:developer';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart';
import 'package:path/path.dart' as path;

class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final String? senderName;
  final bool isMe;

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    this.senderName,
    required this.isMe,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _AudioPlayerCache {
  final AudioPlayer player;
  final List<double> waveform;
  Duration duration;
  Duration position;
  bool isPlaying;
  bool hasError;
  String errorMsg;

  _AudioPlayerCache({
    required this.player,
    required this.waveform,
  })  : duration = const Duration(seconds: 1),
        position = Duration.zero,
        isPlaying = false,
        hasError = false,
        errorMsg = '';
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  // Static cache to store AudioPlayer instances
  static final Map<String, _AudioPlayerCache> _cache = {};

  Duration _duration = const Duration(seconds: 1);
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMsg = '';
  List<double> _generatedWaveform = [];
  AudioPlayer? _audioPlayer;
  File? _localAudioFile;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _initializeFromCacheOrCreate();
  }

  @override
  void dispose() {
    // Don't dispose the audio player if it's cached
    if (!_cache.containsKey(widget.audioUrl)) {
      _audioPlayer?.dispose();
    }
    super.dispose();
  }

  void _initializeFromCacheOrCreate() {
    if (_cache.containsKey(widget.audioUrl)) {
      // Restore from cache
      final cached = _cache[widget.audioUrl]!;
      _audioPlayer = cached.player;
      _generatedWaveform = cached.waveform;
      _duration = cached.duration;
      _position = cached.position;
      _isPlaying = cached.isPlaying;
      _hasError = cached.hasError;
      _errorMsg = cached.errorMsg;
      _isLoading = false;

      // Reattach listeners
      _attachListeners();
    } else {
      // Generate waveform and initialize new player
      _generateWaveformData();
      _initializeAudioPlayer();
    }
  }

  void _attachListeners() {
    if (_audioPlayer == null) return;

    _audioPlayer!.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          if (position.inMilliseconds > _duration.inMilliseconds) {
            _position = _duration;
          } else {
            _position = position;
          }
          // Update cache
          if (_cache.containsKey(widget.audioUrl)) {
            _cache[widget.audioUrl]!.position = _position;
          }
        });
      }
    });

    _audioPlayer!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() {
          _isPlaying = false;
          _position = _duration;
          // Update cache
          if (_cache.containsKey(widget.audioUrl)) {
            _cache[widget.audioUrl]!.isPlaying = false;
            _cache[widget.audioUrl]!.position = _duration;
          }
        });
      }
    });
  }

  Future<void> _initializeAudioPlayer() async {
    try {
      log('Initializing audio player for URL: ${widget.audioUrl}');
      _audioPlayer = AudioPlayer();

      // Create cache entry
      _cache[widget.audioUrl] = _AudioPlayerCache(
        player: _audioPlayer!,
        waveform: _generatedWaveform,
      );

      _attachListeners();

      // Set up duration stream
      _audioPlayer!.durationStream.listen((Duration? d) {
        log('Duration received: ${d?.inMilliseconds ?? 0} ms');
        if (mounted && d != null) {
          setState(() {
            if (d.inMilliseconds > 0) {
              _duration = d;
              // Update cache
              if (_cache.containsKey(widget.audioUrl)) {
                _cache[widget.audioUrl]!.duration = d;
              }
              log('Updated duration to: ${_formatDuration(d)}');
            }
          });
        }
      }, onError: (Object e, StackTrace stackTrace) {
        log('Error from duration stream: $e');
        _handleError('Duration stream error: $e');
      });

      // Try to load the audio
      await _tryLoadAudio();
    } catch (e) {
      log('Error initializing player: $e');
      _handleError('Failed to initialize player: $e');
    }
  }

  // Try multiple approaches to load the audio
  Future<void> _tryLoadAudio() async {
    try {
      // Ensure URL has scheme
      String audioUrl = widget.audioUrl;
      if (!audioUrl.startsWith('http://') && !audioUrl.startsWith('https://')) {
        audioUrl = 'https://$audioUrl';
      }

      // Force HTTP for YOUR_UPLOAD_URL.com - this is because it appears the server doesn't support HTTPS
      if (audioUrl.contains('YOUR_UPLOAD_URL.com') &&
          audioUrl.startsWith('https://')) {
        audioUrl = audioUrl.replaceFirst('https://', 'http://');
        log('Forcing HTTP protocol for YOUR_UPLOAD_URL.com: $audioUrl');
      }

      log('Attempting to load audio directly from URL: $audioUrl');

      // First try: Direct playback from URL
      bool directPlaybackSucceeded = await _tryDirectPlayback(audioUrl);

      if (!directPlaybackSucceeded) {
        log('Direct playback failed, trying to download file...');

        // Second try: Download the file and play locally
        await _downloadAndPlayLocally(audioUrl);
      }
    } catch (e) {
      log('All audio loading attempts failed: $e');
      _handleError('Could not load audio: $e');
    }
  }

  // Try to play directly from URL
  Future<bool> _tryDirectPlayback(String url) async {
    try {
      await _audioPlayer!.setUrl(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Timeout loading audio from URL');
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
      log('Direct URL playback successful');
      return true;
    } catch (e) {
      log('Direct URL playback failed: $e');
      return false;
    }
  }

  // Download and play locally to avoid CORS and other network issues
  Future<void> _downloadAndPlayLocally(String url) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      // Create a unique local file name
      final tempDir = await getTemporaryDirectory();
      final fileName = path.basename(url);
      final localPath = path.join(tempDir.path, fileName);
      _localAudioFile = File(localPath);

      // Check if file already exists
      if (await _localAudioFile!.exists()) {
        log('File already exists locally, using cached version: $localPath');
      } else {
        // Download the file
        log('Downloading file to: $localPath');
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          await _localAudioFile!.writeAsBytes(response.bodyBytes);
          log('File downloaded successfully');
        } else {
          throw Exception('Failed to download file: ${response.statusCode}');
        }
      }

      // Play from local file
      log('Setting audio source to local file: ${_localAudioFile!.path}');
      await _audioPlayer!.setFilePath(_localAudioFile!.path);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
          _isDownloading = false;
        });
      }
    } catch (e) {
      log('Error downloading or playing local file: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        _handleError('Could not load audio: $e');
      }
    }
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMsg = message;
        // Update cache
        if (_cache.containsKey(widget.audioUrl)) {
          _cache[widget.audioUrl]!.hasError = true;
          _cache[widget.audioUrl]!.errorMsg = message;
        }
      });
    }
  }

  // Generate random waveform data for visualization
  void _generateWaveformData() {
    final random = math.Random();
    _generatedWaveform = List.generate(
      40,
      (index) => 0.1 + random.nextDouble() * 0.4,
    );
  }

  // Play or pause audio
  void _togglePlayPause() {
    if (_hasError) {
      _showErrorDetails();
      return;
    }

    if (_isLoading || _isDownloading) return;

    try {
      if (_isPlaying) {
        log('Pausing audio');
        _audioPlayer!.pause();
      } else {
        // If the audio has finished playing (position at end), seek back to beginning
        if (_position.inMilliseconds >= _duration.inMilliseconds - 300) {
          log('Audio finished - resetting to beginning before playing');
          _audioPlayer!.seek(Duration.zero);
          setState(() {
            _position = Duration.zero;
            // Update cache
            if (_cache.containsKey(widget.audioUrl)) {
              _cache[widget.audioUrl]!.position = Duration.zero;
            }
          });
        }

        log('Playing audio');
        _audioPlayer!.play();
      }

      setState(() {
        _isPlaying = !_isPlaying;
        // Update cache
        if (_cache.containsKey(widget.audioUrl)) {
          _cache[widget.audioUrl]!.isPlaying = _isPlaying;
        }
      });
    } catch (e) {
      log('Error toggling playback: $e');
      _handleError('Playback error: $e');
    }
  }

  // Show error details and retry option
  void _showErrorDetails() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audio Playback Error'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Could not play the voice message.'),
              const SizedBox(height: 12),
              Text('URL:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(widget.audioUrl, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text('Error:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_errorMsg,
                  style: TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 12),
              Text('Try downloading and playing the audio locally:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();

              // Get the URL with correct scheme
              String audioUrl = widget.audioUrl;
              if (!audioUrl.startsWith('http://') &&
                  !audioUrl.startsWith('https://')) {
                audioUrl = 'http://$audioUrl';
              }

              if (audioUrl.contains('YOUR_UPLOAD_URL.com') &&
                  audioUrl.startsWith('https://')) {
                audioUrl = audioUrl.replaceFirst('https://', 'http://');
              }

              setState(() {
                _hasError = false;
                _isLoading = true;
              });

              // Try downloading and playing locally
              _downloadAndPlayLocally(audioUrl);
            },
            child: const Text('Download & Play'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _hasError = false;
                _isLoading = true;
              });
              _initializeAudioPlayer();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // Format duration as mm:ss
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Make sure elapsedDuration never exceeds maxDuration
    Duration safePosition = _position;
    if (safePosition.inMilliseconds > _duration.inMilliseconds) {
      safePosition = _duration;
    }

    return Container(
      decoration: BoxDecoration(
        color: widget.isMe
            ? Theme.of(context).primaryColor.withOpacity(0.2)
            : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause/Error button
          InkWell(
            onTap: _togglePlayPause,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasError ? Colors.red : Theme.of(context).primaryColor,
              ),
              child: _isLoading || _isDownloading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _hasError
                          ? Icons.error
                          : (_isPlaying ? Icons.pause : Icons.play_arrow),
                      color: Colors.white,
                      size: 22,
                    ),
            ),
          ),

          const SizedBox(width: 8),

          // Waveform visualization
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sender name (if provided and not from current user)
              if (widget.senderName != null && !widget.isMe) ...[
                Text(
                  widget.senderName!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
              ],

              // Show error message if there's an error
              if (_hasError && _errorMsg.isNotEmpty) ...[
                SizedBox(
                  width: 150,
                  child: Text(
                    _isDownloading ? 'Downloading...' : _errorMsg,
                    style: TextStyle(
                      fontSize: 10,
                      color: _isDownloading ? Colors.blue : Colors.red,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
              ],

              SizedBox(
                width: 150,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Waveform
                    RectangleWaveform(
                      samples: _generatedWaveform,
                      height: 40,
                      width: 150,
                      activeColor: _hasError
                          ? Colors.red.withOpacity(0.6)
                          : Theme.of(context).primaryColor,
                      inactiveColor: _hasError
                          ? Colors.red.withOpacity(0.3)
                          : (isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                      maxDuration: _duration,
                      elapsedDuration: safePosition,
                      isRoundedRectangle: true,
                      isCentered: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          // Duration
          Text(
            _isPlaying
                ? _formatDuration(safePosition)
                : _formatDuration(_duration),
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
