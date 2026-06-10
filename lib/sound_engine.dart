import 'package:audioplayers/audioplayers.dart';

// RPMごとに音のピッチを変える仕組み
// assets/sounds/ に以下のファイルを置く:
//   idle.mp3     (800RPM以下)
//   low.mp3      (800〜2500RPM)
//   mid.mp3      (2500〜5000RPM)
//   high.mp3     (5000RPM以上)

class SoundEngine {
  final AudioPlayer _player = AudioPlayer();
  String _currentFile = '';
  bool _running = false;
  bool _updating = false;
  double _lastRate = 0;
  double _lastVolume = 0;

  Future<void> init() async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    _running = true;
  }

  Future<void> update(int rpm, double throttle) async {
    if (!_running) return;
    // 前回の更新処理が終わる前に次が来たら捨てる（音切れ防止）
    if (_updating) return;
    _updating = true;
    try {
      final targetFile = _fileForRpm(rpm);
      final rate = _rateForRpm(rpm);

      if (targetFile != _currentFile) {
        _currentFile = targetFile;
        await _player.stop();
        await _player.play(AssetSource('sounds/$targetFile'));
        _lastRate = 0;
        _lastVolume = 0;
      }

      if ((rate - _lastRate).abs() > 0.02) {
        _lastRate = rate;
        await _player.setPlaybackRate(rate);
      }

      // アクセル開度で音量も変化
      final volume = (0.4 + (throttle / 100.0) * 0.6).clamp(0.4, 1.0);
      if ((volume - _lastVolume).abs() > 0.03) {
        _lastVolume = volume;
        await _player.setVolume(volume);
      }
    } finally {
      _updating = false;
    }
  }

  String _fileForRpm(int rpm) {
    if (rpm < 900) return 'idle.mp3';
    if (rpm < 2800) return 'low.mp3';
    if (rpm < 5000) return 'mid.mp3';
    return 'high.mp3';
  }

  double _rateForRpm(int rpm) {
    // 各ファイルの基準RPM付近で 1.0、帯域の上端で 1.8〜2.0 になるように。
    // 再生速度が上がる＝音が高くなる＝回転が上がった感じが出る。
    if (rpm < 900) {
      // idle: 500→0.7  800→1.1
      return (rpm / 700.0).clamp(0.6, 1.3);
    } else if (rpm < 2800) {
      // low: 900→0.6  1500→1.0  2800→1.9
      return (rpm / 1500.0).clamp(0.6, 2.0);
    } else if (rpm < 5000) {
      // mid: 2800→0.7  3700→1.0  5000→1.4
      return (rpm / 3700.0).clamp(0.6, 1.5);
    } else {
      // high: 5000→0.8  6500→1.0  8000→1.3
      return (rpm / 6500.0).clamp(0.7, 1.5);
    }
  }

  Future<void> stop() async {
    _running = false;
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
