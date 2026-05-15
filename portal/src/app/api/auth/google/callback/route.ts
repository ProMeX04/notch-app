import { NextResponse } from 'next/server';
import prisma from '@/lib/prisma';
import { applyAuthCookies } from '@/lib/auth-cookies';
import { createAuthPayload } from '@/lib/notch-auth';
import { logAppEvent } from '@/lib/event-logger';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const code = searchParams.get('code');
  const state = searchParams.get('state') || '';

  if (!code) {
    return NextResponse.redirect(new URL('/?error=Canceled', req.url));
  }

  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ||
    (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` :
    (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000'));
  const redirectUri = `${appUrl}/api/auth/google/callback`;

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
          password: null, // Google users don't have a password
        },
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
    let redirectDestination = '/pro';
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
