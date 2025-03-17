import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:we_chat/services/notification/notification_service.dart';

typedef StreamStateCallback = void Function(MediaStream stream);

class Signaling {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302'
        ]
      },
      {
        // Free TURN server from Twilio (you should replace with your own in production)
        'urls': [
          'turn:global.turn.twilio.com:3478?transport=udp',
          'turn:global.turn.twilio.com:3478?transport=tcp',
          'turn:global.turn.twilio.com:443?transport=tcp'
        ],
        'username': 'YOUR_TWILIO_USERNAME',
        'credential': 'YOUR_TWILIO_CREDENTIAL'
      },
      {
        // Backup TURN server
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp'
        ],
        'username': 'YOUR_OPENRELAY_USERNAME',
        'credential': 'YOUR_OPENRELAY_CREDENTIAL'
      }
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
    'enableDtlsSrtp': true,
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceTransportPolicy': 'all',
    'offerExtmapAllowMixed': true,
    'enableRtpDataChannels': true,
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'RtpDataChannels': true},
      {'googIPv6': true}, // Enable IPv6 support
      {
        'googImprovedWifiBwe': true
      }, // Enable improved WiFi bandwidth estimation
      {'googScreencastMinBitrate': 400}, // Set minimum bitrate for screencast
    ]
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;
  bool hasNotifiedReceiver = false;
  Function? onCallEnded; // Add callback for call ending

  Future<String> createRoom(RTCVideoRenderer remoteRenderer) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc();
    hasNotifiedReceiver = false;

    print('Create PeerConnection with configuration: $configuration');

    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    // Code for collecting ICE candidates below
    var callerCandidatesCollection = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      print('Got candidate: ${candidate.toMap()}');
      callerCandidatesCollection.add(candidate.toMap());
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('Got remote track: ${event.streams[0]}');
      remoteRenderer.srcObject = event.streams[0];
      remoteStream = event.streams[0];
      onAddRemoteStream?.call(event.streams[0]);
    };
    // Finish Code for collecting ICE candidate

    // Add code for creating a room
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    print('Created offer: $offer');

    Map<String, dynamic> roomWithOffer = {'offer': offer.toMap()};

    await roomRef.set(roomWithOffer);
    roomId = roomRef.id;
    print('New room created with SDK offer. Room ID: $roomId');
    currentRoomText = 'Current room is $roomId - You are the caller!';
    // Created a Room

    // Listening for remote session description below
    roomRef.snapshots().listen((snapshot) async {
      print('Got updated room: ${snapshot.data()}');

      if (!snapshot.exists) {
        print("Room no longer exists");
        onCallEnded?.call();
        return;
      }

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

      // Check if room was marked as ended
      if (data['ended'] == true) {
        print("Call ended by other party");
        onCallEnded?.call();
        return;
      }

      if (peerConnection?.getRemoteDescription() != null &&
          data['answer'] != null) {
        var answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );

        print("Someone tried to connect");
        await peerConnection?.setRemoteDescription(answer);
      }
    });
    // Listening for remote session description above

    // Listen for remote Ice candidates below
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
          print('Got new remote ICE candidate: ${jsonEncode(data)}');
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
    // Listen for remote ICE candidates above

    return roomId!; // Return non-nullable roomId since we know it's set
  }

  Future<void> joinRoom(String roomId, RTCVideoRenderer remoteVideo) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    print(roomId);
    DocumentReference roomRef = db.collection('rooms').doc(roomId);

    // Add connection timeout handling
    bool connectionEstablished = false;
    Timer? connectionTimer;
    connectionTimer = Timer(const Duration(seconds: 30), () {
      if (!connectionEstablished) {
        print("Connection timeout - forcing hangup");
        hangUp(remoteVideo);
        onCallEnded?.call();
      }
    });

    // Add room listener for the joiner as well
    var roomSubscription = roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        print("Room no longer exists");
        await NotificationService().cancelCallNotification(roomId);
        onCallEnded?.call();
        return;
      }

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

      // Check if room was marked as ended
      if (data['ended'] == true) {
        print("Call ended by other party");
        await NotificationService().cancelCallNotification(roomId);
        onCallEnded?.call();
        return;
      }
    });

    var roomSnapshot = await roomRef.get();
    print('Got room ${roomSnapshot.exists}');

    if (!roomSnapshot.exists) {
      // Room doesn't exist anymore, clean up and return
      await NotificationService().cancelCallNotification(roomId);
      roomSubscription.cancel();
      return;
    }

    // Stop the ringtone when joining the room (answering the call)
    NotificationService().cancelCallNotification(roomId);
    hasNotifiedReceiver = true;

    print('Create PeerConnection with configuration: $configuration');
    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    // Add local tracks to peer connection
    if (localStream != null) {
      print('Adding local stream tracks to peer connection');
      localStream!.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });
    }

    // Set up ICE candidate handling
    var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      print('Got new local ICE candidate: ${candidate.toMap()}');
      calleeCandidatesCollection.add(candidate.toMap());
    };

    // Enhanced remote track handling
    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('Got remote track: ${event.streams[0]}');
      if (event.streams.isEmpty) {
        print('Warning: Received track but no streams');
        return;
      }

      // Verify and enable all tracks
      event.streams[0].getTracks().forEach((track) {
        print(
            'Processing remote track: ${track.kind}, enabled: ${track.enabled}');
        if (!track.enabled) {
          print('Enabling disabled track: ${track.kind}');
          track.enabled = true;
        }
      });

      // Verify audio tracks specifically
      var audioTracks = event.streams[0].getAudioTracks();
      print('Number of audio tracks: ${audioTracks.length}');
      for (var track in audioTracks) {
        track.enabled = true;
        print('Audio track enabled: ${track.enabled}');
      }

      // Verify video tracks specifically
      var videoTracks = event.streams[0].getVideoTracks();
      print('Number of video tracks: ${videoTracks.length}');
      for (var track in videoTracks) {
        track.enabled = true;
        print('Video track enabled: ${track.enabled}');
      }

      remoteVideo.srcObject = event.streams[0];
      remoteStream = event.streams[0];
      onAddRemoteStream?.call(event.streams[0]);

      // Mark connection as established
      connectionEstablished = true;
      connectionTimer?.cancel();
    };

    // Code for creating SDP answer
    var data = roomSnapshot.data() as Map<String, dynamic>;
    print('Got offer $data');
    var offer = data['offer'];
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );
    var answer = await peerConnection!.createAnswer();
    print('Created Answer $answer');

    await peerConnection!.setLocalDescription(answer);

    Map<String, dynamic> roomWithAnswer = {
      'answer': {'type': answer.type, 'sdp': answer.sdp}
    };

    await roomRef.update(roomWithAnswer);

    // Listen for remote ICE candidates
    roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var document in snapshot.docChanges) {
        if (document.type == DocumentChangeType.added) {
          var data = document.doc.data() as Map<String, dynamic>;
          print('Got new remote ICE candidate: $data');
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': []
      }
    };

    try {
      print('Requesting user media with constraints: $mediaConstraints');
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      print('Got local media stream');

      localVideo.srcObject = stream;
      localStream = stream;

      // Initialize remote video with null instead of empty stream
      remoteVideo.srcObject = null;

      // Ensure audio and video tracks are enabled
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        for (var track in audioTracks) {
          track.enabled = true;
        }
      }

      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        for (var track in videoTracks) {
          track.enabled = true;
        }
      }
    } catch (e) {
      print('Error accessing media devices: $e');
      rethrow;
    }
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    final tracks = localVideo.srcObject?.getTracks();
    if (tracks != null) {
      for (var track in tracks) {
        track.stop();
      }
    }

    if (peerConnection != null) {
      peerConnection!.close();
      peerConnection = null;
    }

    if (roomId != null) {
      // Mark the room as ended in Firestore
      var db = FirebaseFirestore.instance;
      var roomRef = db.collection('rooms').doc(roomId);

      // Update the room document to mark it as ended
      await roomRef.update({'ended': true});

      // Cancel any active notifications for this room
      await NotificationService().cancelCallNotification(roomId!);

      // Delete the room after a short delay to ensure all clients receive the 'ended' update
      await Future.delayed(const Duration(seconds: 2));
      await roomRef.delete();
    }

    localVideo.srcObject = null;
    localStream?.dispose();
    localStream = null;
    roomId = null;
    hasNotifiedReceiver = false;
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state change: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('Peer Connection Successfully Established!');

        // Verify streams after connection is established
        if (remoteStream != null) {
          print('Verifying remote stream tracks:');
          remoteStream!.getTracks().forEach((track) {
            print('Track kind: ${track.kind}, enabled: ${track.enabled}');
            track.enabled = true;
          });
        } else {
          print('Warning: No remote stream available after connection');
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        print('Peer Connection Failed or Disconnected');
        onCallEnded?.call();
      }
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      print('Signaling state change: $state');
    };

    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('ICE connection state change: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        print('ICE Connection Successful!');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        print('ICE Connection Failed or Disconnected');
        onCallEnded?.call();
      }
    };
  }
}
