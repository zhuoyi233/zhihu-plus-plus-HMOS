import { utf8Encode } from './Utf8';

const HEX = '0123456789abcdef';
const SHIFTS: Array<number> = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

function createConstants(): Array<number> {
  const constants: Array<number> = [];
  for (let index = 0; index < 64; index += 1) {
    constants.push(Math.floor(Math.abs(Math.sin(index + 1)) * 4294967296) | 0);
  }
  return constants;
}

const CONSTANTS = createConstants();

function rotateLeft(value: number, distance: number): number {
  return (value << distance) | (value >>> (32 - distance));
}

function add32(left: number, right: number): number {
  return (left + right) | 0;
}

function addFour32(first: number, second: number, third: number, fourth: number): number {
  return (first + second + third + fourth) | 0;
}

function appendLittleEndianHex(output: Array<string>, value: number): void {
  for (let index = 0; index < 4; index += 1) {
    const byte = (value >>> (8 * index)) & 0xff;
    output.push(HEX.charAt(byte >>> 4));
    output.push(HEX.charAt(byte & 0x0f));
  }
}

export function md5Hex(input: string): string {
  const message = utf8Encode(input);
  const bitLength = message.length * 8;
  const paddedLength = (Math.floor((message.length + 8) / 64) + 1) * 64;
  const padded: Array<number> = new Array<number>(paddedLength);
  for (let index = 0; index < paddedLength; index += 1) {
    padded[index] = 0;
  }
  for (let index = 0; index < message.length; index += 1) {
    padded[index] = message[index];
  }
  padded[message.length] = 0x80;
  for (let index = 0; index < 8; index += 1) {
    padded[paddedLength - 8 + index] = Math.floor(bitLength / Math.pow(2, 8 * index)) & 0xff;
  }

  let a0 = 0x67452301;
  let b0 = 0xefcdab89 | 0;
  let c0 = 0x98badcfe | 0;
  let d0 = 0x10325476;
  const words: Array<number> = new Array<number>(16);

  for (let chunkOffset = 0; chunkOffset < padded.length; chunkOffset += 64) {
    for (let index = 0; index < 16; index += 1) {
      const offset = chunkOffset + index * 4;
      words[index] = padded[offset] |
        (padded[offset + 1] << 8) |
        (padded[offset + 2] << 16) |
        (padded[offset + 3] << 24);
    }

    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;
    for (let index = 0; index < 64; index += 1) {
      let f: number;
      let wordIndex: number;
      if (index <= 15) {
        f = (b & c) | (~b & d);
        wordIndex = index;
      } else if (index <= 31) {
        f = (d & b) | (~d & c);
        wordIndex = (5 * index + 1) % 16;
      } else if (index <= 47) {
        f = b ^ c ^ d;
        wordIndex = (3 * index + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        wordIndex = (7 * index) % 16;
      }

      const nextD = c;
      c = b;
      const mixed = addFour32(a, f, CONSTANTS[index], words[wordIndex]);
      b = add32(b, rotateLeft(mixed, SHIFTS[index]));
      a = d;
      d = nextD;
    }

    a0 = add32(a0, a);
    b0 = add32(b0, b);
    c0 = add32(c0, c);
    d0 = add32(d0, d);
  }

  const output: Array<string> = [];
  appendLittleEndianHex(output, a0);
  appendLittleEndianHex(output, b0);
  appendLittleEndianHex(output, c0);
  appendLittleEndianHex(output, d0);
  return output.join('');
}
