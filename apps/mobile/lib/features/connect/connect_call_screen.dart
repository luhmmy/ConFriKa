import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/network/api_client.dart';
import '../../core/services/webrtc_service.dart';
import '../../core/theme/confrika_theme.dart';

enum CallState { idle, connecting, ringing, connected, ended, failed }

class ConnectCallScreen extends StatefulWidget {
  final String? initialCallee;
  const ConnectCallScreen({super.key, this.initialCallee});

  @override
  State<ConnectCallScreen> createState() => _ConnectCallScreenState();
}

class _ConnectCallScreenState extends State<ConnectCallScreen> {
  final _api = ConFriKaApiClient.instance;
  final _rtc = ConFriKaWebRTCService();
  final _calleeCtrl = TextEditingController();

  CallState _state = CallState.idle;
  String _status = 'Ready to call';
  String? _error;
  WebSocketChannel? _ws;
  String? _peer;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCallee != null) _calleeCtrl.text = widget.initialCallee!;
  }

  @override
  void dispose() {
    _cleanup();
    _calleeCtrl.dispose();
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _ws?.sink.close();
    _ws = null;
    await _rtc.disposeSession();
  }

  Future<void> _startCall() async {
    final callee = _calleeCtrl.text.trim();
    if (callee.isEmpty) {
      setState(() => _error = 'Enter a @username to call.');
      return;
    }
    setState(() {
      _error = null;
      _state = CallState.connecting;
      _status = 'Requesting microphone...';
      _peer = callee.startsWith('@') ? callee : '@$callee';
    });

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _state = CallState.failed;
        _error = 'Microphone permission is required for calls.';
      });
      return;
    }

    try {
      // 1. Real ICE servers (STUN + time-limited TURN) from the backend.
      final ice = await _api.iceServers();
      _rtc.setIceServers(ice['ice_servers'] as List<dynamic>);

      // 2. Register call session server-side.
      setState(() => _status = 'Connecting signaling...');
      final session = await _api.initiateCall(_peer!);
      if (session['status'] == 'coming_soon') {
        setState(() {
          _state = CallState.failed;
          _error = session['message']?.toString() ?? 'Not available.';
        });
        return;
      }

      // 3. Open signaling socket.
      _ws = WebSocketChannel.connect(
        Uri.parse('${AppConfig.wsBaseUrl}/ws/calls?token=${_api.authToken}'),
      );
      _ws!.stream.listen(_onSignal, onError: (_) {}, cancelOnError: false);

      // 4. WebRTC callbacks -> relay to peer.
      _rtc.onIceCandidateGenerated = (c) => _sendSignal('candidate', {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          });
      _rtc.onConnectionStateChanged = (s) {
        if (!mounted) return;
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _state = CallState.connected;
            _status = 'Connected';
          });
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() {
            _state = CallState.ended;
            _status = 'Call ended';
          });
        }
      };

      // 5. Create and send the SDP offer.
      await _rtc.createPeerConnectionSession();
      final offer = await _rtc.createOffer();
      _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});

      setState(() {
        _state = CallState.ringing;
        _status = 'Ringing $_peer...';
      });
    } on ApiException catch (e) {
      setState(() {
        _state = CallState.failed;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _state = CallState.failed;
        _error = 'Call failed: $e';
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
        await _rtc.setRemoteAnswer(
            RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?));
      } else if (type == 'candidate') {
        await _rtc.addRemoteIceCandidate(RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        ));
      } else if (type == 'hangup' || type == 'reject') {
        _endCall();
      } else if (type == 'offer') {
        // Incoming call while on this screen: answer it.
        _peer = data['sender'] as String?;
        await _rtc.createPeerConnectionSession();
        final answer = await _rtc.createAnswer(
            RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?));
        _sendSignal('answer', {'sdp': answer.sdp, 'type': answer.type});
        if (mounted) setState(() => _state = CallState.connected);
      }
    } catch (_) {}
  }

  void _toggleMute() {
    _rtc.toggleMute();
    setState(() => _muted = _rtc.isMuted);
  }

  Future<void> _endCall() async {
    _sendSignal('hangup', {});
    await _cleanup();
    if (mounted) {
      setState(() {
        _state = CallState.ended;
        _status = 'Call ended';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _state == CallState.connecting ||
        _state == CallState.ringing ||
        _state == CallState.connected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('In-App Voice Call',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const Text('Encrypted peer-to-peer WebRTC voice over STUN/TURN',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 14),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _calleeCtrl,
                  enabled: !active,
                  decoration: InputDecoration(
                    labelText: 'Call @username',
                    prefixIcon: const Icon(Icons.alternate_email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _state == CallState.connected
                            ? const Color(0xFF10B981)
                            : (active ? ConFriKaColors.sunsetOrange : Colors.grey),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
                const SizedBox(height: 12),
                if (!active)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startCall,
                      style: FilledButton.styleFrom(
                        backgroundColor: ConFriKaColors.savannaGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.phone_in_talk),
                      label: const Text('Start In-App Call',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _toggleMute,
                          icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                          label: Text(_muted ? 'Unmute' : 'Mute'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _endCall,
                          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                          icon: const Icon(Icons.call_end),
                          label: const Text('Hang up'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          color: ConFriKaColors.oceanBlue.withValues(alpha: 0.05),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How calling works',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                SizedBox(height: 6),
                Text(
                  '• Both people must be signed in with ConFriKa open.\n'
                  '• Audio is peer-to-peer via WebRTC; media never passes through our servers (only signaling does).\n'
                  '• Live in-call speech translation is on the roadmap — use the Translate tab for text today.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
