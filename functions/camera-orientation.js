export function cameraOrientation(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return 1;
  let cursor = 2;
  for (let segment = 0; segment < 65536 && cursor + 4 <= bytes.length; segment++) {
    if (bytes[cursor++] !== 0xff) return 1;
    while (bytes[cursor] === 0xff) cursor++;
    const marker = bytes[cursor++];
    if (marker === 0xda || marker === 0xd9) return 1;
    if (marker === 0x01 || marker >= 0xd0 && marker <= 0xd8) continue;
    if (cursor + 2 > bytes.length) return 1;
    const length = bytes.readUInt16BE(cursor);
    const end = cursor + length;
    if (length < 2 || end > bytes.length) return 1;
    if (marker === 0xe1 && length >= 16 && bytes.subarray(cursor + 2, cursor + 8).equals(Buffer.from('Exif\0\0'))) {
      const tiff = bytes.subarray(cursor + 8, end);
      const order = tiff.subarray(0, 2).toString('ascii');
      if (!['II', 'MM'].includes(order)) return 1;
      const short = offset => order === 'II' ? tiff.readUInt16LE(offset) : tiff.readUInt16BE(offset);
      const long = offset => order === 'II' ? tiff.readUInt32LE(offset) : tiff.readUInt32BE(offset);
      if (short(2) !== 42) return 1;
      const directory = long(4);
      if (directory < 8 || directory + 2 > tiff.length) return 1;
      const count = short(directory);
      if (directory + 2 + count * 12 > tiff.length) return 1;
      for (let entry = 0; entry < count; entry++) {
        const offset = directory + 2 + entry * 12;
        if (short(offset) === 0x0112 && short(offset + 2) === 3 && long(offset + 4) === 1) {
          const value = short(offset + 8);
          return value >= 1 && value <= 8 ? value : 1;
        }
      }
    }
    cursor = end;
  }
  return 1;
}

export function cameraPageLayout(orientation, width, height) {
  const matrices = {
    1: [1, 0, 0, 1, 0, 0], 2: [-1, 0, 0, 1, width, 0],
    3: [-1, 0, 0, -1, width, height], 4: [1, 0, 0, -1, 0, height],
    5: [0, -1, -1, 0, height, width], 6: [0, -1, 1, 0, 0, width],
    7: [0, 1, 1, 0, 0, 0], 8: [0, 1, -1, 0, height, 0],
  };
  const swapped = orientation >= 5 && orientation <= 8;
  return { width: swapped ? height : width, height: swapped ? width : height,
    matrix: matrices[orientation] ?? matrices[1] };
}
