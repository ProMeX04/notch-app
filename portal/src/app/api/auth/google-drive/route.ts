import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const desktopState = (searchParams.get('state') || '').trim();
  const codeChallenge = (searchParams.get('code_challenge') || '').trim();

  const clientId = process.env.GOOGLE_CLIENT_ID;
  const requestUrl = new URL(req.url);
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || `${requestUrl.protocol}//${requestUrl.host}`;
  const redirectUri = `${appUrl}/api/auth/google/callback`;

  if (!clientId) {
    return NextResponse.json({ error: 'Google Client ID is not configured' }, { status: 500 });
  }

  if (!desktopState || desktopState.length > 256) {
    return NextResponse.json({ error: 'Missing or invalid Google Drive OAuth state' }, { status: 400 });
  }
  if (!/^[A-Za-z0-9_-]{43}$/.test(codeChallenge)) {
    return NextResponse.json({ error: 'Missing or invalid Google Drive handoff challenge' }, { status: 400 });
  }

  const googleDriveState = new URLSearchParams({
    gdrive: 'true',
    desktop_state: desktopState,
    code_challenge: codeChallenge,
  });

  const googleAuthUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  googleAuthUrl.searchParams.append('client_id', clientId);
  googleAuthUrl.searchParams.append('redirect_uri', redirectUri);
  googleAuthUrl.searchParams.append('response_type', 'code');
  googleAuthUrl.searchParams.append('scope', 'https://www.googleapis.com/auth/drive.file');
  googleAuthUrl.searchParams.append('access_type', 'offline');
  googleAuthUrl.searchParams.append('prompt', 'consent');
  googleAuthUrl.searchParams.append('state', googleDriveState.toString());

  return NextResponse.redirect(googleAuthUrl.toString());
}
