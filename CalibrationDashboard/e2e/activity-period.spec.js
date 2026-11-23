import { expect, test } from "@playwright/test";
import { recording } from "./recording.js";

test("the timeline covers both files and a saved label uses the current period", async ({ page }) => {
  await page.clock.setFixedTime(new Date("2026-02-03T12:00:00Z"));
  await page.goto("/");

  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Import recordings", exact: true }).click();
  const files = [
    recording("00000000-0000-4000-8000-000000000001", "2026-02-02T11:00:00Z"),
    recording("00000000-0000-4000-8000-000000000002", "2026-02-03T10:59:58Z"),
  ];
  await (await chooser).setFiles(files.map(file => ({
    name: file.id + ".json",
    mimeType: "application/json",
    buffer: Buffer.from(JSON.stringify(file)),
  })));
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("Participant alias").fill("Fixture");
  await dialog.getByRole("button", { name: "Import recordings" }).click();
  await expect(dialog).toBeHidden();

  const period = page.getByRole("combobox", { name: "Time period" });
  await period.selectOption({ label: "All imported data" });
  await expect(page.getByText("Feb 2, 11:00 AM — Feb 3, 11:00 AM", { exact: true })).toBeVisible();
  const from = page.getByLabel("From", { exact: true });
  const to = page.getByLabel("To", { exact: true });
  await expect(from).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T10:59:58Z"));

  await period.selectOption({ label: "Past hour" });
  await expect(from).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:00Z"));
  await page.clock.setFixedTime(new Date("2026-02-03T12:00:05Z"));
  await page.getByRole("button", { name: "Refresh", exact: true }).click();
  await expect(from).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:05Z"));
  await expect(to).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:12Z"));

  await page.getByLabel("Notes (optional)").fill("Synthetic interval");
  await expect(period).toBeDisabled();
  await page.getByRole("button", { name: "Save activity label" }).click();
  await expect(page.getByText("Activity label saved.")).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "Edit activity label" }).click();
  await expect(page.getByLabel("Notes (optional)")).toHaveValue("Synthetic interval");
  await expect(from).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:05Z"));
  await expect(to).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:12Z"));

  await page.getByLabel("Activity", { exact: true }).selectOption("drinking");
  await from.fill("2026-02-03T11:00:06");
  await page.getByRole("button", { name: "Save changes" }).click();
  await expect(page.getByRole("button", { name: "Save activity label" })).toBeEnabled();
  await expect(page.getByLabel("Activity", { exact: true })).toHaveValue("drinking");
  await expect(from).toHaveJSProperty("valueAsNumber", Date.parse("2026-02-03T11:00:06Z"));
});
