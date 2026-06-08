import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';
import 'sound_engine.dart';

void main() {
  runApp(const FerrariSoundApp());
}

class FerrariSoundApp extends StatelessWidget {
  const FerrariSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ferrari Sound',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFCC0000),
          secondary: Color(0xFFFFD700),
        ),
        scaffoldBackgroundColor: const Color(0xFF111111),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ObdService _obd = ObdService();
  final SoundEngine _sound = SoundEngine();

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selected;
  bool _connected = false;
  bool _connecting = false;
  bool _soundOn = false;
  int _rpm = 0;
  double _throttle = 0.0;
  String _status = '接続待ち';
  StreamSubscription? _sub;
  String _selectedProtocol = 'ATSP0';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    await _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() => _status = 'デバイス検索中...');
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _devices = bonded;
        _status = bonded.isEmpty ? 'ペアリング済みデバイスなし' : 'デバイスを選択してください';
      });
    } catch (e) {
      setState(() => _status = 'Bluetooth エラー: $e');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _connecting = true;
      _status = '${device.name} に接続中...';
    });
    try {
      await _obd.connect(device, _selectedProtocol);
      await _sound.init();
      _sub = _obd.dataStream.listen(_onData);
      setState(() {
        _connected = true;
        _connecting = false;
        _soundOn = true;
        _status = '接続完了！';
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _status = '接続失敗: $e';
      });
    }
  }

  void _onData(ObdData data) {
    setState(() {
      _rpm = data.rpm;
      _throttle = data.throttle;
    });
    if (_soundOn) {
      _sound.update(data.rpm, data.throttle);
    }
  }

  Future<void> _disconnect() async {
    _sub?.cancel();
    await _sound.stop();
    await _obd.disconnect();
    setState(() {
      _connected = false;
      _soundOn = false;
      _rpm = 0;
      _throttle = 0;
      _status = '切断しました';
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sound.dispose();
    _obd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFCC0000),
        title: const Text('🏎 Ferrari Sound OBD2',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled, color: Colors.white),
              onPressed: _disconnect,
              tooltip: '切断',
            ),
        ],
      ),
      body: _connected ? _buildDashboard() : _buildDeviceList(),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF222222),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_status,
                    style: const TextStyle(color: Colors.white70)),
              ),
              if (_connecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1E1E1E),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('接続プロトコル:', style: TextStyle(color: Colors.white70)),
              DropdownButton<String>(
                value: _selectedProtocol,
                dropdownColor: const Color(0xFF222222),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'ATSP0', child: Text('オート（自動検出）')),
                  DropdownMenuItem(value: 'ATSP4', child: Text('ヴォクシー H16年 (5ボー - ATSP4)')),
                  DropdownMenuItem(value: 'ATSP5', child: Text('ヴォクシー H16年 (ファスト - ATSP5)')),
                  DropdownMenuItem(value: 'ATSP6', child: Text('フェラーリ・一般車 (CAN - ATSP6)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedProtocol = val);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bluetooth_searching,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('ICARPROとペアリングしてから\nアプリを開いてください',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('再検索'),
                        onPressed: _scanDevices,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFCC0000)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (ctx, i) {
                    final dev = _devices[i];
                    final isIcarPro = (dev.name ?? '').toLowerCase().contains('obd') ||
                        (dev.name ?? '').toLowerCase().contains('icar') ||
                        (dev.name ?? '').toLowerCase().contains('elm');
                    return ListTile(
                      leading: Icon(
                        Icons.bluetooth,
                        color: isIcarPro ? const Color(0xFFCC0000) : Colors.grey,
                      ),
                      title: Text(dev.name ?? '不明なデバイス',
                          style: TextStyle(
                              color: isIcarPro ? Colors.white : Colors.white70,
                              fontWeight: isIcarPro
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      subtitle: Text(dev.address,
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: isIcarPro
                          ? const Chip(
                              label: Text('OBD2',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.white)),
                              backgroundColor: Color(0xFFCC0000),
                            )
                          : null,
                      onTap: _connecting ? null : () => _connect(dev),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    final rpmPercent = (_rpm / 8000.0).clamp(0.0, 1.0);
    final rpmColor = _rpm < 3000
        ? Colors.green
        : _rpm < 6000
            ? Colors.orange
            : const Color(0xFFCC0000);

    return Column(
      children: [
        // ステータスバー
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.bluetooth_connected,
                  color: Colors.green, size: 16),
              const SizedBox(width: 8),
              Text(_selected?.name ?? 'ICARPRO',
                  style: const TextStyle(color: Colors.green, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _soundOn = !_soundOn),
                child: Row(
                  children: [
                    Icon(
                      _soundOn ? Icons.volume_up : Icons.volume_off,
                      color: _soundOn ? Colors.amber : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(_soundOn ? 'サウンドON' : 'サウンドOFF',
                        style: TextStyle(
                            color: _soundOn ? Colors.amber : Colors.grey,
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // RPMメーター
                const Text('エンジン回転数',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  '${_rpm.toString().padLeft(4, '0')} RPM',
                  style: TextStyle(
                    color: rpmColor,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                // RPMバー
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: rpmPercent,
                    minHeight: 20,
                    backgroundColor: const Color(0xFF333333),
                    valueColor: AlwaysStoppedAnimation<Color>(rpmColor),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('0', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    Text('2000', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    Text('4000', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    Text('6000', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    Text('8000', style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),

                const SizedBox(height: 40),

                // アクセル開度
                const Text('アクセル開度',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  '${_throttle.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _throttle / 100.0,
                    minHeight: 14,
                    backgroundColor: const Color(0xFF333333),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),

                const SizedBox(height: 48),

                // フェラーリロゴ的な装飾
                Text(
                  _rpm > 5000 ? '🔥 PRANCING HORSE 🔥' : '🏎 Ferrari Sound',
                  style: TextStyle(
                    color: _rpm > 5000 ? const Color(0xFFCC0000) : Colors.grey,
                    fontSize: _rpm > 5000 ? 18 : 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
