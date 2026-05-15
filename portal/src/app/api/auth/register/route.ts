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
    const { name, email: rawEmail, password } = body;
    const email = normalizeEmail(rawEmail);
    const normalizedName = typeof name === 'string' ? name.trim() : '';

    if (!email || !password) {
      await logAppEvent({
        req,
        eventType: 'auth.signup_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: 400,
        metadata: { reason: 'missing_credentials' },
      });
      return NextResponse.json({ error: 'Vui lòng nhập đầy đủ email và mật khẩu' }, { status: 400 });
    }

    if (!isValidEmail(email)) {
      await logAppEvent({
        req,
        eventType: 'auth.signup_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: 400,
        metadata: { reason: 'invalid_email' },
      });
      return NextResponse.json({ error: 'Email không hợp lệ' }, { status: 400 });
    }

    const existingUser = await prisma.user.findFirst({
      where: {
        email: {
          equals: email,
          mode: 'insensitive',
        },
      },
    });

    if (existingUser?.password) {
      await logAppEvent({
        req,
        eventType: 'auth.signup_rejected',
        outcome: 'rejected',
        source: 'web',
        actorUserId: existingUser.id,
        statusCode: 400,
        metadata: { reason: 'email_in_use' },
      });
      return NextResponse.json({ error: 'Email này đã được sử dụng' }, { status: 400 });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await prisma.$transaction(async (tx) => {
      const baseUser = existingUser
        ? await tx.user.update({
            where: { id: existingUser.id },
            data: {
              email,
              password: hashedPassword,
              name: normalizedName || existingUser.name || email.split('@')[0],
            },
          })
        : await tx.user.create({
            data: {
              name: normalizedName,
              email,
              password: hashedPassword,
            },
          });

      const hasPaidGuestTransaction = await tx.paymentTransaction.findFirst({
        where: {
          guestEmail: email,
          status: 'paid',
        },
        select: { id: true },
      });

      await tx.paymentTransaction.updateMany({
        where: {
          guestEmail: email,
          userId: null,
        },
        data: {
          userId: baseUser.id,
        },
      });

      if (hasPaidGuestTransaction && !baseUser.isPro) {
        return tx.user.update({
          where: { id: baseUser.id },
          data: { isPro: true },
        });
      }

      return baseUser;
    });

    const payload = await createAuthPayload(user, {
      req,
      device: body,
    });
    await logAppEvent({
      req,
      eventType: 'auth.signup_succeeded',
      outcome: 'success',
      source: 'web',
      actorUserId: user.id,
      sessionId: payload.session.id,
      deviceId: payload.session.device_id,
      statusCode: 201,
      metadata: {
        platform: payload.session.platform,
        trustedDevice: Boolean(payload.session.trusted_at),
      },
    });
    return applyAuthCookies(
      NextResponse.json(authPayloadUserResponse(payload.user, payload.session.id), { status: 201 }),
      payload,
    );
  } catch (error) {
    if (error instanceof AuthDeviceLimitError) {
      await logAppEvent({
        req,
        eventType: 'auth.signup_rejected',
        outcome: 'rejected',
        source: 'web',
        statusCode: error.statusCode,
        metadata: { reason: 'device_limit' },
      });
      return NextResponse.json({ error: error.message }, { status: error.statusCode });
    }
    console.error('Registration error:', error);
    return NextResponse.json({ error: 'Đã có lỗi xảy ra trong quá trình đăng ký' }, { status: 500 });
  }
}
