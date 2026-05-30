import assert from 'node:assert/strict'
import test from 'node:test'
import { signJWT, verifyJWT } from './token-service.ts'

test('JWT Service can sign and verify a token successfully', () => {
  const payload = {
    userId: 'user_123',
    email: 'test@example.com',
    name: 'Test User',
    displayName: 'Tester',
    avatarUrl: 'https://example.com/avatar.png',
    isPro: true,
    isAdmin: false,
    leaderboardOptIn: true,
    userCreatedAt: '2026-05-30T12:00:00Z',
    sessionId: 'session_abc',
    deviceId: 'device_mac',
  }

  // Sign a token valid for 10 seconds
  const token = signJWT(payload, 10000)
  assert.ok(token)
  assert.equal(token.split('.').length, 3)

  // Verify the token
  const decoded = verifyJWT(token)
  assert.ok(decoded)
  assert.equal(decoded.userId, payload.userId)
  assert.equal(decoded.email, payload.email)
  assert.equal(decoded.name, payload.name)
  assert.equal(decoded.isPro, payload.isPro)
  assert.equal(decoded.isAdmin, payload.isAdmin)
  assert.equal(decoded.sessionId, payload.sessionId)
  assert.equal(decoded.deviceId, payload.deviceId)
})

test('JWT Service rejects forged or modified signatures', () => {
  const payload = {
    userId: 'user_123',
    email: 'test@example.com',
    name: 'Test User',
    displayName: 'Tester',
    avatarUrl: null,
    isPro: false,
    isAdmin: false,
    leaderboardOptIn: false,
    userCreatedAt: '2026-05-30T12:00:00Z',
    sessionId: 'session_abc',
    deviceId: null,
  }

  const token = signJWT(payload, 10000)
  const parts = token.split('.')
  
  // Modify payload (middle part) to try to set isPro to true
  const decodedPayload = Buffer.from(parts[1], 'base64url').toString('utf8')
  const tamperedPayloadObj = JSON.parse(decodedPayload)
  tamperedPayloadObj.isPro = true
  
  const tamperedPart = Buffer.from(JSON.stringify(tamperedPayloadObj)).toString('base64url')
  const tamperedToken = `${parts[0]}.${tamperedPart}.${parts[2]}`

  // Decryption should fail due to signature mismatch
  const result = verifyJWT(tamperedToken)
  assert.equal(result, null)
})

test('JWT Service rejects expired tokens', async () => {
  const payload = {
    userId: 'user_expired',
    email: 'expired@example.com',
    name: 'Expired',
    displayName: null,
    avatarUrl: null,
    isPro: false,
    isAdmin: false,
    leaderboardOptIn: false,
    userCreatedAt: '2026-05-30T12:00:00Z',
    sessionId: 'session_expired',
    deviceId: null,
  }

  // Sign a token with a lifespan of negative 1 second (already expired)
  const token = signJWT(payload, -1000)
  assert.ok(token)

  // Verification should return null
  const decoded = verifyJWT(token)
  assert.equal(decoded, null)
})
