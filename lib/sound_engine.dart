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

  Future<void> init() async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    _running = true;
  }

  Future<void> update(int rpm, double throttle) async {
    if (!_running) return;

    final targetFile = _fileForRpm(rpm);
    final rate = _rateForRpm(rpm);

    if (targetFile != _currentFile) {
      _currentFile = targetFile;
      await _player.stop();
      await _player.play(AssetSource('sounds/$targetFile'));
    }

    await _player.setPlaybackRate(rate);

    // アクセル開度で音量も変化
    final volume = 0.4 + (throttle / 100.0) * 0.6;
    await _player.setVolume(volume.clamp(0.4, 1.0));
  }

  String _fileForRpm(int rpm) {
    if (rpm < 800) return 'idle.mp3';
    if (rpm < 2500) return 'low.mp3';
    if (rpm < 5000) return 'mid.mp3';
    return 'high.mp3';
  }

  double _rateForRpm(int rpm) {
    // 各音声ファイルの「基準RPM」に対して再生速度を調整
    if (rpm < 800) {
      return (rpm / 700.0).clamp(0.5, 1.2);
    } else if (rpm < 2500) {
      return (rpm / 1600.0).clamp(0.5, 1.5);
    } else if (rpm < 5000) {
      return (rpm / 3500.0).clamp(0.6, 1.5);
    } else {
      return (rpm / 6000.0).clamp(0.7, 1.8);
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
