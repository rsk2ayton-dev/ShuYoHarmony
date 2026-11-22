import { util } from '@kit.ArkTS';

/**
 * Ports AcademicPasswordEncryptor from ShuYo (1024-bit RSA PKCS#1 v1.5).
 */
export class RsaEncryptor {
  private static readonly rsaModulusHex: string =
    'e5fda0a0465f5fff838df4c7b0a159d5e7c38b394d802c18b614a739c88b1f4a' +
    '98af2b17bb03a162b498c7bdadd6a4cee0bd53a29cc7a1a7a89fd9434891b68d' +
    'fa99567f9230a84571b0d6697a2c5ce06b1b63d757124dd6b518f0192c832f24' +
    'b3104487fe4a49568c4eee28d162a53eda8491c1304d78f3a4d47f8b450a2481';

  private static readonly rsaExponent: bigint = BigInt(65537);

  static encryptPassword(password: string): string {
    const encoder = new util.TextEncoder();
    const messageBytes = encoder.encodeInto(password);
    const keyLen = 128; // 1024 bits = 128 bytes
    if (messageBytes.length > keyLen - 11) {
      throw new Error('密码过长，无法加密');
    }

    // PKCS#1 v1.5 block: 0x00 || 0x02 || PS (>=8 non-zero bytes) || 0x00 || M
    const padded = new Uint8Array(keyLen);
    padded[0] = 0x00;
    padded[1] = 0x02;
    const psLen = keyLen - messageBytes.length - 3;
    for (let i = 0; i < psLen; i++) {
      let randByte = Math.floor(Math.random() * 255) + 1;
      if (randByte <= 0) {
        randByte = 0x5a;
      }
      padded[2 + i] = randByte;
    }
    padded[2 + psLen] = 0x00;
    for (let i = 0; i < messageBytes.length; i++) {
      padded[3 + psLen + i] = messageBytes[i];
    }

    const m = RsaEncryptor.bytesToBigInt(padded);
    const n = BigInt('0x' + RsaEncryptor.rsaModulusHex);
    const c = RsaEncryptor.modPow(m, RsaEncryptor.rsaExponent, n);
    const encryptedBytes = RsaEncryptor.bigIntToBytes(c, keyLen);

    const base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(encryptedBytes);
  }

  private static bytesToBigInt(bytes: Uint8Array): bigint {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      const h = bytes[i].toString(16);
      hex += h.length === 1 ? '0' + h : h;
    }
    return BigInt('0x' + hex);
  }

  private static bigIntToBytes(val: bigint, targetLen: number): Uint8Array {
    let hex = val.toString(16);
    if (hex.length % 2 !== 0) {
      hex = '0' + hex;
    }
    while (hex.length < targetLen * 2) {
      hex = '00' + hex;
    }
    const out = new Uint8Array(targetLen);
    const offset = hex.length / 2 - targetLen;
    for (let i = 0; i < targetLen; i++) {
      const pos = (i + offset) * 2;
      out[i] = parseInt(hex.substring(pos, pos + 2), 16);
    }
    return out;
  }

  private static modPow(baseVal: bigint, expVal: bigint, modVal: bigint): bigint {
    let result = BigInt(1);
    let b = baseVal % modVal;
    let e = expVal;
    const zero = BigInt(0);
    const one = BigInt(1);
    const two = BigInt(2);
    while (e > zero) {
      if ((e % two) === one) {
        result = (result * b) % modVal;
      }
      e = e / two;
      b = (b * b) % modVal;
    }
    return result;
  }
}
