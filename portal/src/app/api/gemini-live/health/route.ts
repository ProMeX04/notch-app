import { NextResponse } from 'next/server'

export async function GET() {
  return NextResponse.json({
    ok: true,
    apiVersion: '1',
    mode: 'portal',
    auth: 'bearer',
  })
}
