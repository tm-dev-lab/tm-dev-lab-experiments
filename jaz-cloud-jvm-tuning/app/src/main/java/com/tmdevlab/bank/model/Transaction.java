package com.tmdevlab.bank.model;

import java.time.Instant;

/** One immutable ledger entry. Amounts are in integer cents to avoid floating-point drift. */
public record Transaction(
        long id,
        String type,
        long amountCents,
        long balanceAfterCents,
        Instant at,
        String description) {
}
