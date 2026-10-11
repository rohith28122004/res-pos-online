// GET /v1/reports/summary?from=YYYY-MM-DD&to=YYYY-MM-DD — owner session or host.

import { authenticateDevice, authenticateHost, isHostBearer } from "../auth/credentials";
import { requireReportsRole } from "../auth/permissions";
import { authenticateSession } from "../auth/session";
import { ApiError, jsonResponse } from "../http/errors";
import { isValidBusinessDate } from "../protocol/schemas";
import { buildSummary } from "../reports/summary";

function dateParam(url: URL, name: string): string {
  const value = url.searchParams.get(name);
  if (value === null || !isValidBusinessDate(value)) {
    throw new ApiError("VALIDATION", `Query parameter ${name} must be a YYYY-MM-DD business date`);
  }
  return value;
}

export async function handleSummary(request: Request, env: Env): Promise<Response> {
  let restaurantId: string;
  if (isHostBearer(request)) {
    restaurantId = (await authenticateHost(request, env.DB)).restaurantId;
  } else {
    const device = await authenticateDevice(request, env.DB);
    const session = await authenticateSession(request, env.DB, device);
    requireReportsRole(session.role);
    restaurantId = device.restaurantId;
  }
  const url = new URL(request.url);
  const report = await buildSummary(env.DB, restaurantId, dateParam(url, "from"), dateParam(url, "to"));
  return jsonResponse(report);
}
