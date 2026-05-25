import { NextResponse } from 'next/server';
import { createHash } from 'node:crypto';

import { decryptGoogleDriveHandoffValue } from '@/lib/google-drive-handoff-crypto';
import { hashToken } from '@/lib/auth/token-service';
import prisma from '@/lib/prisma';

export const dynamic = 'force-dynamic';

type GoogleDriveHandoffRow = {
  id: string;
  codeChallenge: string;
  accessToken: string;
  refreshToken: string | null;
  expiresIn: number | null;
  expiresAt: Date;
  consumedAt: Date | null;
};

export async function POST(req: Request) {
  try {
    const body = await req.json().catch(() => null) as {
      handoff_token?: unknown;
      code_verifier?: unknown;
    } | null;
    const handoffToken = typeof body?.handoff_token === 'string' ? body.handoff_token.trim() : '';
    const codeVerifier = typeof body?.code_verifier === 'string' ? body.code_verifier.trim() : '';

    if (!handoffToken || !/^[A-Za-z0-9_-]{43,128}$/.test(codeVerifier)) {
      return NextResponse.json({ error: 'Missing handoff credentials' }, { status: 400 });
    }

    const result = await prisma.$transaction(async (tx) => {
      const now = new Date();
      const rows = await tx.$queryRaw<GoogleDriveHandoffRow[]>`
        SELECT
          "id",
          "codeChallenge",
          "accessToken",
          "refreshToken",
          "expiresIn",
          "expiresAt",
          "consumedAt"
        FROM "GoogleDriveAuthHandoff"
        WHERE "tokenHash" = ${hashToken(handoffToken)}
        LIMIT 1
      `;

      const handoff = rows[0];
      if (!handoff || handoff.consumedAt || handoff.expiresAt <= now) {
        return null;
      }
      const suppliedChallenge = createHash('sha256').update(codeVerifier).digest('base64url');
      if (suppliedChallenge !== handoff.codeChallenge) {
        return null;
      }
      const accessToken = decryptGoogleDriveHandoffValue(handoff.accessToken);
      const refreshToken = handoff.refreshToken
        ? decryptGoogleDriveHandoffValue(handoff.refreshToken)
        : null;

      const updated = await tx.$executeRaw`
        UPDATE "GoogleDriveAuthHandoff"
        SET
          "consumedAt" = ${now},
          "accessToken" = '',
          "refreshToken" = NULL
        WHERE
          "id" = ${handoff.id}
          AND "consumedAt" IS NULL
          AND "expiresAt" > ${now}
      `;

      if (updated !== 1) {
        return null;
      }

      return {
        access_token: accessToken,
        refresh_token: refreshToken,
        expires_in: handoff.expiresIn,
      };
    });

    await prisma.$executeRaw`
      DELETE FROM "GoogleDriveAuthHandoff"
      WHERE "expiresAt" <= ${new Date(Date.now() - 60 * 1000)}
    `.catch(() => {});

    if (!result) {
      return NextResponse.json({ error: 'Invalid or expired handoff token' }, { status: 400 });
    }

    return NextResponse.json(result);
  } catch (error: unknown) {
    console.error('Google Drive handoff exchange error:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
