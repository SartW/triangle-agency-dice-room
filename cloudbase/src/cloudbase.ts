const ENV_ID = "triangle-agency-dice-d5a49141400";
const API_ROOT = `https://${ENV_ID}.api.tcloudbasegateway.com/v1/rdb/rest/rpc`;
const AUTH_URL = `https://${ENV_ID}.api.tcloudbasegateway.com/auth/v1/signin/anonymously`;

let accessToken: Promise<string> | null = null;

async function ensureAnonymousSession(): Promise<string> {
  if (!accessToken) {
    accessToken = (async () => {
      const response = await fetch(AUTH_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-device-id": actorToken(),
        },
        body: "{}",
      });
      const data = await response.json().catch(() => null) as { access_token?: string; error_description?: string } | null;
      if (!response.ok || !data?.access_token) {
        throw new Error(data?.error_description || "匿名终端认证失败");
      }
      return data.access_token;
    })();
  }
  return accessToken;
}

function actorToken() {
  const key = "triangle-agency-device-token";
  const stored = localStorage.getItem(key);
  if (stored && /^[a-f0-9-]{36,64}$/i.test(stored)) return stored;
  const created = crypto.randomUUID();
  localStorage.setItem(key, created);
  return created;
}

async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
  const token = await ensureAnonymousSession();
  const response = await fetch(`${API_ROOT}/${name}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(params),
  });
  const body = await response.json().catch(() => null) as T | { message?: string; error?: string } | null;
  if (!response.ok) {
    const detail = body && typeof body === "object" && ("message" in body || "error" in body)
      ? body.message || body.error
      : null;
    throw new Error(detail || "云端终端暂时无响应");
  }
  return body as T;
}

export function createRoom(displayName: string) {
  return rpc<{ room: { code: string; name: string } }>("dice_create_room", {
    p_actor_token: actorToken(),
    p_display_name: displayName,
  });
}

export function joinRoom(code: string, displayName: string) {
  return rpc<{ room: { code: string; name: string } }>("dice_join_room", {
    p_actor_token: actorToken(),
    p_code: code,
    p_display_name: displayName,
  });
}

export function getRoomState<T>(code: string) {
  return rpc<T>("dice_get_room", {
    p_actor_token: actorToken(),
    p_code: code,
  });
}

export function submitRoll(
  code: string,
  mode: "public" | "secret",
  includeCorrection: boolean,
  secretDice: { count: number; sides: number; label: string },
) {
  return rpc("dice_roll", {
    p_actor_token: actorToken(),
    p_code: code,
    p_mode: mode,
    p_include_correction: includeCorrection,
    p_secret_count: secretDice.count,
    p_secret_sides: secretDice.sides,
    p_secret_label: secretDice.label,
  });
}
