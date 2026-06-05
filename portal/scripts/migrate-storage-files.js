const { Pool } = require('pg');

const SYDNEY_DB = {
  host: 'aws-1-ap-southeast-2.pooler.supabase.com',
  port: 5432,
  database: 'postgres',
  user: 'postgres.xyhhtghehlzzzpitfveu',
  password: '@Mingw401072',
  ssl: { rejectUnauthorized: false },
};

const SINGAPORE_ANON_KEY = 'sb_publishable_f_Mst2InX6EN_sGZ9ecRjQ_IGQwZzl7';
const SINGAPORE_STORAGE_URL = 'https://jtsshqvahplbjuljtmld.supabase.co/storage/v1/object/avatars';
const SYDNEY_PUBLIC_URL = 'https://xyhhtghehlzzzpitfveu.supabase.co/storage/v1/object/public/avatars';

async function main() {
  console.log('\n📦 Starting Supabase Storage migration (Sydney ➔ Singapore)\n');

  const pool = new Pool(SYDNEY_DB);
  
  // 1. Get all objects in 'avatars' bucket from Sydney DB
  let rows = [];
  try {
    const res = await pool.query("SELECT name FROM storage.objects WHERE bucket_id = 'avatars'");
    rows = res.rows;
    console.log(`Found ${rows.length} files in Sydney 'avatars' bucket.`);
  } catch (err) {
    console.error('Error querying Sydney DB storage objects:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }

  if (rows.length === 0) {
    console.log('No files to migrate.');
    return;
  }

  // 2. Loop through each file, download from Sydney and upload to Singapore
  for (const file of rows) {
    const name = file.name;
    const downloadUrl = `${SYDNEY_PUBLIC_URL}/${name}`;
    const uploadUrl = `${SINGAPORE_STORAGE_URL}/${name}`;

    console.log(`\n⏳ Migrating: ${name}`);
    console.log(`  Downloading: ${downloadUrl}`);

    try {
      const response = await fetch(downloadUrl);
      if (!response.ok) {
        throw new Error(`Failed to download: ${response.statusText} (${response.status})`);
      }

      const fileBuffer = await response.arrayBuffer();
      console.log(`  Downloaded successfully (${fileBuffer.byteLength} bytes).`);

      console.log(`  Uploading to Singapore Storage: ${uploadUrl}`);
      const uploadResponse = await fetch(uploadUrl, {
        method: 'POST',
        headers: {
          'apikey': SINGAPORE_ANON_KEY,
          'Authorization': `Bearer ${SINGAPORE_ANON_KEY}`,
          'Content-Type': 'image/webp',
        },
        body: fileBuffer,
      });

      if (!uploadResponse.ok) {
        const errText = await uploadResponse.text();
        // If file already exists, we might get a conflict, which is fine
        if (uploadResponse.status === 409 || errText.includes('Duplicate') || errText.includes('already exists')) {
          console.log(`  ✓ Already exists in Singapore, skipped.`);
        } else {
          throw new Error(`Failed to upload: ${uploadResponse.statusText} (${uploadResponse.status}) - ${errText}`);
        }
      } else {
        console.log(`  ✓ Uploaded successfully.`);
      }
    } catch (err) {
      console.error(`  ❌ Error migrating ${name}:`, err.message);
    }
  }

  console.log('\n🎉 Storage bucket migration complete!\n');
}

main().catch(console.error);
