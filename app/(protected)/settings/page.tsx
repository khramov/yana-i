import { getSessionUser } from "@/lib/auth";
import { ChangePasswordForm } from "@/components/auth/change-password-form";

export default async function SettingsPage() {
  const user = await getSessionUser();

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-md mx-auto space-y-8">
        <div>
          <h1 className="text-2xl font-bold">Account settings</h1>
          <p className="text-muted-foreground text-sm mt-1">{user?.email}</p>
        </div>
        <ChangePasswordForm />
      </div>
    </main>
  );
}
