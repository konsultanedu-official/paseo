import { createPaseoClient } from "@getpaseo/client";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";

const daemonUrl = process.env.PASEO_DAEMON_URL ?? "ws://paseo:6767/ws";
const daemonPassword = process.env.PASEO_PASSWORD;
const host = process.env.PASEO_MCP_HOST ?? "0.0.0.0";
const port = Number(process.env.PASEO_MCP_PORT ?? "3000");
const workspaceRoot = process.env.PASEO_WORKSPACE_ROOT ?? "/workspace";
const maxText = Number(process.env.PASEO_MCP_MAX_TEXT ?? "60000");

if (!daemonPassword) throw new Error("PASEO_PASSWORD is required");
if (!Number.isInteger(port) || port <= 0 || port > 65535) throw new Error("Invalid PASEO_MCP_PORT");

const paseo = createPaseoClient({
  url: daemonUrl,
  password: daemonPassword,
  reconnect: { enabled: true, baseDelayMs: 500, maxDelayMs: 5000 },
});

await paseo.connect();

const server = new McpServer({
  name: "paseo-readonly",
  version: "0.1.0",
});

function json(value: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }],
  };
}

function text(value: string) {
  return {
    content: [{ type: "text" as const, text: value }],
  };
}

function truncate(value: string) {
  if (value.length <= maxText) return value;
  return value.slice(0, maxText) + "\n\n[truncated by paseo-readonly MCP]";
}

function safeRevision(value: string) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._/@:+-]{0,199}$/.test(value) || value.startsWith("-")) {
    throw new Error("Invalid git revision");
  }
  return value;
}

async function workspaceDirectory(workspaceId: string) {
  const result = await paseo.workspaces.list({ page: { limit: 200 } } as any);
  const ws = result.entries.find((entry: any) => entry.id === workspaceId);
  if (!ws) throw new Error("Workspace not found");

  const cwd = ws.workspaceDirectory;
  if (typeof cwd !== "string" || !cwd.startsWith(workspaceRoot + "/")) {
    throw new Error("Workspace directory is outside the allowed root");
  }
  return { ws, cwd };
}

async function git(cwd: string, args: string[]) {
  const proc = Bun.spawn(["git", "-C", cwd, ...args], {
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, GIT_PAGER: "cat", PAGER: "cat" },
  });

  const timeout = setTimeout(() => proc.kill(), 10_000);
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]).finally(() => clearTimeout(timeout));

  if (code !== 0) {
    throw new Error(truncate(stderr || `git exited with code ${code}`));
  }
  return truncate(stdout);
}

server.registerTool(
  "paseo_status",
  {
    description: "Check read-only connectivity to the Paseo daemon and return aggregate counts.",
    inputSchema: {},
  },
  async () => {
    const [projects, workspaces, agents] = await Promise.all([
      paseo.projects.list(),
      paseo.workspaces.list({ page: { limit: 200 } } as any),
      paseo.agents.list({ page: { limit: 200 } } as any),
    ]);
    return json({
      connected: true,
      daemon: daemonUrl.replace(/\/\/.*@/, "//[redacted]@"),
      projects: projects.entries?.length ?? 0,
      workspaces: workspaces.entries.length,
      agents: agents.entries.length,
      scope: "read-only",
    });
  },
);

server.registerTool(
  "paseo_list_projects",
  {
    description: "List Paseo projects using the official Paseo SDK. Read-only.",
    inputSchema: {},
  },
  async () => {
    const result = await paseo.projects.list();
    return json(
      (result.entries ?? []).map((project: any) => ({
        id: project.id,
        name: project.name,
        path: project.path ?? project.directory ?? null,
        repository: project.repository ?? null,
      })),
    );
  },
);

server.registerTool(
  "paseo_list_workspaces",
  {
    description: "List current Paseo workspaces and their safe operational metadata. Read-only.",
    inputSchema: {},
  },
  async () => {
    const result = await paseo.workspaces.list({ page: { limit: 200 } } as any);
    return json(
      result.entries.map((ws: any) => ({
        id: ws.id,
        projectId: ws.projectId ?? null,
        name: ws.name ?? ws.title ?? null,
        directory: ws.workspaceDirectory ?? null,
        status: ws.status ?? null,
        branch: ws.branch ?? ws.git?.branch ?? null,
        archivedAt: ws.archivedAt ?? null,
      })),
    );
  },
);

server.registerTool(
  "paseo_list_agents",
  {
    description: "List Paseo agents without exposing prompts, transcripts, or permission-response actions. Read-only.",
    inputSchema: {
      workspaceId: z.string().optional().describe("Optional workspace id filter"),
    },
  },
  async ({ workspaceId }) => {
    const result = await paseo.agents.list({ page: { limit: 200 } } as any);
    const entries = result.entries
      .map((entry: any) => entry.agent ?? entry)
      .filter((agent: any) => !workspaceId || agent.workspaceId === workspaceId)
      .map((agent: any) => ({
        id: agent.id,
        workspaceId: agent.workspaceId ?? null,
        title: agent.title ?? null,
        status: agent.status ?? null,
        provider: agent.config?.provider ?? agent.provider ?? null,
        cwd: agent.cwd ?? null,
        pendingPermissionCount: Array.isArray(agent.pendingPermissions)
          ? agent.pendingPermissions.length
          : 0,
        lastUsage: agent.lastUsage ?? null,
        lastError: agent.lastError ?? null,
        archivedAt: agent.archivedAt ?? null,
      }));
    return json(entries);
  },
);

server.registerTool(
  "paseo_git_status",
  {
    description: "Return git status for one Paseo workspace. Fixed read-only git command; no arbitrary shell.",
    inputSchema: {
      workspaceId: z.string().min(1),
    },
  },
  async ({ workspaceId }) => {
    const { cwd } = await workspaceDirectory(workspaceId);
    return text(await git(cwd, ["status", "--short", "--branch"]));
  },
);

server.registerTool(
  "paseo_git_log",
  {
    description: "Return a bounded recent git log for one Paseo workspace. Read-only.",
    inputSchema: {
      workspaceId: z.string().min(1),
      limit: z.number().int().min(1).max(50).default(10),
    },
  },
  async ({ workspaceId, limit }) => {
    const { cwd } = await workspaceDirectory(workspaceId);
    return text(await git(cwd, ["log", "--oneline", "--decorate", "-n", String(limit)]));
  },
);

server.registerTool(
  "paseo_git_diff",
  {
    description: "Return a bounded read-only git diff for one Paseo workspace. Optionally compare against a safe base revision.",
    inputSchema: {
      workspaceId: z.string().min(1),
      baseRef: z.string().optional().describe("Optional git revision such as origin/main"),
      cached: z.boolean().default(false),
    },
  },
  async ({ workspaceId, baseRef, cached }) => {
    const { cwd } = await workspaceDirectory(workspaceId);
    const args = ["diff", "--no-ext-diff", "--unified=3"];
    if (cached) args.push("--cached");
    if (baseRef) args.push(safeRevision(baseRef));
    args.push("--");
    return text(await git(cwd, args));
  },
);

const transport = new WebStandardStreamableHTTPServerTransport({
  sessionIdGenerator: undefined,
  enableJsonResponse: true,
});

await server.connect(transport);

Bun.serve({
  hostname: host,
  port,
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/healthz") {
      return Response.json({
        ok: true,
        name: "paseo-readonly",
        scope: "read-only",
      });
    }

    if (url.pathname !== "/mcp") {
      return new Response("Not Found", { status: 404 });
    }

    return transport.handleRequest(request);
  },
});

console.error(`paseo-readonly MCP listening on http://${host}:${port}/mcp`);
