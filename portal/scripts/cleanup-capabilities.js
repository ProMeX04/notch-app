import { PrismaClient } from '@prisma/client'
import { PrismaNeon } from '@prisma/adapter-neon'
import 'dotenv/config'

const connectionString = process.env.DATABASE_URL?.trim()
const adapter = new PrismaNeon({ connectionString })
const prisma = new PrismaClient({ adapter })

async function main() {
  console.log('Cleaning up capabilities...')

  // Get the current state of gemini_live
  const geminiLive = await prisma.featureConfig.findUnique({
    where: { key: 'gemini_live' }
  })

  if (geminiLive) {
    console.log(`Found old gemini_live: isProOnly=${geminiLive.isProOnly}, isEnabled=${geminiLive.isEnabled}`)
    
    // Sync to talk_connection
    await prisma.featureConfig.upsert({
      where: { key: 'talk_connection' },
      update: {
        isProOnly: geminiLive.isProOnly,
        isEnabled: geminiLive.isEnabled
      },
      create: {
        key: 'talk_connection',
        name: 'Gemini Live (Talk)',
        description: 'Ability to use real-time voice chat with Gemini.',
        isProOnly: geminiLive.isProOnly,
        isEnabled: geminiLive.isEnabled
      }
    })
    
    console.log('Synced talk_connection with gemini_live state.')
    
    // Delete old keys
    await prisma.featureConfig.delete({ where: { key: 'gemini_live' } })
    console.log('Deleted old gemini_live.')
  }

  // Delete other old keys
  const oldKeys = ['advanced_pomodoro', 'shelf_storage']
  for (const key of oldKeys) {
    try {
      await prisma.featureConfig.delete({ where: { key } })
      console.log(`Deleted old key: ${key}`)
    } catch {
    }
  }

  console.log('Cleanup done.')
}

main().finally(() => prisma.$disconnect())
