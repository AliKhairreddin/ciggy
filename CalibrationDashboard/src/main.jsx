import React from "react";
import { createRoot } from "react-dom/client";
import { setNonce } from "get-nonce";
import { App } from "./App";
import "./styles.css";

const styleNonce = document.querySelector(
  'meta[name="csp-style-nonce"]',
)?.content;
if (styleNonce) setNonce(styleNonce);
createRoot(document.getElementById("root")).render(<App />);
