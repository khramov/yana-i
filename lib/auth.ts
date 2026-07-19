import { cookies } from "next/headers";
import { randomBytes } from "crypto";
import { and, eq, gt } from "drizzle-orm";
import { db } from "@/lib/db";
import { sessions, users } from "@/lib/db/schema";

export const SESSION_COOKIE = "session";
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

export interface SessionUser {
  id: number;
  email: string;
}

/** Thrown by requireUser() when there is no valid session. Handlers map this to 401. */
export class UnauthorizedError extends Error {
  constructor() {
    super("Unauthorized");
    this.name = "UnauthorizedError";
  }
}

/** Create a session row and set the httpOnly cookie. Call only from route handlers. */
export async function createSession(userId: number): Promise<void> {
  const token = randomBytes(32).toString("hex");
  const now = Math.floor(Date.now() / 1000);
  const expiresAt = now + SESSION_TTL_SECONDS;
  db.insert(sessions).values({ token, userId, expiresAt, createdAt: now }).run();

  const store = await cookies();
  store.set(SESSION_COOKIE, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: SESSION_TTL_SECONDS,
  });
}

/** Delete the current session row and clear the cookie. Call only from route handlers. */
export async function destroySession(): Promise<void> {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (token) db.delete(sessions).where(eq(sessions.token, token)).run();
  store.delete(SESSION_COOKIE);
}

/** Resolve the signed-in user from the session cookie, or null. Safe in server components. */
export async function getSessionUser(): Promise<SessionUser | null> {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (!token) return null;

  const now = Math.floor(Date.now() / 1000);
  const row = db
    .select({ id: users.id, email: users.email })
    .from(sessions)
    .innerJoin(users, eq(sessions.userId, users.id))
    .where(and(eq(sessions.token, token), gt(sessions.expiresAt, now)))
    .get();

  return row ?? null;
}

/** Like getSessionUser but throws UnauthorizedError when there is no valid session. */
export async function requireUser(): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) throw new UnauthorizedError();
  return user;
}
