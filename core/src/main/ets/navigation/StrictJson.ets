export class JsonNullValue {
}

export class JsonStringValue {
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }
}

export class JsonNumberValue {
  readonly value: number;

  constructor(value: number) {
    this.value = value;
  }
}

export class JsonBooleanValue {
  readonly value: boolean;

  constructor(value: boolean) {
    this.value = value;
  }
}

export class JsonArrayValue {
  readonly items: Array<JsonValue>;

  constructor(items: Array<JsonValue>) {
    this.items = items;
  }
}

export class JsonObjectEntry {
  readonly name: string;
  readonly value: JsonValue;

  constructor(name: string, value: JsonValue) {
    this.name = name;
    this.value = value;
  }
}

export class JsonObjectValue {
  readonly entries: Array<JsonObjectEntry>;

  constructor(entries: Array<JsonObjectEntry>) {
    this.entries = entries;
  }

  get(name: string): JsonValue | undefined {
    const entry = this.entries.find((candidate: JsonObjectEntry): boolean => candidate.name === name);
    return entry?.value;
  }
}

export type JsonValue = JsonNullValue | JsonStringValue | JsonNumberValue | JsonBooleanValue |
  JsonArrayValue | JsonObjectValue;

export class StrictJsonError extends Error {
  constructor() {
    super('Invalid JSON');
    this.name = 'StrictJsonError';
  }
}

export function parseStrictJson(source: string): JsonValue {
  const parser = new StrictJsonParser(source);
  return parser.parse();
}

export function jsonObject(value: JsonValue | undefined): JsonObjectValue | undefined {
  return value instanceof JsonObjectValue ? value : undefined;
}

export function jsonArray(value: JsonValue | undefined): JsonArrayValue | undefined {
  return value instanceof JsonArrayValue ? value : undefined;
}

export function jsonString(value: JsonValue | undefined): string | undefined {
  return value instanceof JsonStringValue ? value.value : undefined;
}

export function jsonNumber(value: JsonValue | undefined): number | undefined {
  return value instanceof JsonNumberValue ? value.value : undefined;
}

export function jsonBoolean(value: JsonValue | undefined): boolean | undefined {
  return value instanceof JsonBooleanValue ? value.value : undefined;
}

class StrictJsonParser {
  private readonly source: string;
  private offset: number = 0;
  private nodes: number = 0;

  constructor(source: string) {
    this.source = source;
  }

  parse(): JsonValue {
    this.skipWhitespace();
    const value = this.readValue(0);
    this.skipWhitespace();
    if (this.offset !== this.source.length) {
      throw new StrictJsonError();
    }
    return value;
  }

  private readValue(depth: number): JsonValue {
    this.nodes += 1;
    if (depth > 64 || this.nodes > 200000) {
      throw new StrictJsonError();
    }
    const character = this.source.charAt(this.offset);
    if (character === '{') {
      return this.readObject(depth + 1);
    }
    if (character === '[') {
      return this.readArray(depth + 1);
    }
    if (character === '"') {
      return new JsonStringValue(this.readString());
    }
    if (character === 't') {
      this.readLiteral('true');
      return new JsonBooleanValue(true);
    }
    if (character === 'f') {
      this.readLiteral('false');
      return new JsonBooleanValue(false);
    }
    if (character === 'n') {
      this.readLiteral('null');
      return new JsonNullValue();
    }
    return new JsonNumberValue(this.readNumber());
  }

  private readObject(depth: number): JsonObjectValue {
    this.offset += 1;
    this.skipWhitespace();
    const entries: Array<JsonObjectEntry> = [];
    if (this.source.charAt(this.offset) === '}') {
      this.offset += 1;
      return new JsonObjectValue(entries);
    }
    while (this.offset < this.source.length) {
      if (this.source.charAt(this.offset) !== '"') {
        throw new StrictJsonError();
      }
      const name = this.readString();
      if (entries.some((entry: JsonObjectEntry): boolean => entry.name === name)) {
        throw new StrictJsonError();
      }
      this.skipWhitespace();
      if (this.source.charAt(this.offset) !== ':') {
        throw new StrictJsonError();
      }
      this.offset += 1;
      this.skipWhitespace();
      entries.push(new JsonObjectEntry(name, this.readValue(depth)));
      this.skipWhitespace();
      const delimiter = this.source.charAt(this.offset);
      if (delimiter === '}') {
        this.offset += 1;
        return new JsonObjectValue(entries);
      }
      if (delimiter !== ',') {
        throw new StrictJsonError();
      }
      this.offset += 1;
      this.skipWhitespace();
    }
    throw new StrictJsonError();
  }

  private readArray(depth: number): JsonArrayValue {
    this.offset += 1;
    this.skipWhitespace();
    const items: Array<JsonValue> = [];
    if (this.source.charAt(this.offset) === ']') {
      this.offset += 1;
      return new JsonArrayValue(items);
    }
    while (this.offset < this.source.length) {
      items.push(this.readValue(depth));
      this.skipWhitespace();
      const delimiter = this.source.charAt(this.offset);
      if (delimiter === ']') {
        this.offset += 1;
        return new JsonArrayValue(items);
      }
      if (delimiter !== ',') {
        throw new StrictJsonError();
      }
      this.offset += 1;
      this.skipWhitespace();
    }
    throw new StrictJsonError();
  }

  private readString(): string {
    this.offset += 1;
    let result = '';
    while (this.offset < this.source.length) {
      const character = this.source.charAt(this.offset);
      this.offset += 1;
      if (character === '"') {
        return result;
      }
      if (character === '\\') {
        result += this.readEscape();
      } else {
        if (character.charCodeAt(0) < 0x20) {
          throw new StrictJsonError();
        }
        result += character;
      }
    }
    throw new StrictJsonError();
  }

  private readEscape(): string {
    const escaped = this.source.charAt(this.offset);
    this.offset += 1;
    if (escaped === '"' || escaped === '\\' || escaped === '/') {
      return escaped;
    }
    if (escaped === 'b') {
      return '\b';
    }
    if (escaped === 'f') {
      return '\f';
    }
    if (escaped === 'n') {
      return '\n';
    }
    if (escaped === 'r') {
      return '\r';
    }
    if (escaped === 't') {
      return '\t';
    }
    if (escaped !== 'u') {
      throw new StrictJsonError();
    }
    return String.fromCharCode(this.readHexCodeUnit());
  }

  private readHexCodeUnit(): number {
    const text = this.source.substring(this.offset, this.offset + 4);
    if (!/^[0-9A-Fa-f]{4}$/.test(text)) {
      throw new StrictJsonError();
    }
    this.offset += 4;
    return Number.parseInt(text, 16);
  }

  private readNumber(): number {
    const remaining = this.source.substring(this.offset);
    const match = remaining.match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/);
    let matchedText: string | undefined;
    if (match !== null) {
      match.forEach((candidate: string): void => {
        if (matchedText === undefined) {
          matchedText = candidate;
        }
      });
    }
    if (matchedText === undefined || matchedText.length === 0) {
      throw new StrictJsonError();
    }
    this.offset += matchedText.length;
    const value = Number(matchedText);
    if (!Number.isFinite(value)) {
      throw new StrictJsonError();
    }
    return value;
  }

  private readLiteral(expected: string): void {
    if (this.source.substring(this.offset, this.offset + expected.length) !== expected) {
      throw new StrictJsonError();
    }
    this.offset += expected.length;
  }

  private skipWhitespace(): void {
    while (this.offset < this.source.length) {
      const character = this.source.charAt(this.offset);
      if (character !== ' ' && character !== '\n' && character !== '\r' && character !== '\t') {
        return;
      }
      this.offset += 1;
    }
  }
}
