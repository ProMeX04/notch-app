import { PrismaClient } from '@prisma/client'
import { PrismaNeon } from '@prisma/adapter-neon'
import 'dotenv/config'

const connectionString = process.env.DATABASE_URL?.trim()
const adapter = new PrismaNeon({ connectionString })
const prisma = new PrismaClient({ adapter })

async function main() {
  const configs = await prisma.featureConfig.findMany()
  console.log(JSON.stringify(configs, null, 2))
}

main().finally(() => prisma.$disconnect())
