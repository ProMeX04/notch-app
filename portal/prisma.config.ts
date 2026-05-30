import "dotenv/config";
import { defineConfig, env } from "prisma/config";

const hasDbUrl = (process.env.DIRECT_URL?.trim() || process.env.DATABASE_URL?.trim()) !== undefined;
const urlVal = hasDbUrl 
  ? (process.env.DIRECT_URL?.trim() ? env("DIRECT_URL") : env("DATABASE_URL"))
  : "postgresql://dummy:dummy@localhost:5432/dummy";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
  },
  datasource: {
    url: urlVal,
  },
});
