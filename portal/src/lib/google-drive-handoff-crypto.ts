import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const HANDOFF_VALUE_VERSION = 'v1';
const IV_BYTES = 12;

function encryptionKey(): Buffer {
  const rawKey = process.env.GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY?.trim() || '';
  const key = Buffer.from(rawKey, 'base64');
  if (key.length !== 32) {
    throw new Error('GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY must be a base64-encoded 32-byte key.');
  }
  return key;
}

export function encryptGoogleDriveHandoffValue(value: string): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return [
    HANDOFF_VALUE_VERSION,
    iv.toString('base64url'),
    authTag.toString('base64url'),
    ciphertext.toString('base64url'),
  ].join('.');
}

export function decryptGoogleDriveHandoffValue(value: string): string {
  const [version, encodedIV, encodedTag, encodedCiphertext] = value.split('.');
  if (version !== HANDOFF_VALUE_VERSION || !encodedIV || !encodedTag || !encodedCiphertext) {
    throw new Error('Invalid Google Drive handoff payload.');
  }

  const decipher = createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(encodedIV, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(encodedTag, 'base64url'));
  const cleartext = Buffer.concat([
    decipher.update(Buffer.from(encodedCiphertext, 'base64url')),
    decipher.final(),
  ]);
  return cleartext.toString('utf8');
}
