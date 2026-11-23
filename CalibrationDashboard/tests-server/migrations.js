import { readFile, readdir } from "node:fs/promises";

const directory = new URL("../migrations/", import.meta.url);

export async function applyMigrations(db) {
  const files = (await readdir(directory)).filter(name => name.endsWith(".sql")).sort();
  for (const name of files) {
    const sql = await readFile(new URL(name, directory), "utf8");
    const statements = sql.split(";").map(statement => statement.trim()).filter(Boolean);
    await db.batch(statements.map(statement => db.prepare(statement)));
  }
}
