import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE } from "@/lib/auth";

// Coarse, edge-safe gate: checks only for the presence of the session cookie.
// Authoritative validation (expiry, user lookup) happens in the protected layout
// and API handlers, which can reach the database.
const PUBLIC_PATHS = ["/login"];
const PUBLIC_API_PREFIX = "/api/auth";

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const hasSession = Boolean(req.cookies.get(SESSION_COOKIE)?.value);

  const isApi = pathname.startsWith("/api");
  const isPublic =
    PUBLIC_PATHS.includes(pathname) || pathname.startsWith(PUBLIC_API_PREFIX);

  if (hasSession || isPublic) return NextResponse.next();

  if (isApi) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const loginUrl = new URL("/login", req.url);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  // Run on everything except Next internals and static assets.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|svg|ico)$).*)"],
};
