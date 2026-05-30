import { NextResponse } from 'next/server';
import { randomBytes } from 'node:crypto';
import prisma from '@/lib/prisma';
import { applyAuthCookies } from '@/lib/auth-cookies';
import { createAuthPayload } from '@/lib/notch-auth';
import { logAppEvent } from '@/lib/event-logger';
import { hashToken } from '@/lib/auth/token-service';
import { encryptGoogleDriveHandoffValue } from '@/lib/google-drive-handoff-crypto';

const GOOGLE_DRIVE_HANDOFF_TTL_MS = 5 * 60 * 1000;

function googleDriveDesktopState(rawState: string) {
  const params = new URLSearchParams(rawState);
  if (params.get('gdrive') !== 'true') return null;
  return (params.get('desktop_state') || '').trim();
}

function googleDriveCodeChallenge(rawState: string) {
  const params = new URLSearchParams(rawState);
  if (params.get('gdrive') !== 'true') return null;
  return (params.get('code_challenge') || '').trim();
}

function escapeHTMLAttribute(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

function normalizedGoogleAvatarURL(value: unknown) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  try {
    const url = new URL(trimmed);
    const hostname = url.hostname.toLowerCase();
    const isGoogleAvatarHost = hostname === 'googleusercontent.com'
      || hostname.endsWith('.googleusercontent.com')
      || hostname === 'google.com'
      || hostname.endsWith('.google.com');
    if (url.protocol !== 'https:' || !isGoogleAvatarHost) return null;
    return url.toString();
  } catch {
    return null;
  }
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const code = searchParams.get('code');
  const state = searchParams.get('state') || '';
  const desktopState = googleDriveDesktopState(state);
  const driveCodeChallenge = googleDriveCodeChallenge(state);

  if (!code) {
    if (desktopState) {
      const deepLink = new URL('notch://gdrive/callback');
      deepLink.searchParams.set('state', desktopState);
      deepLink.searchParams.set('error', searchParams.get('error') || 'Canceled');
      const deepLinkString = deepLink.toString();
      return new NextResponse(
        `<!doctype html><meta charset="utf-8"><title>Notch Google Drive</title><p>Google Drive authorization was canceled.</p><a href="${escapeHTMLAttribute(deepLinkString)}">Return to Notch</a><script>window.location.href=${JSON.stringify(deepLinkString)};</script>`,
        { headers: { 'Content-Type': 'text/html; charset=utf-8' } },
      );
    }
    return NextResponse.redirect(new URL('/?error=Canceled', req.url));
  }

  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const requestUrl = new URL(req.url);
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || `${requestUrl.protocol}//${requestUrl.host}`;
  const redirectUri = `${appUrl}/api/auth/google/callback`;

  if (desktopState !== null) {
    if (!clientId || !clientSecret) {
      return NextResponse.json({ error: 'Google Client ID/Secret not configured' }, { status: 500 });
    }
    if (!desktopState) {
      return NextResponse.json({ error: 'Missing Google Drive OAuth state' }, { status: 400 });
    }
    if (!driveCodeChallenge || !/^[A-Za-z0-9_-]{43}$/.test(driveCodeChallenge)) {
      return NextResponse.json({ error: 'Missing or invalid Google Drive handoff challenge' }, { status: 400 });
    }

    try {
      const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          code,
          grant_type: 'authorization_code',
          redirect_uri: redirectUri,
        }),
      });

      const tokenData = await tokenResponse.json();

      if (!tokenResponse.ok) {
        console.error('Google token error:', tokenData);
        return NextResponse.json({ error: 'Failed to exchange token' }, { status: 400 });
      }

      const accessToken = typeof tokenData.access_token === 'string' ? tokenData.access_token : '';
      const refreshToken = typeof tokenData.refresh_token === 'string' ? tokenData.refresh_token : null;
      const expiresIn = typeof tokenData.expires_in === 'number' ? tokenData.expires_in : null;
      if (!accessToken) {
        return NextResponse.json({ error: 'Google token exchange returned no access token' }, { status: 400 });
      }
      const handoffToken = randomBytes(32).toString('base64url');
      const handoffId = `gdh_${randomBytes(12).toString('hex')}`;
      const handoffExpiresAt = new Date(Date.now() + GOOGLE_DRIVE_HANDOFF_TTL_MS);

      await prisma.$executeRaw`
        INSERT INTO "GoogleDriveAuthHandoff" (
          "id",
          "tokenHash",
          "codeChallenge",
          "accessToken",
          "refreshToken",
          "expiresIn",
          "expiresAt",
          "createdAt"
        )
        VALUES (
          ${handoffId},
          ${hashToken(handoffToken)},
          ${driveCodeChallenge},
          ${encryptGoogleDriveHandoffValue(accessToken)},
          ${refreshToken ? encryptGoogleDriveHandoffValue(refreshToken) : null},
          ${expiresIn},
          ${handoffExpiresAt},
          NOW()
        )
      `;

      const deepLink = new URL('notch://gdrive/callback');
      deepLink.searchParams.set('handoff_token', handoffToken);
      deepLink.searchParams.set('state', desktopState);
      const deepLinkString = deepLink.toString();
      const deepLinkHref = escapeHTMLAttribute(deepLinkString);
      const deepLinkScript = JSON.stringify(deepLinkString);

      const html = `
        <!DOCTYPE html>
        <html>
        <head>
          <title>Notch Google Drive Connection</title>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
              display: flex;
              align-items: center;
              justify-content: center;
              height: 100vh;
              background-color: #0d0d0e;
              color: #f3f4f6;
              margin: 0;
              padding: 16px;
              box-sizing: border-box;
            }
            .card {
              text-align: center;
              max-width: 420px;
              width: 100%;
              padding: 32px;
              background: rgba(255, 255, 255, 0.03);
              border-radius: 24px;
              border: 1px solid rgba(255, 255, 255, 0.08);
              box-shadow: 0 20px 40px rgba(0,0,0,0.5);
              backdrop-filter: blur(20px);
            }
            h2 {
              font-size: 1.5rem;
              margin-top: 0;
              margin-bottom: 8px;
              font-weight: 700;
              letter-spacing: -0.025em;
            }
            p {
              font-size: 0.95rem;
              color: #9ca3af;
              line-height: 1.5;
              margin-bottom: 24px;
            }
            .button {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              padding: 14px 28px;
              background: linear-gradient(135deg, #3b82f6, #1d4ed8);
              color: #fff;
              text-decoration: none;
              border-radius: 12px;
              font-weight: 600;
              font-size: 0.95rem;
              transition: all 0.2s ease;
              box-shadow: 0 4px 12px rgba(37, 99, 235, 0.3);
              border: none;
              cursor: pointer;
              width: 100%;
              box-sizing: border-box;
            }
            .button:hover {
              transform: translateY(-1px);
              box-shadow: 0 6px 20px rgba(37, 99, 235, 0.4);
            }
            .button:active {
              transform: translateY(1px);
            }
            .logo {
              width: 64px;
              height: 64px;
              margin: 0 auto 20px;
              background: rgba(255,255,255,0.05);
              border-radius: 18px;
              display: flex;
              align-items: center;
              justify-content: center;
            }
            .logo svg {
              width: 32px;
              height: 32px;
              fill: #3b82f6;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="logo">
              <svg viewBox="0 0 24 24">
                <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM19 18H6c-2.21 0-4-1.79-4-4 0-2.05 1.53-3.76 3.56-3.97l1.07-.11.5-.95C8.08 7.14 9.94 6 12 6c2.62 0 4.88 1.86 5.39 4.43l.3 1.5 1.53.11c1.56.1 2.78 1.41 2.78 2.96 0 1.65-1.35 3-3 3z"/>
              </svg>
            </div>
            <h2>Kết nối Google Drive thành công!</h2>
            <p>Ứng dụng Notch sẽ tự động mở để hoàn tất liên kết. Nếu không thấy phản hồi, vui lòng nhấn nút bên dưới.</p>
            <a href="${deepLinkHref}" class="button">Hoàn tất liên kết</a>
          </div>
          <script>
            window.location.href = ${deepLinkScript};
          </script>
        </body>
        </html>
      `;

      return new NextResponse(html, {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
        },
      });

    } catch (error) {
      console.error('Google Drive callback error:', error);
      return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
  }

  if (!clientId || !clientSecret) {
    await logAppEvent({
      req,
      eventType: 'auth.google_login_failed',
      outcome: 'failure',
      source: 'oauth',
      statusCode: 500,
      metadata: { reason: 'google_oauth_not_configured' },
    });
    return NextResponse.json({ error: 'Google Client ID/Secret not configured' }, { status: 500 });
  }

  try {
    // 1. Exchange the authorization code for an access token
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: 'authorization_code',
        redirect_uri: redirectUri,
      }),
    });

    const tokenData = await tokenResponse.json();

    if (!tokenResponse.ok) {
      console.error('Google token error:', tokenData);
      await logAppEvent({
        req,
        eventType: 'auth.google_login_failed',
        outcome: 'failure',
        source: 'oauth',
        statusCode: 400,
        metadata: { reason: 'token_exchange_failed' },
      });
      return NextResponse.redirect(new URL(`/?error=Failed to exchange token`, req.url));
    }

    const { access_token } = tokenData;

    // 2. Fetch the user profile from Google
    const profileResponse = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
      headers: {
        Authorization: `Bearer ${access_token}`,
      },
    });

    const profileData = await profileResponse.json();

    if (!profileResponse.ok || !profileData.email) {
      console.error('Google profile error:', profileData);
      await logAppEvent({
        req,
        eventType: 'auth.google_login_failed',
        outcome: 'failure',
        source: 'oauth',
        statusCode: 400,
        metadata: { reason: 'profile_fetch_failed' },
      });
      return NextResponse.redirect(new URL(`/?error=Failed to fetch profile`, req.url));
    }

    const { email, name } = profileData;
    const lowerEmail = email.toLowerCase().trim();
    const avatarUrl = normalizedGoogleAvatarURL(profileData.picture);

    // 3. Find or Create the User in the database
    let user = await prisma.user.findFirst({
      where: {
        email: {
          equals: lowerEmail,
          mode: 'insensitive',
        },
      },
    });

    const isNewUser = !user;
    if (!user) {
      user = await prisma.user.create({
        data: {
          email: lowerEmail,
          name: name || null,
          avatarUrl,
          password: null, // Google users don't have a password
        },
      });
    } else if (user.avatarUrl !== avatarUrl) {
      user = await prisma.user.update({
        where: { id: user.id },
        data: { avatarUrl },
      });
    }

    // 4. Create a Notch Session
    const payload = await createAuthPayload(user, {
      req,
      device: { device_id: 'google-oauth', device_name: 'Browser', platform: 'Web' },
    });

    await logAppEvent({
      req,
      eventType: isNewUser ? 'auth.google_signup_succeeded' : 'auth.google_login_succeeded',
      outcome: 'success',
      source: 'oauth',
      actorUserId: user.id,
      sessionId: payload.session.id,
      deviceId: payload.session.device_id,
      statusCode: 302,
      metadata: {
        emailDomain: email.split('@')[1] ?? null,
        trustedDevice: Boolean(payload.session.trusted_at),
      },
    });

    // 5. Determine redirect destination
    // If state has oauth parameters, we redirect back to /oauth/authorize to finish the flow
    let redirectDestination = '/account';
    if (state.includes('client_id=')) {
      redirectDestination = `/oauth/authorize?${state}`;
    }

    // 6. Set Cookies and Redirect
    const response = NextResponse.redirect(new URL(redirectDestination, req.url));
    return applyAuthCookies(response, payload);

  } catch (error) {
    console.error('Google OAuth error:', error);
    await logAppEvent({
      req,
      eventType: 'auth.google_login_failed',
      outcome: 'failure',
      source: 'oauth',
      statusCode: 500,
      metadata: { reason: 'internal_error' },
    });
    return NextResponse.redirect(new URL('/?error=Internal Server Error', req.url));
  }
}
