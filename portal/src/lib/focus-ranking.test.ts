import assert from 'node:assert/strict'
import test from 'node:test'

import {
  maskedEmail,
  parseFocusWindow,
  publicLeaderboardName,
  startOfUTCWeek,
  validateFocusSyncEntries,
} from './focus-ranking.ts'

test('validateFocusSyncEntries accepts versioned bounded daily aggregates without client device identity', () => {
  const entries = validateFocusSyncEntries({
    schema_version: 2,
    entries: [
      {
        date: '2026-05-27',
        focus_seconds: 3600,
        session_count: 2,
      },
    ],
  })

  assert.deepEqual(entries, [
    {
      date: '2026-05-27',
      focus_seconds: 3600,
      session_count: 2,
    },
  ])
})

test('validateFocusSyncEntries rejects old schemas, client device identity, and invalid aggregates', () => {
  assert.throws(() => validateFocusSyncEntries({ entries: [] }))
  assert.throws(() => validateFocusSyncEntries({ schema_version: 1, entries: [] }))
  assert.throws(() => validateFocusSyncEntries({ schema_version: 2, entries: [{ date: '2026-05-27', focus_seconds: 1, session_count: 1, device_id: 'forged' }] }))
  assert.throws(() => validateFocusSyncEntries({ schema_version: 2, entries: [{ date: 'today', focus_seconds: 1, session_count: 1 }] }))
  assert.throws(() => validateFocusSyncEntries({ schema_version: 2, entries: [{ date: '2026-02-30', focus_seconds: 1, session_count: 1 }] }))
  assert.throws(() => validateFocusSyncEntries({ schema_version: 2, entries: [{ date: '2026-05-27', focus_seconds: 90_000, session_count: 1 }] }))
})

test('startOfUTCWeek uses Monday as the weekly leaderboard boundary', () => {
  assert.equal(startOfUTCWeek(new Date('2026-05-27T12:00:00Z')).toISOString(), '2026-05-25T00:00:00.000Z')
  assert.equal(startOfUTCWeek(new Date('2026-05-31T12:00:00Z')).toISOString(), '2026-05-25T00:00:00.000Z')
})

test('leaderboard window defaults to week', () => {
  assert.equal(parseFocusWindow(null), 'week')
  assert.equal(parseFocusWindow('week'), 'week')
  assert.equal(parseFocusWindow('all'), 'all')
})

test('public leaderboard name prefers display name and masks email fallback', () => {
  assert.equal(publicLeaderboardName({ displayName: 'Ada', email: 'ada@example.com' }), 'Ada')
  assert.equal(publicLeaderboardName({ displayName: null, email: 'alex@example.com' }), 'al***@example.com')
  assert.equal(maskedEmail(null), 'Notch user')
})
