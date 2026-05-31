import { describe, test } from 'node:test'
import assert from 'node:assert'

const NEXT_URL = 'http://localhost:3000'
const GO_URL = 'http://localhost:8080'

describe('Auth API Parity Tests', () => {
  // Test 1: Unauthenticated me
  test('GET /api/auth/me unauthenticated parity', async () => {
    const nextResp = await fetch(`${NEXT_URL}/api/auth/me`)
    const goResp = await fetch(`${GO_URL}/api/auth/me`)

    assert.strictEqual(goResp.status, nextResp.status, 'Status codes should match (401)')
    assert.strictEqual(goResp.status, 401)

    const nextJson = await nextResp.json()
    const goJson = await goResp.json()

    assert.strictEqual(goJson.detail, nextJson.detail, 'Detail error messages should match')
    assert.strictEqual(goJson.detail, 'Invalid or expired session token.')
  })

  // Test 2: Unauthenticated sessions
  test('GET /api/auth/sessions unauthenticated parity', async () => {
    const nextResp = await fetch(`${NEXT_URL}/api/auth/sessions`)
    const goResp = await fetch(`${GO_URL}/api/auth/sessions`)

    assert.strictEqual(goResp.status, nextResp.status, 'Status codes should match (401)')
    assert.strictEqual(goResp.status, 401)

    const nextJson = await nextResp.json()
    const goJson = await goResp.json()

    assert.strictEqual(goJson.detail, nextJson.detail, 'Detail error messages should match')
  })

  // Test 3: Login validation failure (empty payload)
  test('POST /api/auth/login empty body parity', async () => {
    const nextResp = await fetch(`${NEXT_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    })
    const goResp = await fetch(`${GO_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    })

    assert.strictEqual(goResp.status, nextResp.status, 'Status codes should match (400)')
    assert.strictEqual(goResp.status, 400)

    const nextJson = await nextResp.json()
    const goJson = await goResp.json()

    // Both should report empty email/password
    assert.strictEqual(goJson.error, nextJson.error)
    assert.strictEqual(goJson.error, 'Vui lòng nhập email và mật khẩu')
  })

  // Test 4: Login validation failure (invalid email)
  test('POST /api/auth/login invalid email parity', async () => {
    const nextResp = await fetch(`${NEXT_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'invalid-email', password: 'password123' }),
    })
    const goResp = await fetch(`${GO_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'invalid-email', password: 'password123' }),
    })

    assert.strictEqual(goResp.status, nextResp.status, 'Status codes should match (400)')
    assert.strictEqual(goResp.status, 400)

    const nextJson = await nextResp.json()
    const goJson = await goResp.json()

    assert.strictEqual(goJson.error, nextJson.error)
    assert.strictEqual(goJson.error, 'Email không hợp lệ')
  })

  // Test 5: Login non-existent user
  test('POST /api/auth/login non-existent user parity', async () => {
    const nextResp = await fetch(`${NEXT_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'nonexistentuser@example.com', password: 'wrongpassword' }),
    })
    const goResp = await fetch(`${GO_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'nonexistentuser@example.com', password: 'wrongpassword' }),
    })

    assert.strictEqual(goResp.status, nextResp.status, 'Status codes should match (401)')
    assert.strictEqual(goResp.status, 401)

    const nextJson = await nextResp.json()
    const goJson = await goResp.json()

    assert.strictEqual(goJson.error, nextJson.error)
    assert.strictEqual(goJson.error, 'Email hoặc mật khẩu không chính xác')
  })
})
