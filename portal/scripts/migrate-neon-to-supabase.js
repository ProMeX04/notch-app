/* eslint-disable @typescript-eslint/no-require-imports */
/**
 * migrate-neon-to-supabase.js
 * Copies all production data from Neon → Supabase.
 * Safe: uses ON CONFLICT DO NOTHING, so existing Supabase rows are never overwritten.
 * Run: node scripts/migrate-neon-to-supabase.js
 */

const { Pool } = require('pg');

const NEON_URL = 'postgresql://neondb_owner:npg_4eHfV3yJPbng@ep-silent-mode-a1aaq63g-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require';

const neon = new Pool({ connectionString: NEON_URL, ssl: { rejectUnauthorized: false }, max: 3 });
const supa = new Pool({
  host: 'aws-1-ap-southeast-2.pooler.supabase.com',
  port: 5432,
  database: 'postgres',
  user: 'postgres.xyhhtghehlzzzpitfveu',
  password: '@Mingw401072',
  ssl: { rejectUnauthorized: false },
  max: 3,
});

// Tables in dependency order (parents first)
const TABLES = [
  'User',
  'FeatureConfig',
  'GeminiLiveModelConfig',
  'GoogleDriveAuthHandoff',
  'AuthSession',
  'AuthBridgeToken',
  'AuthAppBridgeToken',
  'OAuthAuthorizationCode',
  'FocusDailyStat',
  'PaymentTransaction',
  'AppEvent',
];

async function getColumns(client, table) {
  const res = await client.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = $1
     ORDER BY ordinal_position`,
    [table]
  );
  return res.rows.map(r => r.column_name);
}

async function migrateTable(table) {
  const cols = await getColumns(neon, table);
  if (!cols.length) {
    console.log(`  ⚠️  ${table}: no columns found, skipping`);
    return 0;
  }

  const { rows } = await neon.query(`SELECT * FROM "${table}"`);
  if (!rows.length) {
    console.log(`  ○  ${table}: empty on Neon, skipping`);
    return 0;
  }

  const colList = cols.map(c => `"${c}"`).join(', ');
  const BATCH = 200;
  let inserted = 0;
  let skipped = 0;

  for (let i = 0; i < rows.length; i += BATCH) {
    const batch = rows.slice(i, i + BATCH);
    const placeholders = batch.map((_, bi) =>
      `(${cols.map((_, ci) => `$${bi * cols.length + ci + 1}`).join(', ')})`
    ).join(', ');
    const values = batch.flatMap(row => cols.map(c => row[c] ?? null));

    const sql = `INSERT INTO "${table}" (${colList}) VALUES ${placeholders} ON CONFLICT DO NOTHING`;
    const res = await supa.query(sql, values);
    inserted += res.rowCount ?? 0;
    skipped += batch.length - (res.rowCount ?? 0);
  }

  console.log(`  ✓  ${table}: ${rows.length} rows from Neon → ${inserted} inserted, ${skipped} already existed`);
  return inserted;
}

async function main() {
  console.log('\n🚀 Starting Neon → Supabase data migration\n');

  // Verify connections
  try {
    await neon.query('SELECT 1');
    console.log('✅ Neon connected');
  } catch (e) {
    console.error('❌ Cannot connect to Neon:', e.message);
    process.exit(1);
  }

  try {
    await supa.query('SELECT 1');
    console.log('✅ Supabase connected\n');
  } catch (e) {
    console.error('❌ Cannot connect to Supabase:', e.message);
    process.exit(1);
  }

  // Disable FK checks temporarily via session_replication_role
  await supa.query("SET session_replication_role = 'replica'");

  let totalInserted = 0;
  for (const table of TABLES) {
    try {
      totalInserted += await migrateTable(table);
    } catch (err) {
      console.error(`  ❌ ${table}: ${err.message}`);
    }
  }

  // Re-enable FK checks
  await supa.query("SET session_replication_role = 'origin'");

  console.log(`\n✅ Migration complete. Total rows inserted: ${totalInserted}`);
  await neon.end();
  await supa.end();
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
