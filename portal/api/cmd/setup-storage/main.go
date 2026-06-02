package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	devDbURL  = "postgresql://postgres.jtsshqvahplbjuljtmld:%40Mingw401072@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres?sslmode=require"
	prodDbURL = "postgresql://postgres.xyhhtghehlzzzpitfveu:%40Mingw401072@aws-1-ap-southeast-2.pooler.supabase.com:6543/postgres?sslmode=require"
)

const sqlQueries = `
--// Create or update avatars bucket with size limit (200KB) and WebP only
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 204800, ARRAY['image/webp'])
ON CONFLICT (id) DO UPDATE 
SET file_size_limit = 204800, allowed_mime_types = ARRAY['image/webp'];

-- 1. SELECT (View avatars)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Public Access to avatars'
    ) THEN
        CREATE POLICY "Public Access to avatars" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
    END IF;
END
$$;

-- 2. INSERT (Upload avatars)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Public Upload to avatars'
    ) THEN
        CREATE POLICY "Public Upload to avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars');
    END IF;
END
$$;

-- 3. UPDATE (Overwrite avatars)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Public Update to avatars'
    ) THEN
        CREATE POLICY "Public Update to avatars" ON storage.objects FOR UPDATE USING (bucket_id = 'avatars');
    END IF;
END
$$;

-- 4. DELETE (Remove avatars)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Public Delete from avatars'
    ) THEN
        CREATE POLICY "Public Delete from avatars" ON storage.objects FOR DELETE USING (bucket_id = 'avatars');
    END IF;
END
$$;
`

func setupProject(name, dbURL string) {
	fmt.Printf("\n⚙️  Setting up Supabase Storage for project [%s]...\n", name)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Printf("  ❌ Failed to connect to %s database: %v\n", name, err)
		return
	}
	defer conn.Close(ctx)

	fmt.Printf("  ✅ Connected to %s database\n", name)

	_, err = conn.Exec(ctx, sqlQueries)
	if err != nil {
		log.Printf("  ❌ Failed to execute storage setup SQL for %s: %v\n", name, err)
		return
	}

	fmt.Printf("  🎉 Successfully created 'avatars' bucket & configured storage policies for %s\n", name)
}

func main() {
	setupProject("Dev (jtsshqvahplbjuljtmld)", devDbURL)
	setupProject("Prod (xyhhtghehlzzzpitfveu)", prodDbURL)
	fmt.Println("\n✨ Go Storage Setup Tool Complete!")
}
