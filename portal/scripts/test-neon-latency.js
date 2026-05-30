/* eslint-disable @typescript-eslint/no-require-imports */
require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const { PrismaPg } = require('@prisma/adapter-pg');
const { Pool } = require('pg');

const { parse } = require('pg-connection-string');
const config = parse(process.env.DATABASE_URL);
config.ssl = { rejectUnauthorized: false };
const pool = new Pool(config);
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

async function main() {
  console.log('Connecting to database...');
  
  const startCold = Date.now();
  try {
    const userCount = await prisma.user.count();
    const endCold = Date.now();
    console.log(`Total users in DB: ${userCount}`);
    console.log(`Cold query duration (Connection spin-up): ${endCold - startCold}ms`);
  } catch (err) {
    console.error('Failed to query database:', err);
    process.exit(1);
  }

  const runs = 5;
  let total = 0;
  console.log(`\nRunning ${runs} warm queries to measure active connection latency...`);
  for (let i = 1; i <= runs; i++) {
    const start = Date.now();
    await prisma.user.count();
    const end = Date.now();
    const duration = end - start;
    console.log(`Query #${i} response: ${duration}ms`);
    total += duration;
  }

  console.log(`\nAverage active query response time: ${(total / runs).toFixed(2)}ms`);
  await prisma.$disconnect();
}

main().catch(console.error);
