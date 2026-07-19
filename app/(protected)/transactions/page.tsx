import { TransactionTable } from "@/components/transactions/transaction-table";

export const metadata = { title: "Transactions — Yana" };

export default function TransactionsPage() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Transactions</h1>
      <TransactionTable />
    </main>
  );
}
