import { NextResponse } from 'next/server';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  
  // We pass all the searchParams into `state` so we can recover them in the callback.
  // This helps us remember the oauth request from the Notch macOS app (client_id, redirect_uri, etc.)
  const state = searchParams.toString();
  
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || 
    (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : 
    (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000'));
  const redirectUri = `${appUrl}/api/auth/google/callback`;

  if (!clientId) {
    return NextResponse.json({ error: 'Google Client ID is not configured' }, { status: 500 });
  }

  const googleAuthUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  googleAuthUrl.searchParams.append('client_id', clientId);
  googleAuthUrl.searchParams.append('redirect_uri', redirectUri);
  googleAuthUrl.searchParams.append('response_type', 'code');
  googleAuthUrl.searchParams.append('scope', 'openid email profile');
  googleAuthUrl.searchParams.append('access_type', 'online');
  googleAuthUrl.searchParams.append('state', state);

  return NextResponse.redirect(googleAuthUrl.toString());
}
