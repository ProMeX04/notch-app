#!/usr/bin/env node
/**
 * Dump TOEIC vocab mastery (+ optional notebook) from Chrome Local Extension Settings
 * for Block Shorts extension into a JSON file Notch can read.
 *
 * Usage:
 *   node script/export_block_shorts_toeic.mjs [output.json]
 */
import { ClassicLevel } from "classic-level";
import fs from "fs";
import os from "os";
import path from "path";
import { fileURLToPath } from "url";

const EXT_ID = "kdjoebngjpcdpfklfegbonlmdgcdlngk";
const chromeStore = path.join(
  os.homedir(),
  "Library/Application Support/Google/Chrome/Default/Local Extension Settings",
  EXT_ID
);

const outPath =
  process.argv[2] ||
  path.join(
    os.homedir(),
    "Library/Application Support/dev.notch/toeic/block_shorts_mastery.json"
  );

async function main() {
  if (!fs.existsSync(chromeStore)) {
    console.error("Chrome extension storage not found:", chromeStore);
    process.exit(2);
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "notch-toeic-export-"));
  for (const name of fs.readdirSync(chromeStore)) {
    if (name === "LOCK") continue;
    fs.copyFileSync(path.join(chromeStore, name), path.join(tmp, name));
  }

  const db = new ClassicLevel(tmp, {
    createIfMissing: false,
    keyEncoding: "utf8",
    valueEncoding: "utf8",
  });
  await db.open();

  const pick = async (key) => {
    try {
      return JSON.parse(await db.get(key));
    } catch {
      return null;
    }
  };

  const mastery = (await pick("toeic_vocab_mastery")) || {};
  const notebook = (await pick("gemini_vocab_notebook")) || [];
  const stats = (await pick("gemini_stats")) || {};
  const permanentQuestions =
    (await pick("toeic_vocab_permanent_questions_db")) || [];

  await db.close();

  const payload = {
    exportedAt: new Date().toISOString(),
    extensionId: EXT_ID,
    mastery,
    notebook,
    stats,
    permanentQuestionCount: Array.isArray(permanentQuestions)
      ? permanentQuestions.length
      : 0,
    // Keep questions optional — can be large; include for Notch quiz bank.
    permanentQuestions: Array.isArray(permanentQuestions)
      ? permanentQuestions
      : [],
  };

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(payload));
  console.log(
    JSON.stringify({
      ok: true,
      outPath,
      masteryWords: Object.keys(mastery).length,
      notebook: notebook.length,
      permanentQuestions: payload.permanentQuestionCount,
    })
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
