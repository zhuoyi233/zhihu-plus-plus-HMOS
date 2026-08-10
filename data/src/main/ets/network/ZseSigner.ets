import { utf8Encode } from './Utf8';

const ZK: Array<number> = [
  1170614578, 1024848638, 1413669199, 3951632832, 3528873006, 2921909214, 4151847688, 3997739139,
  1933479194, 3323781115, 3888513386, 460404854, 3747539722, 2403641034, 2615871395, 2119585428,
  2265697227, 2035090028, 2773447226, 4289380121, 4217216195, 2200601443, 3051914490, 1579901135,
  1321810770, 456816404, 2903323407, 4065664991, 330002838, 3506006750, 363569021, 2347096187
];

const ZB: Array<number> = [
  20, 223, 245, 7, 248, 2, 194, 209, 87, 6, 227, 253, 240, 128, 222, 91, 237, 9, 125, 157, 230,
  93, 252, 205, 90, 79, 144, 199, 159, 197, 186, 167, 39, 37, 156, 198, 38, 42, 43, 168, 217,
  153, 15, 103, 80, 189, 71, 191, 97, 84, 247, 95, 36, 69, 14, 35, 12, 171, 28, 114, 178, 148,
  86, 182, 32, 83, 158, 109, 22, 255, 94, 238, 151, 85, 77, 124, 254, 18, 4, 26, 123, 176, 232,
  193, 131, 172, 143, 142, 150, 30, 10, 146, 162, 62, 224, 218, 196, 229, 1, 192, 213, 27, 110,
  56, 231, 180, 138, 107, 242, 187, 54, 120, 19, 44, 117, 228, 215, 203, 53, 239, 251, 127, 81,
  11, 133, 96, 204, 132, 41, 115, 73, 55, 249, 147, 102, 48, 122, 145, 106, 118, 74, 190, 29, 16,
  174, 5, 177, 129, 63, 113, 99, 31, 161, 76, 246, 34, 211, 13, 60, 68, 207, 160, 65, 111, 82,
  165, 67, 169, 225, 57, 112, 244, 155, 51, 236, 200, 233, 58, 61, 47, 100, 137, 185, 64, 17, 70,
  234, 163, 219, 108, 170, 166, 59, 149, 52, 105, 24, 212, 78, 173, 45, 0, 116, 226, 119, 136,
  206, 135, 175, 195, 25, 92, 121, 208, 126, 139, 3, 75, 141, 21, 130, 98, 241, 40, 154, 66, 184,
  49, 181, 46, 243, 88, 101, 183, 8, 23, 72, 188, 104, 179, 210, 134, 250, 201, 164, 89, 216,
  202, 220, 50, 221, 152, 140, 33, 235, 214
];

const ALPHABET = '6fpLRqJO8M/c3jnYxFkUVC4ZIG12SiH=5v0mXDazWBTsuw7QetbKdoPyAl+hN9rgE';
const KEY16: Array<number> = [48, 53, 57, 48, 53, 51, 102, 55, 100, 49, 53, 101, 48, 49, 100, 55];

function rotateLeft(value: number, distance: number): number {
  return (value << distance) | (value >>> (32 - distance));
}

function readU32Be(bytes: Array<number>, offset: number): number {
  return ((bytes[offset] & 0xff) << 24) |
    ((bytes[offset + 1] & 0xff) << 16) |
    ((bytes[offset + 2] & 0xff) << 8) |
    (bytes[offset + 3] & 0xff);
}

function writeU32Be(value: number, output: Array<number>, offset: number): void {
  output[offset] = (value >>> 24) & 0xff;
  output[offset + 1] = (value >>> 16) & 0xff;
  output[offset + 2] = (value >>> 8) & 0xff;
  output[offset + 3] = value & 0xff;
}

function gTransform(value: number): number {
  const b0 = ZB[(value >>> 24) & 0xff] & 0xff;
  const b1 = ZB[(value >>> 16) & 0xff] & 0xff;
  const b2 = ZB[(value >>> 8) & 0xff] & 0xff;
  const b3 = ZB[value & 0xff] & 0xff;
  const substituted = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  return substituted ^ rotateLeft(substituted, 2) ^ rotateLeft(substituted, 10) ^
    rotateLeft(substituted, 18) ^ rotateLeft(substituted, 24);
}

function transformBlock(input: Array<number>): Array<number> {
  const state: Array<number> = new Array<number>(36);
  state[0] = readU32Be(input, 0);
  state[1] = readU32Be(input, 4);
  state[2] = readU32Be(input, 8);
  state[3] = readU32Be(input, 12);

  for (let index = 0; index < 32; index += 1) {
    const mixed = state[index + 1] ^ state[index + 2] ^ state[index + 3] ^ ZK[index];
    state[index + 4] = state[index] ^ gTransform(mixed);
  }

  const output: Array<number> = new Array<number>(16);
  writeU32Be(state[35], output, 0);
  writeU32Be(state[34], output, 4);
  writeU32Be(state[33], output, 8);
  writeU32Be(state[32], output, 12);
  return output;
}

function encryptBlocks(data: Array<number>, initialVector: Array<number>): Array<number> {
  let vector = initialVector;
  const output: Array<number> = new Array<number>(data.length);
  for (let offset = 0; offset < data.length; offset += 16) {
    const mixed: Array<number> = new Array<number>(16);
    for (let index = 0; index < 16; index += 1) {
      mixed[index] = (data[offset + index] ^ vector[index]) & 0xff;
    }
    vector = transformBlock(mixed);
    for (let index = 0; index < 16; index += 1) {
      output[offset + index] = vector[index];
    }
  }
  return output;
}

function customEncode(input: Array<number>): string {
  const bytes = input.slice();
  const remainder = bytes.length % 3;
  if (remainder !== 0) {
    for (let count = remainder; count < 3; count += 1) {
      bytes.push(0);
    }
  }

  let output = '';
  let maskIndex = 0;
  for (let position = bytes.length - 1; position >= 0; position -= 3) {
    let value = 0;
    for (let byteIndex = 0; byteIndex < 3; byteIndex += 1) {
      const mask = (58 >>> (8 * (maskIndex % 4))) & 0xff;
      value |= ((bytes[position - byteIndex] ^ mask) & 0xff) << (8 * byteIndex);
      maskIndex += 1;
    }
    output += ALPHABET.charAt(value & 63);
    output += ALPHABET.charAt((value >>> 6) & 63);
    output += ALPHABET.charAt((value >>> 12) & 63);
    output += ALPHABET.charAt((value >>> 18) & 63);
  }
  return output;
}

export function encryptZseV4(input: string): string {
  const plain: Array<number> = [210, 0];
  const encoded = utf8Encode(input);
  for (let index = 0; index < encoded.length; index += 1) {
    plain.push(encoded[index]);
  }

  const padding = 16 - (plain.length % 16);
  for (let index = 0; index < padding; index += 1) {
    plain.push(padding);
  }

  const first: Array<number> = new Array<number>(16);
  for (let index = 0; index < 16; index += 1) {
    first[index] = (plain[index] ^ KEY16[index] ^ 42) & 0xff;
  }

  const firstCipher = transformBlock(first);
  const cipher = firstCipher.slice();
  if (plain.length > 16) {
    const rest = encryptBlocks(plain.slice(16), firstCipher);
    for (let index = 0; index < rest.length; index += 1) {
      cipher.push(rest[index]);
    }
  }
  return customEncode(cipher);
}
