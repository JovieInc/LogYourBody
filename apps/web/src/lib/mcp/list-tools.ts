import { healthVaultMcpTools } from './health-vault-tools';
import { LYB_MCP_TOOLS, type ToolDefinition } from './tools';
import { weightMcpTools } from './weight-tools';

export type ListToolsOptions = {
  vault?: boolean;
  widgetSurface?: boolean;
};

function everyTool(): ToolDefinition[] {
  return [...LYB_MCP_TOOLS, ...weightMcpTools(), ...healthVaultMcpTools()];
}

export function listTools(
  delegatedEnabled = false,
  metricsEnabled = false,
  options: ListToolsOptions = {},
) {
  return everyTool()
    .filter((tool) => !tool.delegated || delegatedEnabled)
    .filter((tool) => tool.gate !== 'metrics' || metricsEnabled)
    .filter((tool) => tool.gate !== 'vault' || options.vault === true)
    .filter((tool) => !tool.widgetOnly || options.widgetSurface === true)
    .map((tool) => {
      const securitySchemes = [{ type: 'oauth2', scopes: [tool.scope] }];
      return {
        name: tool.name,
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema,
        ...(tool.outputSchema ? { outputSchema: tool.outputSchema } : {}),
        annotations: {
          title: tool.title,
          readOnlyHint: tool.readOnly,
          destructiveHint: tool.destructive === true,
          openWorldHint: false,
          idempotentHint: tool.idempotent ?? tool.readOnly,
        },
        securitySchemes,
        _meta: {
          securitySchemes,
          ...(tool.ui ? { ui: tool.ui } : {}),
          ...(tool.openai ?? {}),
        },
      };
    });
}

export function findTool(name: unknown): ToolDefinition | undefined {
  return everyTool().find((tool) => tool.name === name);
}
