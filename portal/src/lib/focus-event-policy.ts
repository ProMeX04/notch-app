export const focusEventTypes = {
  syncSucceeded: 'focus.sync_succeeded',
  syncRejected: 'focus.sync_rejected',
  syncFailed: 'focus.sync_failed',
  leaderboardProfileUpdated: 'focus.leaderboard_profile_updated',
  leaderboardProfileRejected: 'focus.leaderboard_profile_rejected',
  leaderboardProfileFailed: 'focus.leaderboard_profile_failed',
} as const

type FocusRejectedReason = 'unauthorized' | 'invalid_payload' | 'device_not_bound'

export function focusRejectedMetadata(reason: FocusRejectedReason) {
  return { reason }
}

export function focusSyncSucceededMetadata(entryCount: number, syncedCount: number) {
  return { entryCount, syncedCount }
}

export function focusSyncFailedMetadata(entryCount: number, error: unknown) {
  return {
    entryCount,
    errorName: error instanceof Error ? error.name : 'UnknownError',
  }
}

export function leaderboardProfileUpdatedMetadata(leaderboardOptIn: boolean, displayName: string | null) {
  return {
    leaderboardOptIn,
    displayNameConfigured: Boolean(displayName),
  }
}

export function leaderboardProfileFailedMetadata(error: unknown) {
  return { errorName: error instanceof Error ? error.name : 'UnknownError' }
}
