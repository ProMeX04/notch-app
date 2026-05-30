import 'dotenv/config'
import { PrismaClient } from '@prisma/client'

import { PrismaPg } from '@prisma/adapter-pg'
import { Pool } from 'pg'
import { parse } from 'pg-connection-string'

const prismaClientSingleton = () => {
  const connectionString = process.env.DATABASE_URL?.trim()
  if (!connectionString) {
    throw new Error('DATABASE_URL is not set.')
  }
  
  const config = parse(connectionString)
  const pool = new Pool({
    host: config.host || undefined,
    port: config.port ? parseInt(config.port, 10) : undefined,
    user: config.user || undefined,
    password: config.password || undefined,
    database: config.database || undefined,
    ssl: { rejectUnauthorized: false }
  })
  const adapter = new PrismaPg(pool)
  
  return new PrismaClient({ adapter })
}

declare global {
  var prisma: undefined | ReturnType<typeof prismaClientSingleton>
}

let prisma: ReturnType<typeof prismaClientSingleton>;

if (process.env.NODE_ENV === 'production') {
  prisma = prismaClientSingleton()
} else {
  if (!global.prisma) {
    global.prisma = prismaClientSingleton()
  }
  prisma = global.prisma
}

export default prisma
