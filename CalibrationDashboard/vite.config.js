import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    {
      name: "browser-only-preview",
      configureServer(server) {
        server.middlewares.use("/api", (_request, response) => {
          response.writeHead(404);
          response.end();
        });
      },
    },
  ],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  publicDir: false,
  build: { outDir: "dist", target: "es2022" },
});
