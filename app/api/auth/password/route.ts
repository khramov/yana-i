import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { db } from "@/lib/db";
import { users, sessions } from "@/lib/db/schema";
import { and, eq, ne } from "drizzle-orm";
import { hashPassword, verifyPassword } from "@/lib/password";
import { getSessionUser, SESSION_COOKIE } from "@/lib/auth";

export async function POST(req: Request) {
  const sessionUser = await getSessionUser();
  if (!sessionUser) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json().catch(() => ({}));
  const currentPassword = typeof body.currentPassword === "string" ? body.currentPassword : "";
  const newPassword = typeof body.newPassword === "string" ? body.newPassword : "";

  if (newPassword.length < 8) {
    return NextResponse.json({ error: "New password must be at least 8 characters" }, { status: 400 });
  }

  const user = db.select().from(users).where(eq(users.id, sessionUser.id)).get();
  if (!user || !verifyPassword(currentPassword, user.passwordHash)) {
    return NextResponse.json({ error: "Current password is incorrect" }, { status: 400 });
  }

  db.update(users).set({ passwordHash: hashPassword(newPassword) }).where(eq(users.id, user.id)).run();

  // Revoke every other session so a leaked/old session can't outlive the change.
  const currentToken = (await cookies()).get(SESSION_COOKIE)?.value ?? "";
  db.delete(sessions)
    .where(and(eq(sessions.userId, user.id), ne(sessions.token, currentToken)))
    .run();

  return NextResponse.json({ ok: true });
}
