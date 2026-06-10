import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class ObdData {
  final int rpm;
  final double throttle;
  final bool throttleValid; // 車がアクセル開度(0111)に応答しない場合は false
  ObdData({required this.rpm, required this.throttle, this.throttleValid = true});
}

class ObdService {
  BluetoothConnection? _connection;
  final _dataController = StreamController<ObdData>.broadcast();
  Stream<ObdData> get dataStream => _dataController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  String _buffer = '';
  Completer<String>? _pending;
  bool _polling = false;
  int _rpm = 0;
  double _throttle = 0.0;
  bool _throttleSupported = true;
  int _throttleFails = 0;

  // プロトコルごとの初期化コマンド。
  // 'toyota' はトヨタM-OBD(K-Line)用カスタム初期化。
  //   H16ヴォクシー等のCAN以前のトヨタ車はこの設定でないとECUが応答しない。
  //   ATIB96  : ISO通信を9600bpsに設定
  //   ATIIA13 : イニシャライズアドレスを 0x13 に設定
  //   ATSH8113F1 : ヘッダーを 81 13 F1 (対象ECU 0x13) に設定
  //   ATSPA4  : プロトコルをKWP(5ボーイニシャル)+自動フォールバックに設定
  //   ATSW00  : ウェイクアップメッセージ停止
  static const Map<String, List<String>> _presets = {
    'toyota': [
      'ATE0', 'ATL0', 'ATH1', 'ATST96', 'ATAT1',
      'ATIB96', 'ATIIA13', 'ATSH8113F1', 'ATSPA4', 'ATSW00',
    ],
    'std': ['ATE0', 'ATL0', 'ATH1', 'ATST96', 'ATAT1', 'ATSP0'],
    'can': ['ATE0', 'ATL0', 'ATH1', 'ATST32', 'ATAT1', 'ATSP6'],
  };

  static const Map<String, String> presetNames = {
    'toyota': 'トヨタ K-Line (M-OBD)',
    'std': '標準OBD2 (自動検出)',
    'can': 'CAN (ISO 15765-4)',
  };

  Future<void> connect(BluetoothDevice device, String mode) async {
    _log('--- ${device.name ?? device.address} に接続します ---');
    _connection = await BluetoothConnection.toAddress(device.address).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw 'Bluetooth接続タイムアウト。アダプターの電源を確認してください',
    );
    _connection!.input!.listen(
      _onRaw,
      onDone: () {
        _polling = false;
        _log('!! Bluetooth接続が切断されました');
      },
    );

    // 'auto' はトヨタK-Line → 標準 → CAN の順に全部試す
    final order = mode == 'auto' ? ['toyota', 'std', 'can'] : [mode];
    for (final id in order) {
      _log('=== プロトコル試行: ${presetNames[id]} ===');
      if (await _tryInit(_presets[id]!)) {
        _log('=== 接続成功: ${presetNames[id]} ===');
        _startPolling();
        return;
      }
      _log('=== ${presetNames[id]} では応答なし ===');
    }
    throw 'ECUと通信できませんでした。キーON(またはエンジン始動)を確認して再試行してください';
  }

  Future<bool> _tryInit(List<String> commands) async {
    try {
      // ATZでアダプターを完全リセット（前回試行の設定を消す）
      await _send('ATZ', const Duration(seconds: 8));
      await Future.delayed(const Duration(milliseconds: 500));

      for (final cmd in commands) {
        final res = await _send(cmd, const Duration(seconds: 5));
        if (res.contains('?')) {
          _log('!! $cmd は未対応の可能性（続行します）');
        }
      }

      // 最初のPID要求でバス初期化が走る。
      // K-Lineの5ボーイニシャルは応答まで5秒以上かかるため長めに待つ。
      for (int attempt = 1; attempt <= 2; attempt++) {
        final res = await _send('010C', const Duration(seconds: 20));
        if (_parseRpm(res) != null) return true;
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    } catch (e) {
      _log('!! 初期化中のエラー: $e');
    }
    return false;
  }

  void _startPolling() {
    _polling = true;
    _throttleSupported = true;
    _throttleFails = 0;
    _pollLoop();
  }

  Future<void> _pollLoop() async {
    while (_polling && (_connection?.isConnected ?? false)) {
      // 回転数
      try {
        final res = await _send('010C', const Duration(seconds: 4));
        final rpm = _parseRpm(res);
        if (rpm != null) _rpm = rpm;
      } catch (_) {
        // タイムアウトしても止めずに次の周回へ
      }
      if (!_polling) break;

      // アクセル開度（非対応の車なら5回失敗した時点で諦めて回転数のみにする）
      if (_throttleSupported) {
        try {
          final res = await _send('0111', const Duration(seconds: 4));
          final th = _parseThrottle(res);
          if (th != null) {
            _throttle = th;
            _throttleFails = 0;
          } else {
            _countThrottleFail();
          }
        } catch (_) {
          _countThrottleFail();
        }
      }

      _dataController.add(ObdData(
        rpm: _rpm,
        throttle: _throttle,
        throttleValid: _throttleSupported,
      ));
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  void _countThrottleFail() {
    _throttleFails++;
    if (_throttleFails >= 5) {
      _throttleSupported = false;
      _log('!! アクセル開度(0111)は非対応のようです。回転数のみで動作します');
    }
  }

  Future<String> _send(String cmd, Duration timeout) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw '未接続です';
    }
    final completer = Completer<String>();
    _pending = completer;
    _log('-> $cmd');
    conn.output.add(Uint8List.fromList('$cmd\r'.codeUnits));
    await conn.output.allSent;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _log('!! 応答タイムアウト ($cmd)');
      rethrow;
    } finally {
      if (identical(_pending, completer)) _pending = null;
    }
  }

  void _onRaw(Uint8List data) {
    // ELM327の出力はASCIIのみ
    _buffer += String.fromCharCodes(data);
    while (true) {
      final idx = _buffer.indexOf('>');
      if (idx < 0) break;
      final chunk = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (chunk.isNotEmpty) {
        _log('<- ${chunk.replaceAll(RegExp(r'[\r\n]+'), ' / ')}');
      }
      final p = _pending;
      if (p != null && !p.isCompleted) {
        p.complete(chunk);
      }
    }
  }

  /// 応答文字列から16進バイト列を取り出す。
  /// ATH1(ヘッダー表示ON)のため "86 F1 13 41 0C 1A F8 E9" のような形式になる。
  /// CAN応答の "7E8" のような3桁IDは読み飛ばす。
  List<String> _hexTokens(String response) {
    final tokens = <String>[];
    for (final line in response.split(RegExp(r'[\r\n]+'))) {
      for (final raw in line.trim().split(RegExp(r'\s+'))) {
        final t = raw.toUpperCase();
        if (RegExp(r'^[0-9A-F]{2}$').hasMatch(t)) {
          tokens.add(t);
        } else if (RegExp(r'^[0-9A-F]{4,}$').hasMatch(t) && t.length.isEven) {
          // スペースなしで連結されて来た場合は2桁ずつに分割
          for (int i = 0; i + 1 < t.length; i += 2) {
            tokens.add(t.substring(i, i + 2));
          }
        }
      }
    }
    return tokens;
  }

  /// "41 0C A B" を探して RPM = (A*256+B)/4 を返す。見つからなければ null。
  int? _parseRpm(String response) {
    final t = _hexTokens(response);
    for (int i = 0; i + 3 < t.length; i++) {
      if (t[i] == '41' && t[i + 1] == '0C') {
        final a = int.parse(t[i + 2], radix: 16);
        final b = int.parse(t[i + 3], radix: 16);
        final rpm = ((a * 256) + b) ~/ 4;
        if (rpm >= 0 && rpm <= 12000) return rpm;
      }
    }
    return null;
  }

  /// "41 11 A" を探して開度% = A*100/255 を返す。見つからなければ null。
  double? _parseThrottle(String response) {
    final t = _hexTokens(response);
    for (int i = 0; i + 2 < t.length; i++) {
      if (t[i] == '41' && t[i + 1] == '11') {
        final a = int.parse(t[i + 2], radix: 16);
        final pct = a * 100.0 / 255.0;
        if (pct >= 0 && pct <= 100) return pct;
      }
    }
    return null;
  }

  void _log(String msg) {
    if (!_logController.isClosed) _logController.add(msg);
  }

  Future<void> disconnect() async {
    _polling = false;
    final p = _pending;
    if (p != null && !p.isCompleted) {
      p.completeError(TimeoutException('切断'));
    }
    _pending = null;
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
  }

  void dispose() {
    disconnect();
    _dataController.close();
    _logController.close();
  }
}
