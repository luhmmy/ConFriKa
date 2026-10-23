import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/network/api_client.dart';
import '../../core/services/webrtc_service.dart';
import '../../core/theme/confrika_theme.dart';

enum CallPhase { dialing, ringing, incoming, connected, ended, failed }

/// Full-screen, WhatsApp-style voice call UI over the existing WebRTC stack.
/// Handles both outgoing calls and (when [incoming] is set) the accept/decline
/// screen for an inbound call.
class ActiveCallScreen extends StatefulWidget {
  final String calleeUsername;
  final String? displayName;
  final bool incoming;
  final Map<String, dynamic>? incomingOffer;

  const ActiveCallScreen({
    super.key,
    required this.calleeUsername,
    this.displayName,
    this.incoming = false,
    this.incomingOffer,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final _api = ConFriKaApiClient.instance;
  final _rtc = ConFriKaWebRTCService();

  late CallPhase _phase;
  String? _error;
  WebSocketChannel? _ws;
  String _peer = '';
  bool _muted = false;
  bool _speaker = false;

  Timer? _tick;
  Duration _elapsed = Duration.zero;

  String get _name =>
      widget.displayName ?? widget.calleeUsername.replaceFirst('@', '');

  @override
  void initState() {
    super.initState();
    _peer = widget.calleeUsername.startsWith('@')
        ? widget.calleeUsername
        : '@${widget.calleeUsername}';
    _phase = widget.incoming ? CallPhase.incoming : CallPhase.dialing;
    if (!widget.incoming) _startOutgoing();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cleanup();
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _ws?.sink.close();
    _ws = null;
    await _rtc.disposeSession();
  }

  void _startTimer() {
    _tick?.cancel();
    _elapsed = Duration.zero;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<bool> _ensureMic() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _phase = CallPhase.failed;
        _error = 'Microphone permission is required for calls.';
      });
      return false;
    }
    return true;
  }

  Future<void> _openSignaling() async {
    final ice = await _api.iceServers();
    _rtc.setIceServers(ice['ice_servers'] as List<dynamic>);
    _ws = WebSocketChannel.connect(
      Uri.parse('${AppConfig.wsBaseUrl}/ws/calls?token=${_api.authToken}'),
    );
    _ws!.stream.listen(_onSignal, onError: (_) {}, cancelOnError: false);

    _rtc.onIceCandidateGenerated = (c) => _sendSignal('candidate', {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
    _rtc.onConnectionStateChanged = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _phase = CallPhase.connected);
        _startTimer();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _finish('Call ended');
      }
    };
  }

  Future<void> _startOutgoing() async {
    if (!await _ensureMic()) return;
    try {
      final session = await _api.initiateCall(_peer);
      if (session['status'] == 'coming_soon') {
        setState(() {
          _phase = CallPhase.failed;
          _error = session['message']?.toString() ?? 'Not available.';
        });
        return;
      }
      await _openSignaling();
      await _rtc.createPeerConnectionSession();
      final offer = await _rtc.createOffer();
      _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});
      if (mounted) setState(() => _phase = CallPhase.ringing);
    } on ApiException catch (e) {
      setState(() {
        _phase = CallPhase.failed;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _phase = CallPhase.failed;
        _error = 'Call failed: $e';
      });
    }
  }

  Future<void> _acceptIncoming() async {
    if (!await _ensureMic()) return;
    try {
      await _openSignaling();
      final offer = widget.incomingOffer ?? {};
      await _rtc.createPeerConnectionSession();
      final answer = await _rtc.createAnswer(
        RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
      );
      _sendSignal('answer', {'sdp': answer.sdp, 'type': answer.type});
      if (mounted) setState(() => _phase = CallPhase.connected);
      _startTimer();
    } catch (e) {
      setState(() {
        _phase = CallPhase.failed;
        _error = 'Could not answer: $e';
      });
    }
  }

  void _sendSignal(String type, Map<String, dynamic> payload) {
    _ws?.sink.add(jsonEncode({
      'target': _peer,
      'signal_type': type,
      'payload': payload,
    }));
  }

  Future<void> _onSignal(dynamic raw) async {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['signal_type'];
      final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      if (type == 'answer') {
        await _rtc.setRemoteAnswer(RTCSessionDescription(
            payload['sdp'] as String?, payload['type'] as String?));
      } else if (type == 'candidate') {
        await _rtc.addRemoteIceCandidate(RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        ));
      } else if (type == 'hangup' || type == 'reject') {
        _finish(type == 'reject' ? 'Call declined' : 'Call ended');
      }
    } catch (_) {}
  }

  void _toggleMute() {
    _rtc.toggleMute();
    setState(() => _muted = _rtc.isMuted);
  }

  Future<void> _toggleSpeaker() async {
    await _rtc.setSpeakerphone(!_speaker);
    setState(() => _speaker = _rtc.isSpeakerOn);
  }

  Future<void> _hangUp() async {
    _sendSignal('hangup', {});
    _finish('Call ended');
  }

  Future<void> _decline() async {
    _sendSignal('reject', {});
    _finish('Declined');
  }

  void _finish(String _) {
    _tick?.cancel();
    _cleanup();
    if (mounted) {
      setState(() => _phase = CallPhase.ended);
      // Leave the call screen shortly after it ends.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  String get _statusText {
    switch (_phase) {
      case CallPhase.dialing:
        return 'Calling…';
      case CallPhase.ringing:
        return 'Ringing…';
      case CallPhase.incoming:
        return 'Incoming ConFriKa call';
      case CallPhase.connected:
        return _fmt(_elapsed);
      case CallPhase.ended:
        return 'Call ended';
      case CallPhase.failed:
        return _error ?? 'Call failed';
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ConFriKaColors.deepSlate,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF123B5E), ConFriKaColors.deepSlate],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, size: 12, color: Colors.white54),
                  const SizedBox(width: 5),
                  Text('End-to-end encrypted',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12)),
                ],
              ),
              const SizedBox(height: 40),
              _Avatar(name: _name, pulsing: _phase == CallPhase.ringing ||
                  _phase == CallPhase.dialing ||
                  _phase == CallPhase.incoming),
              const SizedBox(height: 24),
              Text(_name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_statusText,
                  style: TextStyle(
                      color: _phase == CallPhase.connected
                          ? ConFriKaColors.savannaGreen
                          : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              _controls(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    if (_phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end,
            color: Colors.redAccent,
            label: 'Decline',
            onTap: _decline,
            big: true,
          ),
          _RoundButton(
            icon: Icons.call,
            color: ConFriKaColors.savannaGreen,
            label: 'Accept',
            onTap: _acceptIncoming,
            big: true,
          ),
        ],
      );
    }

    final inCall = _phase == CallPhase.connected ||
        _phase == CallPhase.ringing ||
        _phase == CallPhase.dialing;
    return Column(
      children: [
        if (inCall)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(
                icon: _muted ? Icons.mic_off : Icons.mic,
                color: _muted ? Colors.white : Colors.white24,
                iconColor: _muted ? Colors.black : Colors.white,
                label: _muted ? 'Unmute' : 'Mute',
                onTap: _toggleMute,
              ),
              _RoundButton(
                icon: _speaker ? Icons.volume_up : Icons.volume_down,
                color: _speaker ? Colors.white : Colors.white24,
                iconColor: _speaker ? Colors.black : Colors.white,
                label: 'Speaker',
                onTap: _toggleSpeaker,
              ),
              _RoundButton(
                icon: Icons.translate,
                color: Colors.white24,
                iconColor: Colors.white,
                label: 'Translate',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Live call translation activates once the voice service is connected.'),
                  ));
                },
              ),
            ],
          ),
        const SizedBox(height: 28),
        _RoundButton(
          icon: Icons.call_end,
          color: Colors.redAccent,
          label: _phase == CallPhase.failed ? 'Close' : 'End',
          onTap: _hangUp,
          big: true,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool pulsing;
  const _Avatar({required this.name, required this.pulsing});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '·';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ConFriKaColors.oceanBlue,
        border: Border.all(
            color: Colors.white.withValues(alpha: pulsing ? 0.35 : 0.15),
            width: 4),
        boxShadow: [
          if (pulsing)
            BoxShadow(
                color: ConFriKaColors.oceanBlue.withValues(alpha: 0.5),
                blurRadius: 40,
                spreadRadius: 6),
        ],
      ),
      alignment: Alignment.center,
      child: Text(_initials,
          style: const TextStyle(
              color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool big;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 68.0 : 58.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: big ? 32 : 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
