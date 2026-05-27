import assert from 'node:assert/strict'
import test from 'node:test'

import {
  focusEventTypes,
  focusRejectedMetadata,
  focusSyncFailedMetadata,
  focusSyncSucceededMetadata,
  leaderboardProfileFailedMetadata,
  leaderboardProfileUpdatedMetadata,
} from './focus-event-policy.ts'

test('focus event names define the admin audit surface', () => {
  assert.deepEqual(focusEventTypes, {
    syncSucceeded: 'focus.sync_succeeded',
    syncRejected: 'focus.sync_rejected',
    syncFailed: 'focus.sync_failed',
    leaderboardProfileUpdated: 'focus.leaderboard_profile_updated',
    leaderboardProfileRejected: 'focus.leaderboard_profile_rejected',
    leaderboardProfileFailed: 'focus.leaderboard_profile_failed',
  })
})

test('sync event metadata contains counts and safe failure classification only', () => {
  assert.deepEqual(focusSyncSucceededMetadata(3, 3), { entryCount: 3, syncedCount: 3 })
  assert.deepEqual(focusRejectedMetadata('invalid_payload'), { reason: 'invalid_payload' })
  assert.deepEqual(focusRejectedMetadata('device_not_bound'), { reason: 'device_not_bound' })
  assert.deepEqual(focusSyncFailedMetadata(3, new TypeError('raw details')), {
    entryCount: 3,
    errorName: 'TypeError',
  })
})

test('leaderboard profile event metadata never includes display name contents', () => {
  assert.deepEqual(leaderboardProfileUpdatedMetadata(true, 'Private Name'), {
    leaderboardOptIn: true,
    displayNameConfigured: true,
  })
  assert.deepEqual(leaderboardProfileUpdatedMetadata(false, null), {
    leaderboardOptIn: false,
    displayNameConfigured: false,
  })
  assert.deepEqual(leaderboardProfileFailedMetadata(new Error('private details')), {
    errorName: 'Error',
  })
})
