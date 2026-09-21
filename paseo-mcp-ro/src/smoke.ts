import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const url = new URL(process.env.PASEO_MCP_TEST_URL ?? "http://127.0.0.1:3000/mcp");

const client = new Client({
  name: "paseo-readonly-smoke",
  version: "0.1.0",
});

const transport = new StreamableHTTPClientTransport(url);
await client.connect(transport);

try {
  const listed = await client.listTools();
  const names = listed.tools.map((tool) => tool.name).sort();

  const expected = [
    "paseo_git_diff",
    "paseo_git_log",
    "paseo_git_status",
    "paseo_list_agents",
    "paseo_list_projects",
    "paseo_list_workspaces",
    "paseo_status",
  ];

  const missing = expected.filter((name) => !names.includes(name));
  const unexpectedWriteLike = names.filter((name) =>
    /(write|edit|create|delete|archive|send|terminal|permission|schedule|browser)/i.test(name),
  );

  console.log("tools:", names.join(", "));
  console.log("missing:", missing.length ? missing.join(", ") : "none");
  console.log("write-like tools:", unexpectedWriteLike.length ? unexpectedWriteLike.join(", ") : "none");

  if (missing.length) throw new Error("Missing expected read-only tools");
  if (unexpectedWriteLike.length) throw new Error("Unexpected write/control tool exposed");

  const status = await client.callTool({ name: "paseo_status", arguments: {} });
  console.log("status:", JSON.stringify(status.content));

  console.log("PASS: read-only MCP tool surface is available");
} finally {
  await client.close();
}
