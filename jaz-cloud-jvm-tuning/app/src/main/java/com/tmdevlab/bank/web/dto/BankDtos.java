package com.tmdevlab.bank.web.dto;

/** Request/response records for the bank API, grouped to keep the web layer compact. */
public final class BankDtos {

    private BankDtos() {
    }

    public record OpenRequest(long openingCents) {
    }

    public record AmountRequest(long amountCents, String description) {
    }

    public record TransferRequest(long fromId, long toId, long amountCents) {
    }

    public record IdResponse(long id) {
    }

    public record AccountResponse(long id, long balanceCents, int ledgerSize) {
    }

    public record TxResponse(long id, String type, long amountCents, long balanceAfterCents, String at, String description) {
    }

    public record StatsResponse(long accounts, long ioDelayMs) {
    }
}
