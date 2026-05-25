import assert from 'node:assert/strict'
import test from 'node:test'
import { GoogleGenAI } from '@google/genai'

import { buildGeminiLiveConnectConfig } from './gemini-live-token-policy.ts'

test('managed tokens leave session resumption handle unlocked', () => {
  const { liveConfig } = buildGeminiLiveConnectConfig(
    { response_modalities: ['AUDIO'] },
    'gemini-3.1-flash-live-preview',
  )

  assert.equal(Object.prototype.hasOwnProperty.call(liveConfig, 'sessionResumption'), false)
})

test('SDK token constraints do not generate a session resumption field mask', async () => {
  const { liveConfig } = buildGeminiLiveConnectConfig(
    { response_modalities: ['AUDIO'] },
    'gemini-3.1-flash-live-preview',
  )
  let submittedBody = ''
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (_input, init) => {
    submittedBody = typeof init?.body === 'string' ? init.body : ''
    return new Response(JSON.stringify({ name: 'auth_tokens/test' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }

  try {
    const client = new GoogleGenAI({ apiKey: 'test-api-key' })
    await client.authTokens.create({
      config: {
        uses: 1,
        lockAdditionalFields: [],
        liveConnectConstraints: {
          model: 'gemini-3.1-flash-live-preview',
          config: liveConfig,
        },
        httpOptions: { apiVersion: 'v1alpha' },
      },
    })
  } finally {
    globalThis.fetch = originalFetch
  }

  assert.notEqual(submittedBody, '')
  assert.doesNotMatch(submittedBody, /sessionResumption/)
})

test('Gemini 3.1 embeds thinkingLevel and ignores legacy budget', () => {
  const { liveConfig, hasThinkingLevel, hasThinkingBudget } = buildGeminiLiveConnectConfig(
    { thinking_level: 'high', thinking_budget: 8192 },
    'gemini-3.1-flash-live-preview',
  )

  assert.deepEqual(liveConfig.thinkingConfig, { thinkingLevel: 'HIGH' })
  assert.equal(hasThinkingLevel, true)
  assert.equal(hasThinkingBudget, false)
})

test('Gemini 3.1 upgrades legacy client budgets to thinkingLevel', () => {
  const { liveConfig } = buildGeminiLiveConnectConfig(
    { thinking_budget: 2048 },
    'gemini-3.1-flash-live-preview',
  )

  assert.deepEqual(liveConfig.thinkingConfig, { thinkingLevel: 'MEDIUM' })
})

test('Gemini 2.5 embeds a zero thinking budget for Off', () => {
  const { liveConfig, hasThinkingLevel, hasThinkingBudget } = buildGeminiLiveConnectConfig(
    { thinking_level: 'minimal', thinking_budget: 0 },
    'gemini-2.5-flash-native-audio-preview-12-2025',
  )

  assert.deepEqual(liveConfig.thinkingConfig, { thinkingBudget: 0 })
  assert.equal(hasThinkingLevel, false)
  assert.equal(hasThinkingBudget, true)
})
