import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const npmRoot = execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim();
const packageRoot = path.join(npmRoot, "@getpaseo", "server");

function findBridgeFile(root) {
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
        continue;
      }
      if (
        entry.isFile() &&
        entry.name === "bridge.js" &&
        full.includes(`${path.sep}agent${path.sep}providers${path.sep}opencode${path.sep}`)
      ) {
        return full;
      }
    }
  }
  return null;
}

const bridgeFile = findBridgeFile(packageRoot);
if (!bridgeFile) {
  throw new Error(`Unable to locate installed Paseo OpenCode bridge.js under ${packageRoot}`);
}

const source = fs.readFileSync(bridgeFile, "utf8");
const anchor = "inputSchema: serializePaseoToolInputParameters(tool),";
const replacement = `inputSchema: (() => {
        const schema = serializePaseoToolInputParameters(tool);
        // The OpenCode plugin manifest is shared across Paseo-managed OpenCode
        // sessions. The global/top-level create_agent schema contains
        // background, while every agent-scoped create_agent handler rejects
        // that field. Managed OpenCode sessions are always agent-scoped, so
        // hide this top-level-only field from the shared manifest.
        if (tool.name === "create_agent") {
          const properties = schema.properties;
          if (properties && typeof properties === "object" && !Array.isArray(properties)) {
            delete properties.background;
          }
          if (Array.isArray(schema.required)) {
            schema.required = schema.required.filter((field) => field !== "background");
          }
        }
        return schema;
      })(),`;

const occurrences = source.split(anchor).length - 1;
if (occurrences !== 1) {
  throw new Error(
    `Expected exactly one OpenCode manifest schema anchor in ${bridgeFile}; found ${occurrences}. ` +
      "The upstream Paseo bridge changed; review the patch before rebuilding."
  );
}

const patched = source.replace(anchor, replacement);
fs.writeFileSync(bridgeFile, patched);

const verified = fs.readFileSync(bridgeFile, "utf8");
if (
  !verified.includes('if (tool.name === "create_agent")') ||
  !verified.includes("delete properties.background")
) {
  throw new Error("Paseo OpenCode bridge patch verification failed");
}

console.log(`Patched Paseo OpenCode create_agent manifest schema: ${bridgeFile}`);
