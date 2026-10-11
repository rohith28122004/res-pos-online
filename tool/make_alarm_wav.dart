// Generates assets/sounds/new_ticket.wav: three short rising beeps (mono,
// 16-bit, 22.05 kHz). Run once: dart run tool/make_alarm_wav.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  const rate = 22050;
  final samples = <int>[];
  void tone(double hz, double seconds, {double volume = 0.6}) {
    final n = (rate * seconds).round();
    for (var i = 0; i < n; i++) {
      // Short fade in/out avoids clicks.
      final edge = min(1.0, min(i, n - i) / (rate * 0.01));
      samples.add((sin(2 * pi * hz * i / rate) * volume * edge * 32767).round());
    }
  }

  void silence(double seconds) => samples.addAll(List.filled((rate * seconds).round(), 0));

  tone(880, 0.15);
  silence(0.06);
  tone(1175, 0.15);
  silence(0.06);
  tone(1568, 0.25);

  final data = ByteData(44 + samples.length * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  final out = File('assets/sounds/new_ticket.wav')..createSync(recursive: true);
  out.writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('Wrote ${out.path} (${data.lengthInBytes} bytes)');
}
