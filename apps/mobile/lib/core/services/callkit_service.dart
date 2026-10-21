import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';

/// ConFriKa Native CallKit & Android Telecom Service
/// Provides native incoming call ringing screen, lock-screen notifications,
/// and hardware phone call controls (AirPods, Bluetooth, vehicle carplay/android auto).
class ConFriKaCallKitService {
  static final ConFriKaCallKitService _instance = ConFriKaCallKitService._internal();
  factory ConFriKaCallKitService() => _instance;
  ConFriKaCallKitService._internal();

  Function(String callUuid, Map<String, dynamic>? extra)? onCallAccepted;
  Function(String callUuid)? onCallDeclined;
  Function(String callUuid)? onCallEnded;

  /// Initialize listeners for native CallKit / Android Telecom events
  void initialize() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      switch (event.event) {
        case Event.actionCallAccept:
          debugPrint('Native Call Accepted: ${event.body}');
          final uuid = event.body['id'] as String? ?? '';
          final extra = event.body['extra'] as Map<String, dynamic>?;
          onCallAccepted?.call(uuid, extra);
          break;
        case Event.actionCallDecline:
          debugPrint('Native Call Declined: ${event.body}');
          final uuid = event.body['id'] as String? ?? '';
          onCallDeclined?.call(uuid);
          break;
        case Event.actionCallEnded:
          debugPrint('Native Call Ended: ${event.body}');
          final uuid = event.body['id'] as String? ?? '';
          onCallEnded?.call(uuid);
          break;
        case Event.actionCallTimeout:
          debugPrint('Native Call Timed Out: ${event.body}');
          break;
        default:
          break;
      }
    });
  }

  /// Triggers native incoming call UI (like a cellular phone call)
  Future<void> displayIncomingCall({
    required String callerName,
    required String callerUsername,
    required String callerDialect,
    required String countryFlag,
    String? callerAvatarUrl,
    Map<String, dynamic>? extraData,
  }) async {
    final callUuid = const Uuid().v4();
    final callKitParams = CallKitParams(
      id: callUuid,
      nameCaller: '$callerName ($countryFlag $callerDialect)',
      appName: 'ConFriKa',
      avatar: callerAvatarUrl ?? 'https://confrika.com/assets/images/default_avatar.png',
      handle: callerUsername,
      type: 0, // 0: Audio Call, 1: Video Call
      duration: 45000, // 45 seconds ring timeout
      textAccept: 'Answer with Translation',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'callerUsername': callerUsername,
        'callerDialect': callerDialect,
        ...?extraData,
      },
      headers: <String, dynamic>{'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D4C85', // ConFriKa Deep Atlantic Blue
        actionColor: '#288240', // ConFriKa Emerald Green
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'ConFriKa In-App Voice Calls',
        missedCallNotificationChannelName: 'ConFriKa Missed Calls',
      ),
      ios: const IOSParams(
        iconName: 'CallKitIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  /// Ends the active native call screen
  Future<void> endCall(String callUuid) async {
    await FlutterCallkitIncoming.endCall(callUuid);
  }

  /// Clears all call screens
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }
}
