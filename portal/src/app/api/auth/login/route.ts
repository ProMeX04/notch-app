import { NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import prisma from '@/lib/prisma';
import { applyAuthCookies } from '@/lib/auth-cookies';
import { isValidEmail, normalizeEmail } from '@/lib/email';
import { logAppEvent } from '@/lib/event-logger';
import { AuthDeviceLimitError, authPayloadUserResponse, createAuthPayload } from '@/lib/notch-auth';

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const { email: rawEmail, password } = body;
    const email = normalizeEmail(rawEmail);

    if (!email || !password) {
      await logAppEvent({
        req,
        eventType: 'auth.login_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: 400,
        metadata: { reason: 'missing_credentials' },
      });
      return NextResponse.json({ error: 'Vui lòng nhập email và mật khẩu' }, { status: 400 });
    }

    if (!isValidEmail(email)) {
      await logAppEvent({
        req,
        eventType: 'auth.login_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: 400,
        metadata: { reason: 'invalid_email' },
      });
      return NextResponse.json({ error: 'Email không hợp lệ' }, { status: 400 });
    }

    const user = await prisma.user.findFirst({
      where: {
        email: {
          equals: email,
          mode: 'insensitive',
        },
      },
    });

    if (!user || !user.password) {
      await logAppEvent({
        req,
        eventType: 'auth.login_failed',
        outcome: 'failure',
        source: 'web',
        statusCode: 401,
        metadata: { reason: 'invalid_credentials' },
      });
      return NextResponse.json({ error: 'Email hoặc mật khẩu không chính xác' }, { status: 401 });
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      await logAppEvent({
        req,
        eventType: 'auth.login_failed',
        outcome: 'failure',
        source: 'web',
        actorUserId: user.id,
        statusCode: 401,
        metadata: { reason: 'invalid_credentials' },
      });
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    const payload = await createAuthPayload(user, {
      req,
      device: body,
    });
    await logAppEvent({
      req,
      eventType: 'auth.login_succeeded',
      outcome: 'success',
      source: 'web',
      actorUserId: user.id,
      sessionId: payload.session.id,
      deviceId: payload.session.device_id,
      statusCode: 200,
      metadata: {
        platform: payload.session.platform,
        trustedDevice: Boolean(payload.session.trusted_at),
      },
    });
    return applyAuthCookies(
      NextResponse.json(authPayloadUserResponse(payload.user, payload.session.id)),
      payload,
      req,
    );
  } catch (error: unknown) {
    if (error instanceof AuthDeviceLimitError) {
      await logAppEvent({
        req,
        eventType: 'auth.login_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: error.statusCode,
        metadata: { reason: 'device_limit' },
      });
      return NextResponse.json({ error: error.message }, { status: error.statusCode });
    }
    console.error('Login error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Đã có lỗi xảy ra' },
      { status: 500 }
    );
  }
}
