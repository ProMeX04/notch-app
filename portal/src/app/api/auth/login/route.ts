import { NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import prisma from '@/lib/prisma';
import { applyAuthCookies } from '@/lib/auth-cookies';
import { isValidEmail, normalizeEmail } from '@/lib/email';
import { AuthDeviceLimitError, authPayloadUserResponse, createAuthPayload } from '@/lib/notch-auth';

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const { email: rawEmail, password } = body;
    const email = normalizeEmail(rawEmail);

    if (!email || !password) {
      return NextResponse.json({ error: 'Vui lòng nhập email và mật khẩu' }, { status: 400 });
    }

    if (!isValidEmail(email)) {
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
      return NextResponse.json({ error: 'Email hoặc mật khẩu không chính xác' }, { status: 401 });
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
    }

    const payload = await createAuthPayload(user, {
      req,
      device: body,
    });
    return applyAuthCookies(
      NextResponse.json(authPayloadUserResponse(payload.user, payload.session.id)),
      payload,
    );
  } catch (error: unknown) {
    if (error instanceof AuthDeviceLimitError) {
      return NextResponse.json({ error: error.message }, { status: error.statusCode });
    }
    console.error('Login error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Đã có lỗi xảy ra' },
      { status: 500 }
    );
  }
}
