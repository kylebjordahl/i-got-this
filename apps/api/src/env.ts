/** Worker bindings (kept in sync with wrangler.jsonc + Terraform). */
export interface Bindings {
  DB: D1Database;
  ENVIRONMENT: string;
}

export type HonoEnv = { Bindings: Bindings };
