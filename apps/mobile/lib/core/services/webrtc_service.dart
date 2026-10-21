import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ConFriKa WebRTC Service
/// Handles real-time voice call audio streaming and peer-to-peer signaling.
/// Specially optimized for African mobile carrier networks (MTN, Airtel, Safaricom, Vodacom)
/// traversing Carrier-Grade NAT (CGNAT) with resilient STUN/TURN fallback.
class ConFriKaWebRTCService {
  static final ConFriKaWebRTCService _instance = ConFriKaWebRTCService._internal();
  factory ConFriKaWebRTCService() => _instance;
  ConFriKaWebRTCService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // ICE Server Configuration. Populated at runtime from the backend's
  // /calls/ice-servers endpoint (STUN + time-limited TURN REST credentials).
  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'iceCandidatePoolSize': 4,
    'sdpSemantics': 'unified-plan',
  };

  /// Replaces the ICE server list with credentials fetched from the backend.
  void setIceServers(List<dynamic> servers) {
    if (servers.isNotEmpty) {
      _iceConfiguration['iceServers'] = servers;
    }
  }

  // Low-bandwidth audio constraints for 2G/3G/4G connectivity
  final Map<String, dynamic> _audioConstraints = {
    'audio': {
      'mandatory': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'highpassFilter': true,
      },
      'optional': [
        {'googEchoCancellation': true},
        {'googAutoGainControl': true},
        {'googNoiseSuppression': true},
        {'googHighpassFilter': true},
      ],
    },
    'video': false,
  };

  Function(RTCIceCandidate candidate)? onIceCandidateGenerated;
  Function(MediaStream stream)? onRemoteStreamReceived;
  Function(RTCPeerConnectionState state)? onConnectionStateChanged;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// Initializes the local microphone audio stream
  Future<MediaStream> initLocalAudioStream() async {
    if (_localStream != null) {
      return _localStream!;
    }
    _localStream = await navigator.mediaDevices.getUserMedia(_audioConstraints);
    return _localStream!;
  }

  /// Creates a WebRTC Peer Connection with African STUN/TURN configuration
  Future<RTCPeerConnection> createPeerConnectionSession() async {
    if (_peerConnection != null) {
      await disposeSession();
    }

    _peerConnection = await createPeerConnection(_iceConfiguration);

    // Ensure local stream is ready
    final stream = await initLocalAudioStream();
    stream.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, stream);
    });

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        onIceCandidateGenerated?.call(candidate);
      }
    };

    _peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStreamReceived?.call(_remoteStream!);
      }
    };

    _peerConnection?.onConnectionState = (state) {
      onConnectionStateChanged?.call(state);
    };

    return _peerConnection!;
  }

  /// Creates an SDP Offer for the caller
  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) {
      await createPeerConnectionSession();
    }
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });

    // Enforce OPUS low-latency bitrate configuration
    final modifiedSdp = _tuneSdpForAfricanCellular(offer.sdp ?? '');
    final description = RTCSessionDescription(modifiedSdp, offer.type);
    await _peerConnection!.setLocalDescription(description);
    return description;
  }

  /// Creates an SDP Answer for the callee
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription remoteOffer) async {
    if (_peerConnection == null) {
      await createPeerConnectionSession();
    }
    await _peerConnection!.setRemoteDescription(remoteOffer);

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });

    final modifiedSdp = _tuneSdpForAfricanCellular(answer.sdp ?? '');
    final description = RTCSessionDescription(modifiedSdp, answer.type);
    await _peerConnection!.setLocalDescription(description);
    return description;
  }

  /// Sets the remote SDP answer on caller's connection
  Future<void> setRemoteAnswer(RTCSessionDescription remoteAnswer) async {
    if (_peerConnection != null) {
      await _peerConnection!.setRemoteDescription(remoteAnswer);
    }
  }

  /// Adds a remote ICE candidate
  Future<void> addRemoteIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection != null) {
      await _peerConnection!.addCandidate(candidate);
    }
  }

  /// Mutes or unmutes the microphone
  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _isMuted = !_isMuted;
        audioTracks[0].enabled = !_isMuted;
      }
    }
  }

  /// Tunes SDP with OPUS codec parameters: FEC (Forward Error Correction) and DTX (Discontinuous Transmission)
  String _tuneSdpForAfricanCellular(String sdp) {
    if (sdp.contains('opus/48000')) {
      // African cellular optimization: useinbandfec=1 reduces packet drop impact, usedtx=1 conserves data
      return sdp.replaceAll(
        'useinbandfec=1',
        'useinbandfec=1;usedtx=1;maxaveragebitrate=16000',
      );
    }
    return sdp;
  }

  /// Cleans up and disposes the calling session
  Future<void> disposeSession() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;

      _remoteStream?.getTracks().forEach((track) => track.stop());
      await _remoteStream?.dispose();
      _remoteStream = null;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
      _isMuted = false;
    } catch (e) {
      debugPrint('Error disposing WebRTC session: $e');
    }
  }
}
