import 'dart:async';
import 'dart:convert';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class ObdData {
  final int rpm;
  final double throttle;
  ObdData({required this.rpm, required this.throttle});
}

class ObdService {
  BluetoothConnection? _connection;
  final _dataController = StreamController<ObdData>.broadcast();
  Stream<ObdData> get dataStream => _dataController.stream;

  String _buffer = '';
  bool _initialized = false;
  bool _requesting = false;
  int _rpm = 0;
  double _throttle = 0.0;
  bool _waitingRpm = false;

  Future<void> connect(BluetoothDevice device) async {
    _connection = await BluetoothConnection.toAddress(device.address);
    _connection!.input!.listen(_onData);
    await _initialize();
  }

  Future<void> _initialize() async {
    await _sendCommand('ATZ');
    await Future.delayed(const Duration(milliseconds: 1000));
    await _sendCommand('ATE0');
    await Future.delayed(const Duration(milliseconds: 300));
    await _sendCommand('ATL0');
    await Future.delayed(const Duration(milliseconds: 300));
    await _sendCommand('ATH0');
    await Future.delayed(const Duration(milliseconds: 300));
    // ISO 14230-4 KWP (ファストイニット) H16年式ヴォクシー用
    // うまく繋がらない場合は ATSP4 (5ボーイニット) に変える
    await _sendCommand('ATSP5');
    await Future.delayed(const Duration(milliseconds: 500));
    // KWPはヘッダー形式が違うのでヘッダー非表示を念押し
    await _sendCommand('ATH0');
    await Future.delayed(const Duration(milliseconds: 300));
    _initialized = true;
    _startPolling();
  }

  void _startPolling() {
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_initialized || _requesting) return;
      if (_connection == null || !(_connection!.isConnected)) {
        timer.cancel();
        return;
      }
      _pollNext();
    });
  }

  bool _nextIsRpm = true;

  Future<void> _pollNext() async {
    _requesting = true;
    if (_nextIsRpm) {
      _waitingRpm = true;
      await _sendCommand('010C');
    } else {
      _waitingRpm = false;
      await _sendCommand('0111');
    }
    _nextIsRpm = !_nextIsRpm;
  }

  Future<void> _sendCommand(String cmd) async {
    if (_connection == null) return;
    _connection!.output.add(Uint8List.fromList(utf8.encode('$cmd\r')));
    await _connection!.output.allSent;
  }

  void _onData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);

    if (!_buffer.contains('>')) return;

    final response = _buffer.replaceAll('>', '').trim();
    _buffer = '';
    _requesting = false;

    if (_waitingRpm) {
      _rpm = _parseRpm(response);
    } else {
      _throttle = _parseThrottle(response);
      _dataController.add(ObdData(rpm: _rpm, throttle: _throttle));
    }
  }

  int _parseRpm(String response) {
    try {
      final cleaned = response.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      // 410C XX XX の形式を探す
      for (int i = 0; i < parts.length - 1; i++) {
        if (parts[i].toUpperCase() == '0C' ||
            (i > 0 && parts[i-1].toUpperCase() == '41' && parts[i].toUpperCase() == '0C')) {
          int aIdx = (parts[i].toUpperCase() == '0C') ? i + 1 : i + 1;
          if (aIdx + 1 < parts.length) {
            final a = int.parse(parts[aIdx], radix: 16);
            final b = int.parse(parts[aIdx + 1], radix: 16);
            return ((a * 256) + b) ~/ 4;
          }
        }
      }
      // シンプルな後ろから2バイト取得
      if (parts.length >= 4) {
        final a = int.parse(parts[parts.length - 2], radix: 16);
        final b = int.parse(parts[parts.length - 1], radix: 16);
        final rpm = ((a * 256) + b) ~/ 4;
        if (rpm >= 0 && rpm <= 9000) return rpm;
      }
    } catch (_) {}
    return _rpm; // 失敗したら前回値を維持
  }

  double _parseThrottle(String response) {
    try {
      final cleaned = response.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final a = int.parse(parts[parts.length - 1], radix: 16);
        final pct = a * 100.0 / 255.0;
        if (pct >= 0 && pct <= 100) return pct;
      }
    } catch (_) {}
    return _throttle;
  }

  Future<void> disconnect() async {
    _initialized = false;
    await _connection?.close();
    _connection = null;
  }

  void dispose() {
    _dataController.close();
    disconnect();
  }
}
