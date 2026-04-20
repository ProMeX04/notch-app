import { NextResponse } from 'next/server'

export async function POST(req: Request) {
  void req
  return NextResponse.json(
    { detail: 'Vui lòng đăng nhập hoặc tạo tài khoản trước khi nâng cấp Pro.' },
    { status: 403 },
  )
}
