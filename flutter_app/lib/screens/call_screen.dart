import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants.dart';
import '../core/socket_client.dart';
import '../models/chat_user.dart';

class CallScreen extends StatefulWidget {
  final ChatUser user;
  final bool isCaller;

  const CallScreen({super.key, required this.user, required this.isCaller});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _remoteConnected = false;
  bool _callEnded = false;

  static const _iceServers = {
    'iceServers': [
      {
        'urls': 'turn:153.127.16.117:2222?transport=tcp',
        'username': 'sakura',
        'credential': 'sakura123456',
      },
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    _localRenderer.srcObject = _localStream;
    if (mounted) setState(() {});

    await _createPeerConnection();
    _listenSignalling();

    if (widget.isCaller) {
      await _makeOffer();
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() => _remoteConnected = true);
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      SocketClient.instance.emit(AppConstants.rtcMessage, {
        'to': widget.user.deviceId,
        'type': 'candidate',
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall();
      }
    };
  }

  void _listenSignalling() {
    final socket = SocketClient.instance;

    socket.on(AppConstants.rtcMessage, (data) async {
      if (data == null) return;
      dynamic decoded = data;
      if (data is String) {
        try { decoded = jsonDecode(data); } catch (_) { return; }
      }
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final type = map['type'];

      if (type == 'offer') {
        final desc = RTCSessionDescription(map['sdp'], 'offer');
        await _peerConnection?.setRemoteDescription(desc);
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        socket.emit(AppConstants.rtcMessage, {
          'to': widget.user.deviceId,
          'type': 'answer',
          'sdp': answer.sdp,
        });
        if (mounted) setState(() => _remoteConnected = true);
      } else if (type == 'answer') {
        final desc = RTCSessionDescription(map['sdp'], 'answer');
        await _peerConnection?.setRemoteDescription(desc);
        if (mounted) setState(() => _remoteConnected = true);
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          map['candidate']['candidate'],
          map['candidate']['sdpMid'],
          map['candidate']['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      } else if (type == 'bye') {
        _endCall();
      }
    });
  }

  Future<void> _makeOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    SocketClient.instance.emit(AppConstants.rtcMessage, {
      'to': widget.user.deviceId,
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  void _toggleMute() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _isMuted);
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _isCameraOff);
    setState(() => _isCameraOff = !_isCameraOff);
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
      setState(() => _isFrontCamera = !_isFrontCamera);
    }
  }

  void _endCall() {
    if (_callEnded) return;
    _callEnded = true;

    SocketClient.instance.emit(AppConstants.rtcMessage, {
      'to': widget.user.deviceId,
      'type': 'bye',
    });

    SocketClient.instance.off(AppConstants.rtcMessage);

    _localStream?.dispose();
    _peerConnection?.close();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    SocketClient.instance.off(AppConstants.rtcMessage);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (full screen)
          _remoteConnected
              ? RTCVideoView(_remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white24,
                        child: Text(
                          widget.user.displayName.isNotEmpty
                              ? widget.user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 36, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.user.displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isCaller ? 'Calling…' : 'Incoming call',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),

          // Local video (PiP top-right)
          Positioned(
            top: 48,
            right: 16,
            width: 100,
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _isCameraOff
                  ? Container(
                      color: Colors.grey[900],
                      child: const Icon(Icons.videocam_off,
                          color: Colors.white54),
                    )
                  : RTCVideoView(
                      _localRenderer,
                      mirror: _isFrontCamera,
                      objectFit: RTCVideoViewObjectFit
                          .RTCVideoViewObjectFitCover,
                    ),
            ),
          ),

          // Controls
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _controlBtn(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  color: _isMuted ? Colors.red : Colors.white24,
                  onTap: _toggleMute,
                ),
                _controlBtn(
                  icon: Icons.call_end,
                  label: 'End',
                  color: Colors.red,
                  size: 64,
                  onTap: _endCall,
                ),
                _controlBtn(
                  icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: _isCameraOff ? 'Cam on' : 'Cam off',
                  color: _isCameraOff ? Colors.red : Colors.white24,
                  onTap: _toggleCamera,
                ),
                _controlBtn(
                  icon: Icons.flip_camera_ios,
                  label: 'Flip',
                  color: Colors.white24,
                  onTap: _switchCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 52,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
