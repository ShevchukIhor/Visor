import 'dart:typed_data';

/// Base58 encoder (Bitcoin/Solana alphabet).
String base58Encode(Uint8List bytes) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var n = BigInt.from(0);
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  if (n == BigInt.zero) {
    return '1' * bytes.length;
  }
  final buf = StringBuffer();
  final base = BigInt.from(58);
  while (n > BigInt.zero) {
    final r = (n % base).toInt();
    buf.write(alphabet[r]);
    n = n ~/ base;
  }
  for (final b in bytes) {
    if (b == 0) {
      buf.write('1');
    } else {
      break;
    }
  }
  return buf.toString().split('').reversed.join();
}