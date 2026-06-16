import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

void main() {
  gen('assets/correct.wav', 880.0, 8000, 4.0);
  gen('assets/wrong.wav', 220.0, 12000, 2.5, amp: 0.6);
  print('done');
}

void gen(String path, double freq, int samples, double decay, {double amp = 1.0}) {
  final bytes = BytesBuilder();
  for (int i = 0; i < samples; i++) {
    double t = i / 8000.0;
    double envelope = max(0, 1.0 - t * decay);
    double val = sin(2 * pi * freq * t) * envelope * amp;
    int sample = (val * 8000).round().clamp(-32768, 32767);
    bytes.add([sample & 0xFF, (sample >> 8) & 0xFF]);
  }
  final data = bytes.toBytes();
  final out = BytesBuilder();
  final dataSize = data.length;
  out.add('RIFF'.codeUnits);
  out.add(Uint8List(4)..buffer.asByteData().setInt32(0, 36 + dataSize, Endian.little));
  out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits);
  out.add(Uint8List(4)..buffer.asByteData().setInt32(0, 16, Endian.little));
  out.add(Uint8List(2)..buffer.asByteData().setInt16(0, 1, Endian.little));
  out.add(Uint8List(2)..buffer.asByteData().setInt16(0, 1, Endian.little));
  out.add(Uint8List(4)..buffer.asByteData().setInt32(0, 8000, Endian.little));
  out.add(Uint8List(4)..buffer.asByteData().setInt32(0, 16000, Endian.little));
  out.add(Uint8List(2)..buffer.asByteData().setInt16(0, 2, Endian.little));
  out.add(Uint8List(2)..buffer.asByteData().setInt16(0, 16, Endian.little));
  out.add('data'.codeUnits);
  out.add(Uint8List(4)..buffer.asByteData().setInt32(0, dataSize, Endian.little));
  out.add(data);
  File(path).writeAsBytesSync(out.toBytes());
}
