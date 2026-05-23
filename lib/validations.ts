import { z } from "zod";

export const transactionSchema = z
  .object({
    holdingId: z.number().int().positive(),
    type: z.enum(["buy", "sell", "dividend", "fee"]),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date must be YYYY-MM-DD"),
    shares: z.number().positive().nullable().optional(),
    price: z.number().positive().nullable().optional(),
    fee: z.number().min(0).optional(),
    tax: z.number().min(0).optional(),
    currency: z.string().min(1).optional(),
    notes: z.string().nullable().optional(),
  })
  .refine(
    (d) => {
      if (d.type === "buy" || d.type === "sell") {
        return d.shares != null && d.price != null;
      }
      return true;
    },
    { message: "Shares and price are required for buy/sell transactions", path: ["shares"] }
  );

export type TransactionInput = z.infer<typeof transactionSchema>;
